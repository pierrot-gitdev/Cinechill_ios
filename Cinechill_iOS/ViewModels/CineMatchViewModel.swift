//
//  CineMatchViewModel.swift
//  Cinechill_iOS
//

import Foundation

/// Le parcours CinéMatch v2 : deux questions, jusqu'à quatre comparaisons entre
/// films vus, puis cinq films. Ou, en un geste, la proposition du jour.
///
/// Le moteur est sur le serveur. Ce ViewModel ne classe rien : il tient la
/// séance (ce qui a été montré, ce qui a été choisi, combien de fois on a
/// hésité) et la transmet. Aucune mise à jour optimiste : chaque attente est un
/// état visible (`isLoadingRound`, `.loadingFive`, `.daily` sans film), et
/// l'écran ne change qu'une fois la réponse arrivée.
@Observable
@MainActor
final class CineMatchViewModel {
    enum Step: Equatable { case home, want, energy, comparison, loadingFive, five, daily, conclusion }
    enum ComparisonStage: Equatable { case keep, exclude }
    enum GalleryAddState: Equatable { case idle, adding, added, failed }

    private let client: any CineMatchFetching

    private(set) var step: Step = .home
    var situation: CineMatchSituation
    private(set) var want: CineMatchWant?
    private(set) var energy: CineMatchEnergy?

    // MARK: Questionnaire

    /// Le nombre de comparaisons annoncé (0 à 4). Connu à la réponse du
    /// premier tour : tant qu'il n'est pas arrivé, l'écran reste sur la
    /// question 2 avec `isLoadingRound`.
    private(set) var comparisonTotal = 0
    /// 1-based.
    private(set) var comparisonRound = 0
    private(set) var comparisonStage: ComparisonStage = .keep
    /// Les affiches affichées. Pendant le chargement du tour suivant, celles
    /// du tour joué restent en place : la vue peut y marquer l'écarté.
    private(set) var displayedFilms: [CineMatchGalleryFilm] = []
    /// L'affiche qui vient de prendre la place de la gardée (fondu).
    private(set) var freshFilmID: Int?
    private(set) var isLoadingRound = false

    var progressTotal: Int { 2 + comparisonTotal }

    var progressIndex: Int {
        switch step {
        case .home: return 0
        case .want: return 1
        case .energy: return 2
        case .comparison: return min(2 + comparisonRound, progressTotal)
        case .loadingFive, .five, .daily, .conclusion: return progressTotal
        }
    }

    /// « Un film qui plaît à tout le monde » n'a pas de sens pour quelqu'un seul.
    var availableWants: [CineMatchWant] {
        situation.company == .alone
            ? CineMatchWant.allCases.filter { $0 != .everyone }
            : CineMatchWant.allCases
    }

    // MARK: Résultats

    private(set) var films: [CineMatchFilm] = []
    private(set) var currentIndex = 0
    private(set) var widening: CineMatchWidening?
    private(set) var dailyFilm: CineMatchFilm?
    private(set) var concludedFilm: CineMatchFilm?
    private(set) var galleryAddState: GalleryAddState = .idle
    /// Non nil : la vue affiche `PlanEmptyState` et « Réessayer ».
    private(set) var errorMessage: String?

    // MARK: La séance (privé)

    /// Tous les films montrés en comparaison dans cette séance, remplaçants
    /// compris, dans l'ordre d'apparition et sans doublon.
    private var shownIDs: [Int] = []
    /// Les comparaisons jouées, dans l'ordre.
    private var history: [CineMatchComparison] = []
    /// Les « Annuler » et les retours. Ils survivent à `startGuided` : une
    /// hésitation n'a de valeur que pour la séance **suivante**, celle qui
    /// aboutit. Remis à zéro une fois transmis avec les cinq.
    private var hesitations = 0
    private var currentRoundData: CineMatchComparisonRound?
    private var keptFilm: CineMatchGalleryFilm?
    /// L'instant où les affiches (ou le remplaçant) sont apparues : l'origine
    /// de la latence d'une comparaison.
    private var appearedAt = ContinuousClock.now
    /// L'exposition des cinq, accumulée carte par carte, envoyée par
    /// `flushExposure`.
    private var pendingFiveExposure: [Int] = []
    /// La requête en cours. `cancel()` et `backToHome()` l'annulent : sa
    /// réponse, si elle arrive quand même, ne touche plus à l'écran.
    private var inflight: Task<Void, Never>?
    private var lastFailedAction: (@MainActor () async -> Void)?

    init(client: any CineMatchFetching = BackendCineMatchClient(), platformIDs: [String] = []) {
        self.client = client
        self.situation = CineMatchSituation(platformIDs: platformIDs)
    }

    // MARK: - Accueil

    func updateSituation(_ s: CineMatchSituation) {
        situation = s
    }

    /// Accueil → question 1. Repart d'une séance vierge, hésitations exceptées.
    func startGuided() {
        stopInflight()
        resetSession()
        films = []
        currentIndex = 0
        widening = nil
        concludedFilm = nil
        galleryAddState = .idle
        step = .want
    }

    // MARK: - Questions

    func chooseWant(_ w: CineMatchWant) {
        guard step == .want else { return }
        want = w
        step = .energy
    }

    /// Question 2 → premier tour de comparaison, ou directement les cinq quand
    /// la galerie ne permet aucune comparaison.
    func chooseEnergy(_ e: CineMatchEnergy) async {
        guard step == .energy, !isLoadingRound else { return }
        energy = e
        await perform { [weak self] in await self?.loadRound(1) }
    }

    // MARK: - Comparaisons

    /// Le premier geste : la gardée cède sa place à son remplaçant (ou disparaît
    /// si la galerie est épuisée), et on demande laquelle écarter.
    func keep(_ film: CineMatchGalleryFilm) {
        guard step == .comparison, comparisonStage == .keep, !isLoadingRound,
              errorMessage == nil,
              let index = displayedFilms.firstIndex(where: { $0.id == film.id })
        else { return }
        keptFilm = film
        if let replacement = currentRoundData?.replacements[film.id] {
            displayedFilms[index] = replacement
            freshFilmID = replacement.id
            appendShown([replacement.id])
            recordPosterExposure([replacement.id])
        } else {
            displayedFilms.remove(at: index)
            freshFilmID = nil
        }
        comparisonStage = .exclude
        appearedAt = .now
    }

    /// Le second geste : la comparaison est jouée. Le duel part au serveur sans
    /// qu'on l'attende (son échec est sans conséquence pour la séance, qui
    /// transmet elle-même son historique), puis le tour suivant se charge.
    func exclude(_ film: CineMatchGalleryFilm) async {
        guard step == .comparison, comparisonStage == .exclude, !isLoadingRound,
              errorMessage == nil,
              let kept = keptFilm, kept.id != film.id,
              displayedFilms.contains(where: { $0.id == film.id })
        else { return }
        history.append(.pick(keptID: kept.id, excludedID: film.id, latencyMs: elapsedMs()))
        let client = client
        Task { try? await client.recordDuel(winnerID: kept.id, loserID: film.id) }
        await advanceAfterComparison()
    }

    /// « Aucun des quatre ce soir » : rien ne tente parmi les affiches
    /// affichées. Avant comme après une garde, on passe au tour suivant.
    func noneOfThese() async {
        guard step == .comparison, !isLoadingRound, errorMessage == nil,
              !displayedFilms.isEmpty
        else { return }
        history.append(.none(shownIDs: displayedFilms.map(\.id)))
        await advanceAfterComparison()
    }

    /// « Annuler » : retour à l'accueil, compté comme une hésitation.
    func cancel() {
        hesitations += 1
        stopInflight()
        resetSession()
        step = .home
    }

    // MARK: - Résultats

    func showCard(at index: Int) {
        guard films.indices.contains(index) else { return }
        currentIndex = index
        queueFiveExposure(films[index].id)
    }

    /// Accueil → la proposition du jour. `.daily` sans film et sans erreur :
    /// le chargement.
    func openDaily() async {
        guard step == .home else { return }
        stopInflight()
        dailyFilm = nil
        concludedFilm = nil
        galleryAddState = .idle
        errorMessage = nil
        lastFailedAction = nil
        step = .daily
        await perform { [weak self] in await self?.loadDaily() }
    }

    /// Le lancement part au serveur sans être attendu ; la vue ouvre l'URL.
    func start(_ film: CineMatchFilm) {
        let client = client
        Task { try? await client.recordLaunch(tmdbID: film.id) }
        concludedFilm = film
        galleryAddState = .idle
        step = .conclusion
        flushExposureInBackground()
    }

    func beginGalleryAdd() {
        guard galleryAddState == .idle || galleryAddState == .failed else { return }
        galleryAddState = .adding
    }

    func finishGalleryAdd(success: Bool) {
        guard galleryAddState == .adding else { return }
        galleryAddState = success ? .added : .failed
    }

    /// Conclusion, proposition du jour ou erreur → accueil. Quitter une
    /// proposition ou des questions sans erreur compte comme une hésitation ;
    /// sortir d'une erreur ou d'une conclusion, non.
    func backToHome() {
        if errorMessage == nil, [.want, .energy, .comparison, .five, .daily].contains(step) {
            hesitations += 1
        }
        stopInflight()
        resetSession()
        step = .home
        flushExposureInBackground()
    }

    /// Rejoue la dernière requête en échec.
    func retry() async {
        guard let action = lastFailedAction else { return }
        lastFailedAction = nil
        errorMessage = nil
        await perform(action)
    }

    /// Envoie l'exposition des cinq accumulée. Le tampon est vidé avant
    /// l'envoi : deux appels rapprochés n'écrivent pas deux fois.
    func flushExposure() async {
        guard !pendingFiveExposure.isEmpty else { return }
        let ids = pendingFiveExposure
        pendingFiveExposure = []
        try? await client.recordExposure(kind: .five, tmdbIDs: ids)
    }

    // MARK: - Chargements

    private func loadRound(_ round: Int) async {
        isLoadingRound = true
        errorMessage = nil
        do {
            let result = try await client.comparisonRound(
                round: round, shownIDs: shownIDs, history: history, forDoor: false
            )
            guard !Task.isCancelled else { return }
            isLoadingRound = false
            if round == 1 { comparisonTotal = max(0, min(4, result.total)) }
            // Deux affiches au moins : garder puis écarter en demande deux.
            guard round <= result.total, round <= comparisonTotal, result.films.count >= 2 else {
                // La barre ne doit pas annoncer des comparaisons qui n'auront
                // pas lieu.
                comparisonTotal = min(comparisonTotal, round - 1)
                await loadFive()
                return
            }
            present(result, round: round)
        } catch {
            isLoadingRound = false
            fail(error) { [weak self] in await self?.loadRound(round) }
        }
    }

    private func present(_ result: CineMatchComparisonRound, round: Int) {
        currentRoundData = result
        comparisonRound = round
        comparisonStage = .keep
        keptFilm = nil
        freshFilmID = nil
        displayedFilms = result.films
        let ids = result.films.map(\.id)
        appendShown(ids)
        recordPosterExposure(ids)
        step = .comparison
        appearedAt = .now
    }

    private func advanceAfterComparison() async {
        let next = comparisonRound + 1
        if next <= comparisonTotal {
            await perform { [weak self] in await self?.loadRound(next) }
        } else {
            await perform { [weak self] in await self?.loadFive() }
        }
    }

    private func loadFive() async {
        guard let want, let energy else { return }
        step = .loadingFive
        errorMessage = nil
        do {
            let response = try await client.five(
                situation: situation, want: want, energy: energy,
                comparisons: history, hesitations: hesitations
            )
            guard !Task.isCancelled else { return }
            guard !response.films.isEmpty else {
                fail(CineMatchClientError.noCandidates) { [weak self] in await self?.loadFive() }
                return
            }
            hesitations = 0
            films = response.films
            widening = response.widening
            currentIndex = 0
            pendingFiveExposure = []
            step = .five
            // La première carte est à l'écran dès l'arrivée ; les suivantes
            // passent par `showCard`.
            queueFiveExposure(response.films[0].id)
        } catch {
            fail(error) { [weak self] in await self?.loadFive() }
        }
    }

    private func loadDaily() async {
        errorMessage = nil
        do {
            let film = try await client.daily(situation: situation)
            guard !Task.isCancelled else { return }
            guard let film else {
                fail(CineMatchClientError.noCandidates) { [weak self] in await self?.loadDaily() }
                return
            }
            dailyFilm = film
            let client = client
            Task { try? await client.recordExposure(kind: .daily, tmdbIDs: [film.id]) }
        } catch {
            fail(error) { [weak self] in await self?.loadDaily() }
        }
    }

    // MARK: - Mécanique

    /// Lance le travail dans une tâche gardée, pour que `cancel()` puisse
    /// l'interrompre, et l'attend : l'appelant reste `async` jusqu'au bout.
    private func perform(_ work: @escaping @MainActor () async -> Void) async {
        inflight?.cancel()
        let task = Task { await work() }
        inflight = task
        await task.value
    }

    private func stopInflight() {
        inflight?.cancel()
        inflight = nil
        isLoadingRound = false
    }

    private func fail(_ error: Error, retry: @escaping @MainActor () async -> Void) {
        if error is CancellationError || Task.isCancelled { return }
        lastFailedAction = retry
        errorMessage = error.localizedDescription
    }

    private func resetSession() {
        want = nil
        energy = nil
        comparisonTotal = 0
        comparisonRound = 0
        comparisonStage = .keep
        displayedFilms = []
        freshFilmID = nil
        currentRoundData = nil
        keptFilm = nil
        shownIDs = []
        history = []
        errorMessage = nil
        lastFailedAction = nil
    }

    private func appendShown(_ ids: [Int]) {
        for id in ids where !shownIDs.contains(id) {
            shownIDs.append(id)
        }
    }

    private func queueFiveExposure(_ id: Int) {
        guard !pendingFiveExposure.contains(id) else { return }
        pendingFiveExposure.append(id)
    }

    /// Les affiches de comparaison partent tout de suite : une séance annulée
    /// ne passe jamais par `flushExposure`, et une affiche vue reste vue.
    private func recordPosterExposure(_ ids: [Int]) {
        guard !ids.isEmpty else { return }
        let client = client
        Task { try? await client.recordExposure(kind: .poster, tmdbIDs: ids) }
    }

    private func flushExposureInBackground() {
        guard !pendingFiveExposure.isEmpty else { return }
        Task { [weak self] in await self?.flushExposure() }
    }

    private func elapsedMs() -> Int {
        let components = appearedAt.duration(to: .now).components
        let ms = components.seconds * 1000 + components.attoseconds / 1_000_000_000_000_000
        return max(0, Int(ms))
    }
}
