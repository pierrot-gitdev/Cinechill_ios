//
//  CineMatchViewModel.swift
//  Cinechill_iOS
//

import Foundation

/// Le parcours CinéMatch : un style, un de ses films comme point de départ,
/// un second film pour préciser la direction, une retouche (« Comme Heat,
/// mais… ? »), puis cinq films proches. Ou, en un geste, la proposition du
/// jour.
///
/// Les deux questions et les quatre comparaisons du soir ont laissé la place
/// à ces deux touchers (lot 1, octobre 2026). Mesurées, les questions ne
/// départageaient presque rien. Un film qu'on aime dit d'un coup ce qu'on
/// cherche ce soir, et le moteur sait trouver ce qui lui ressemble.
///
/// Le même parcours sert les séries, sur l'autre profil.
///
/// Le moteur est sur le serveur. Ce ViewModel ne classe rien : il tient la
/// séance (le style, le film de départ, les films marqués parmi les cinq) et
/// la transmet. Aucune mise à jour optimiste : chaque attente est un état
/// visible (`isLoadingStyles`, `pendingStyle`, `isLoadingStarters`,
/// `.loadingFive`, `.daily` sans film), et l'écran ne change qu'une fois la
/// réponse arrivée.
@Observable
@MainActor
final class CineMatchViewModel {
    /// `.style` et `.anchor` sont les deux écrans du départ ; `.refine`
    /// (« Plutôt du côté de… ? ») et `.tweak` (« Comme Heat, mais… ? »)
    /// affinent, et se passent quand le serveur n'a rien à y proposer ;
    /// `.loadingFive` est l'attente des cinq.
    ///
    /// Deux touchers ne suffisaient pas (retour de Pierre, 12 octobre) : le
    /// film choisi dit le genre d'histoire, pas la direction ni le ton.
    enum Step: Equatable { case home, style, anchor, refine, tweak, loadingFive, five, daily, conclusion }

    /// Ce qu'on a dit d'un des cinq. Un film marqué ne se lance plus : il se
    /// remplace, avec les autres films marqués, en un seul calcul.
    enum Mark: Equatable {
        case seen(loved: Bool)
        /// « Pas celui-là ».
        case refused
    }

    private let client: any CineMatchFetching

    private(set) var step: Step = .home
    var situation: CineMatchSituation
    /// Films ou séries : le profil sur lequel le parcours travaille.
    private(set) var format: MediaFormat = .film
    /// La durée retenue pour l'autre format. Une durée de film et une durée
    /// d'épisode ne se mesurent pas pareil : chaque format garde la sienne,
    /// la compagnie et les plateformes restent communes.
    private var parkedDurations: [MediaFormat: CineMatchDuration] = [:]

    // MARK: Le départ

    /// Les styles chargés, par format, et quand. Un format n'emprunte jamais
    /// les styles de l'autre.
    private var styleCache: [MediaFormat: StyleCacheEntry] = [:]
    private(set) var isLoadingStyles = false
    /// L'accueil prépare les styles en silence (`prepareStyles`).
    private var isPreparingStyles = false
    /// Le style touché, le temps que ses films arrivent : sa tuile le dit.
    private(set) var pendingStyle: CineMatchStyle?
    /// Le style des films de départ affichés. `nil` après « Peu importe ».
    private(set) var selectedStyle: CineMatchStyle?
    /// Les six films de départ affichés.
    private(set) var starterPage: CineMatchStarterPage?
    /// « Pas ceux-là » : la page suivante se charge, les six restent en place.
    private(set) var isLoadingStarters = false
    /// Le film de départ des cinq. `nil` après « Peu importe ».
    private(set) var anchor: CineMatchGalleryFilm?
    /// Les voisins du film de départ et les retouches qui ont un sens pour
    /// lui. `nil` tant qu'ils ne sont pas arrivés.
    private(set) var nearPage: CineMatchNearPage?
    /// Le film de départ touché, le temps que ses voisins arrivent.
    private(set) var isLoadingNear = false
    /// Le second film (« Plutôt du côté de… ? »). `nil` : « Pile comme ».
    private(set) var secondFilm: CineMatchGalleryFilm?
    /// La retouche (« Comme Heat, mais… ? »). `nil` : « Pareil ».
    private(set) var chosenTweak: CineMatchTweak?

    /// Les styles du format courant, du plus présent dans la galerie au moins
    /// présent. Vide tant qu'ils n'ont pas été chargés.
    var styleTiles: [CineMatchStyleTile] { styleCache[format]?.tiles ?? [] }

    /// Les six tuiles de l'écran : les styles les plus présents dans la
    /// galerie, parmi ceux qui en ont au moins un film. Une galerie qui n'a
    /// encore aucun film classé les montre tous : le serveur complète alors
    /// chaque style avec ses films les plus connus.
    var mainStyles: [CineMatchStyleTile] {
        let present = styleTiles.filter { $0.count > 0 }
        return present.isEmpty ? styleTiles : Array(present.prefix(Self.mainStyleCount))
    }

    /// Les styles de « Un autre style », dans le même ordre.
    var otherStyles: [CineMatchStyleTile] {
        let main = Set(mainStyles.map(\.style))
        return styleTiles.filter { !main.contains($0.style) }
    }

    // MARK: Résultats

    private(set) var films: [CineMatchFilm] = []
    private(set) var currentIndex = 0
    private(set) var widening: CineMatchWidening?
    private(set) var dailyFilm: CineMatchFilm?
    /// La proposition du jour remplace un film qu'on vient de ranger en
    /// galerie : l'écran le dit, et l'attente parle d'un autre film.
    private(set) var dailyReplacedSeen = false
    private(set) var concludedFilm: CineMatchFilm?
    /// Non nil : la vue affiche `PlanEmptyState` et « Réessayer ».
    private(set) var errorMessage: String?

    // MARK: Films marqués

    /// Ce qui est arrivé au dernier remplacement des films marqués.
    enum ReplaceOutcome: Equatable {
        /// `count` films remplacés, `dropped` sans remplaçant (et retirés).
        /// `seen` : combien des films partis étaient déjà vus. Eux seuls sont
        /// entrés en galerie, et la phrase le dit.
        case replaced(count: Int, dropped: Int, seen: Int)
        case failed
    }

    /// Les films de la proposition marqués « déjà vu » ou « pas celui-là ».
    /// Marquer ne recalcule rien : on peut en marquer plusieurs, et le calcul
    /// ne part qu'une fois, pour tous (`replaceMarked`).
    private(set) var marks: [Int: Mark] = [:]
    /// Les films arrivés au dernier remplacement.
    private(set) var freshFilmIDs: Set<Int> = []
    private(set) var isReplacing = false
    private(set) var replaceOutcome: ReplaceOutcome?
    /// La séance écrite par le serveur pour ces cinq films.
    private var sessionID: String?
    /// La soirée en cours : un identifiant tiré à chaque départ, envoyé avec
    /// chaque appel. Le serveur y range chaque écran et chaque geste (voir
    /// `journalEvening`) ; c'est ce journal qui permettra au moteur
    /// d'apprendre de ce que les gens font vraiment.
    private(set) var eveningID = CineMatchViewModel.newEveningID()

    /// 32 caractères hexadécimaux, sans tiret : le format que le serveur accepte.
    static func newEveningID() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "")
    }
    /// Le film de départ et le style des cinq affichés : un remplacement se
    /// calcule sur les mêmes.
    private var fiveAnchorID: Int?
    private var fiveSecondID: Int?
    private var fiveTweak: CineMatchTweak?
    private var fiveStyle: CineMatchStyle?

    var markedCount: Int { films.filter { marks[$0.id] != nil }.count }

    // MARK: La séance (privé)

    /// Les films de départ montrés depuis qu'on est sur leur écran, toutes
    /// pages confondues. Ils partent comme affiches vues **en quittant
    /// l'écran**, pas à leur arrivée : le serveur repousse en fin d'ordre
    /// les affiches vues ces quatorze derniers jours, et noter la première
    /// page dès son arrivée aurait décalé l'ordre sous « Pas ceux-là ». Dans
    /// un petit style, la page suivante aurait ramené les six mêmes.
    private var visitStarterIDs: [Int] = []
    /// Les films de départ montrés depuis le dernier retour au début du
    /// style. « Pas ceux-là » les envoie : le serveur les écarte des six
    /// suivants. Compter les pages ne suffisait pas : l'ordre du serveur
    /// bouge tant que les fiches du style entrent en cache, et la deuxième
    /// page remontrait des films de la première.
    private var cycleStarterIDs: [Int] = []
    /// L'exposition des cinq, accumulée carte par carte, envoyée par
    /// `flushExposure`.
    private var pendingFiveExposure: [Int] = []
    /// La requête en cours. `goBack()` et `backToHome()` l'annulent : sa
    /// réponse, si elle arrive quand même, ne touche plus à l'écran.
    private var inflight: Task<Void, Never>?
    private var lastFailedAction: (@MainActor () async -> Void)?

    private static let mainStyleCount = 6
    /// Au-delà, l'écran des styles se recharge : la galerie a pu bouger.
    private static let styleFreshness: Duration = .seconds(600)

    private struct StyleCacheEntry {
        let tiles: [CineMatchStyleTile]
        let loadedAt: ContinuousClock.Instant
    }

    init(client: any CineMatchFetching = BackendCineMatchClient(), platformIDs: [String] = []) {
        self.client = client
        self.situation = CineMatchSituation(platformIDs: platformIDs)
    }

    // MARK: - Accueil

    func updateSituation(_ s: CineMatchSituation) {
        situation = s
    }

    /// L'interrupteur a basculé. Il ne se montre qu'à l'accueil et devant la
    /// Porte, jamais au milieu d'une recherche : la séance en cours, s'il en
    /// reste une, est abandonnée, puisqu'elle ne parlait pas du même profil.
    func setFormat(_ newFormat: MediaFormat) {
        guard newFormat != format else { return }
        recordStarterExposure()
        stopInflight()
        resetSession()
        parkedDurations[format] = situation.duration
        situation.duration = parkedDurations[newFormat] ?? .any
        format = newFormat
        films = []
        currentIndex = 0
        widening = nil
        dailyFilm = nil
        dailyReplacedSeen = false
        concludedFilm = nil
        pendingFiveExposure = []
        step = .home
    }

    /// L'accueil prépare l'écran des styles pendant qu'on le regarde :
    /// « Trouver mon film » s'ouvre alors sans attente. Un échec ici ne se
    /// montre pas ; l'écran des styles réessaiera, et lui le dira.
    func prepareStyles() async {
        guard step == .home, !stylesAreFresh, !isPreparingStyles else { return }
        let format = format
        isPreparingStyles = true
        defer { isPreparingStyles = false }
        guard let tiles = try? await client.styles(format: format, evening: nil) else { return }
        styleCache[format] = StyleCacheEntry(tiles: tiles, loadedAt: .now)
    }

    /// Accueil → l'écran des styles. Repart d'une séance vierge.
    func startGuided() async {
        stopInflight()
        resetSession()
        films = []
        currentIndex = 0
        widening = nil
        concludedFilm = nil
        step = .style
        guard !stylesAreFresh else { return }
        // Posé avant la tâche : entre les deux, l'écran des styles se serait
        // cru chargé et vide.
        isLoadingStyles = true
        await perform { [weak self] in await self?.loadStyles() }
    }

    // MARK: - Le départ

    /// Un style touché : ses six films arrivent, puis l'écran change.
    func chooseStyle(_ style: CineMatchStyle) async {
        guard step == .style, pendingStyle == nil, !isLoadingStyles, errorMessage == nil else { return }
        pendingStyle = style
        await perform { [weak self] in await self?.loadStarters(style: style, page: 0, shownIDs: []) }
    }

    /// « Pas ceux-là » : les six suivants du même style.
    func moreStarters() async {
        guard step == .anchor, !isLoadingStarters, errorMessage == nil,
              let page = starterPage, page.hasMore
        else { return }
        let shown = cycleStarterIDs
        await perform { [weak self] in
            await self?.loadStarters(style: page.style, page: page.page + 1, shownIDs: shown)
        }
    }

    /// Un film de départ touché : ses voisins arrivent, puis l'écran passe
    /// à « Plutôt du côté de… ? », ou directement à la suite s'il n'y a rien
    /// à y proposer.
    func chooseAnchor(_ film: CineMatchGalleryFilm) async {
        guard step == .anchor, !isLoadingStarters, !isLoadingNear, errorMessage == nil,
              starterPage?.films.contains(where: { $0.id == film.id }) == true
        else { return }
        recordStarterExposure()
        anchor = film
        secondFilm = nil
        chosenTweak = nil
        nearPage = nil
        await perform { [weak self] in await self?.loadNear(for: film) }
    }

    /// « Plutôt du côté de… ? » : un second film touché.
    func chooseSecond(_ film: CineMatchGalleryFilm) async {
        guard step == .refine, nearPage?.films.contains(where: { $0.id == film.id }) == true else { return }
        secondFilm = film
        await advanceAfterRefine()
    }

    /// « Pile comme Heat » : pas de second film.
    func skipSecond() async {
        guard step == .refine else { return }
        secondFilm = nil
        await advanceAfterRefine()
    }

    /// « Comme Heat, mais… ? » : une retouche, ou `nil` pour « Pareil ».
    func chooseTweak(_ tweak: CineMatchTweak?) async {
        guard step == .tweak else { return }
        if let tweak, nearPage?.tweaks.contains(tweak) != true { return }
        chosenTweak = tweak
        await perform { [weak self] in await self?.loadFive() }
    }

    /// Assez de voisins pour que choisir parmi eux veuille dire quelque chose.
    private var hasNearFilms: Bool { (nearPage?.films.count ?? 0) >= 2 }
    private var hasTweaks: Bool { !(nearPage?.tweaks.isEmpty ?? true) }

    private func advanceAfterAnchor() async {
        if hasNearFilms {
            step = .refine
        } else if hasTweaks {
            step = .tweak
        } else {
            await loadFive()
        }
    }

    private func advanceAfterRefine() async {
        if hasTweaks {
            step = .tweak
        } else {
            await perform { [weak self] in await self?.loadFive() }
        }
    }

    /// « Peu importe, propose-moi » : pas de film de départ, les cinq
    /// viennent des coups de cœur et de la réception des films.
    func chooseAnyStyle() async {
        guard step == .style, pendingStyle == nil, errorMessage == nil else { return }
        anchor = nil
        secondFilm = nil
        chosenTweak = nil
        nearPage = nil
        selectedStyle = nil
        await perform { [weak self] in await self?.loadFive() }
    }

    /// « Retour » : une marche en arrière, jusqu'au dernier écran où l'on a
    /// répondu. Des cinq à la retouche, de la retouche au second film, du
    /// second film aux films de départ, puis aux styles et à l'accueil. Ce
    /// qu'on retrouve est ce qu'on avait laissé, sans nouveau chargement.
    func goBack() {
        switch step {
        case .loadingFive, .five:
            stopInflight()
            flushExposureInBackground()
            clearFive()
            errorMessage = nil
            lastFailedAction = nil
            chosenTweak = nil
            if anchor == nil {
                step = .style
            } else if hasTweaks {
                step = .tweak
            } else if hasNearFilms {
                secondFilm = nil
                step = .refine
            } else {
                leaveRefinement()
            }
        case .tweak:
            errorMessage = nil
            lastFailedAction = nil
            chosenTweak = nil
            if hasNearFilms {
                secondFilm = nil
                step = .refine
            } else {
                leaveRefinement()
            }
        case .refine:
            errorMessage = nil
            lastFailedAction = nil
            leaveRefinement()
        case .anchor:
            recordStarterExposure()
            stopInflight()
            errorMessage = nil
            lastFailedAction = nil
            starterPage = nil
            selectedStyle = nil
            cycleStarterIDs = []
            step = .style
        case .style, .home, .daily, .conclusion:
            backToHome()
        }
    }

    /// Retour aux films de départ : le film touché ne l'est plus.
    private func leaveRefinement() {
        stopInflight()
        anchor = nil
        secondFilm = nil
        chosenTweak = nil
        nearPage = nil
        step = starterPage != nil ? .anchor : .style
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
        dailyReplacedSeen = false
        concludedFilm = nil
        errorMessage = nil
        lastFailedAction = nil
        eveningID = Self.newEveningID()
        step = .daily
        await perform { [weak self] in await self?.loadDaily() }
    }

    /// Le lancement part au serveur sans être attendu ; la vue ouvre l'URL.
    func start(_ film: CineMatchFilm) {
        let client = client
        let format = format
        let evening = eveningID
        Task { try? await client.recordLaunch(tmdbID: film.id, format: format, evening: evening) }
        concludedFilm = film
        step = .conclusion
        flushExposureInBackground()
    }

    // MARK: - Films marqués

    func markSeen(_ film: CineMatchFilm, loved: Bool) {
        guard step == .five, films.contains(where: { $0.id == film.id }) else { return }
        marks[film.id] = .seen(loved: loved)
        replaceOutcome = nil
    }

    /// « Pas celui-là ». Le refus part au serveur tout de suite, sans être
    /// attendu : c'est le refus d'un film précis, dans cette séance, et il
    /// compte même si l'on ne remplace rien. Revenir dessus (« Je le garde,
    /// en fait ») ne l'efface pas : l'hésitation reste un signal.
    func markRefused(_ film: CineMatchFilm) {
        guard step == .five, films.contains(where: { $0.id == film.id }) else { return }
        marks[film.id] = .refused
        replaceOutcome = nil
        let client = client
        let format = format
        let evening = eveningID
        Task { try? await client.recordPass(tmdbID: film.id, format: format, evening: evening) }
    }

    func unmark(_ film: CineMatchFilm) {
        marks[film.id] = nil
        replaceOutcome = nil
    }

    /// Un seul calcul pour tous les films marqués. Les autres gardent leur
    /// place : on ne perd pas ce qu'on a déjà regardé. Chaque film marqué cède
    /// la sienne à un remplaçant, dans l'ordre ; s'il en manque, la place
    /// disparaît plutôt que de garder un film qu'on a déjà vu ou écarté.
    func replaceMarked() async {
        guard step == .five, !isReplacing else { return }
        let marked = films.filter { marks[$0.id] != nil }
        guard !marked.isEmpty else { return }
        let keepIDs = films.filter { marks[$0.id] == nil }.map(\.id)
        let refusedIDs = marked.filter { marks[$0.id] == .refused }.map(\.id)
        let seenIDs = marked.filter { marks[$0.id] != .refused }.map(\.id)

        isReplacing = true
        replaceOutcome = nil
        defer { isReplacing = false }
        do {
            let response = try await client.picks(
                situation: situation, anchorID: fiveAnchorID, secondID: fiveSecondID, tweak: fiveTweak,
                style: fiveStyle, format: format,
                replacing: CineMatchReplacement(
                    sessionID: sessionID, keepIDs: keepIDs, seenIDs: seenIDs, refusedIDs: refusedIDs
                ),
                evening: eveningID
            )
            guard !Task.isCancelled, step == .five else { return }
            var spares = response.films
                .filter { !keepIDs.contains($0.id) && marks[$0.id] == nil }
                .makeIterator()
            var next: [CineMatchFilm] = []
            var arrived: Set<Int> = []
            for film in films {
                if marks[film.id] == nil {
                    next.append(film)
                } else if let spare = spares.next() {
                    next.append(spare)
                    arrived.insert(spare.id)
                }
            }
            // Plus rien à proposer : on garde la proposition et ses marques,
            // l'écran le dit.
            guard !next.isEmpty else {
                replaceOutcome = .replaced(count: 0, dropped: marked.count, seen: seenIDs.count)
                return
            }
            let firstArrival = next.firstIndex { arrived.contains($0.id) }
            films = next
            marks = [:]
            freshFilmIDs = arrived
            replaceOutcome = .replaced(count: arrived.count, dropped: marked.count - arrived.count, seen: seenIDs.count)
            currentIndex = firstArrival ?? min(currentIndex, next.count - 1)
            queueFiveExposure(films[currentIndex].id)
        } catch {
            if error is CancellationError || Task.isCancelled { return }
            replaceOutcome = .failed
        }
    }

    /// Conclusion, proposition du jour, erreur ou « Annuler » → accueil.
    func backToHome() {
        if step == .anchor { recordStarterExposure() }
        stopInflight()
        // Avant la remise à zéro : l'exposition appartient à la soirée qui
        // s'achève, pas à celle qui commence.
        flushExposureInBackground()
        resetSession()
        step = .home
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
        try? await client.recordExposure(kind: .five, tmdbIDs: ids, format: format, evening: eveningID)
    }

    // MARK: - Chargements

    private var stylesAreFresh: Bool {
        guard let entry = styleCache[format] else { return false }
        return entry.loadedAt.duration(to: .now) < Self.styleFreshness
    }

    private func loadStyles() async {
        isLoadingStyles = true
        errorMessage = nil
        let format = format
        do {
            let tiles = try await client.styles(format: format, evening: eveningID)
            guard !Task.isCancelled else { return }
            isLoadingStyles = false
            styleCache[format] = StyleCacheEntry(tiles: tiles, loadedAt: .now)
        } catch {
            isLoadingStyles = false
            fail(error) { [weak self] in await self?.loadStyles() }
        }
    }

    private func loadStarters(style: CineMatchStyle, page: Int, shownIDs: [Int]) async {
        isLoadingStarters = true
        errorMessage = nil
        do {
            let result = try await client.starters(style: style, page: page, shownIDs: shownIDs, format: format,
                                                   evening: eveningID)
            guard !Task.isCancelled else { return }
            isLoadingStarters = false
            pendingStyle = nil
            selectedStyle = style
            starterPage = result
            let ids = result.films.map(\.id)
            for id in ids where !visitStarterIDs.contains(id) {
                visitStarterIDs.append(id)
            }
            cycleStarterIDs = shownIDs.isEmpty || result.restarted ? ids : cycleStarterIDs + ids
            step = .anchor
        } catch {
            isLoadingStarters = false
            pendingStyle = nil
            fail(error) { [weak self] in await self?.loadStarters(style: style, page: page, shownIDs: shownIDs) }
        }
    }

    /// Les voisins du film de départ. Ils décident des deux écrans suivants.
    private func loadNear(for film: CineMatchGalleryFilm) async {
        isLoadingNear = true
        errorMessage = nil
        do {
            let page = try await client.near(anchorID: film.id, format: format, evening: eveningID)
            guard !Task.isCancelled else { return }
            isLoadingNear = false
            nearPage = page
            await advanceAfterAnchor()
        } catch {
            isLoadingNear = false
            fail(error) { [weak self] in await self?.loadNear(for: film) }
        }
    }

    private func loadFive() async {
        let anchorID = anchor?.id
        let secondID = anchor == nil ? nil : secondFilm?.id
        let tweak = anchor == nil ? nil : chosenTweak
        let style = anchor == nil ? nil : selectedStyle
        step = .loadingFive
        errorMessage = nil
        do {
            let response = try await client.picks(
                situation: situation, anchorID: anchorID, secondID: secondID, tweak: tweak,
                style: style, format: format, replacing: nil, evening: eveningID
            )
            guard !Task.isCancelled else { return }
            guard !response.films.isEmpty else {
                fail(CineMatchClientError.noCandidates(for: format)) { [weak self] in await self?.loadFive() }
                return
            }
            films = response.films
            sessionID = response.sessionID
            fiveAnchorID = anchorID
            fiveSecondID = secondID
            fiveTweak = tweak
            fiveStyle = style
            marks = [:]
            freshFilmIDs = []
            replaceOutcome = nil
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

    /// « Je l'ai déjà vu » sur la proposition du jour : la vue l'a rangé en
    /// galerie, on en tire une autre. Le serveur l'écarte de lui-même, sans
    /// attendre que la galerie le montre.
    func replaceSeenDaily(_ film: CineMatchFilm) async {
        guard step == .daily, dailyFilm?.id == film.id else { return }
        dailyFilm = nil
        dailyReplacedSeen = true
        await perform { [weak self] in await self?.loadDaily(replacingSeen: film.id) }
    }

    private func loadDaily(replacingSeen seenID: Int? = nil) async {
        errorMessage = nil
        do {
            let film = try await client.daily(situation: situation, format: format,
                                              replacingSeen: seenID, evening: eveningID)
            guard !Task.isCancelled else { return }
            guard let film else {
                fail(CineMatchClientError.noCandidates(for: format)) { [weak self] in
                    await self?.loadDaily(replacingSeen: seenID)
                }
                return
            }
            dailyFilm = film
            let client = client
            let format = format
            let evening = eveningID
            Task { try? await client.recordExposure(kind: .daily, tmdbIDs: [film.id], format: format, evening: evening) }
        } catch {
            fail(error) { [weak self] in await self?.loadDaily(replacingSeen: seenID) }
        }
    }

    // MARK: - Mécanique

    /// Lance le travail dans une tâche gardée, pour que `goBack()` puisse
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
        isLoadingStyles = false
        isLoadingStarters = false
        isLoadingNear = false
        pendingStyle = nil
    }

    /// L'échec vient de la soirée, pas du réseau : réessayer n'y changerait
    /// rien, seul un réglage de « Ce soir » le peut.
    private(set) var failureIsNoCandidates = false

    private func fail(_ error: Error, retry: @escaping @MainActor () async -> Void) {
        if error is CancellationError || Task.isCancelled { return }
        lastFailedAction = retry
        if let known = error as? CineMatchClientError {
            failureIsNoCandidates = true
            errorMessage = known.errorDescription
        } else {
            failureIsNoCandidates = false
            // Le code HTTP et le corps de la réponse servent au rapport de bug,
            // pas à l'écran, où ils poussaient « Réessayer » hors de vue.
            // Une coupure réseau se dit à part : elle se règle chez soi, pas
            // en attendant.
            errorMessage = Self.isNetworkFailure(error)
                ? String(localized: "Connexion trop lente ou coupée. Vérifie ton réseau, puis réessaie.", bundle: .app)
                : String(localized: "Un souci de notre côté. Réessaie dans un instant.", bundle: .app)
        }
    }

    /// La requête n'a pas atteint le serveur : hors ligne, délai dépassé.
    private static func isNetworkFailure(_ error: Error) -> Bool {
        if error is URLError { return true }
        if let clientError = error as? RecommendationClientError, case .transport = clientError {
            return true
        }
        return false
    }

    private func resetSession() {
        eveningID = Self.newEveningID()
        pendingStyle = nil
        selectedStyle = nil
        starterPage = nil
        isLoadingStarters = false
        anchor = nil
        nearPage = nil
        isLoadingNear = false
        secondFilm = nil
        chosenTweak = nil
        visitStarterIDs = []
        cycleStarterIDs = []
        errorMessage = nil
        lastFailedAction = nil
        clearFive()
    }

    /// Les cinq et leurs marques. Les films eux-mêmes restent, le temps du
    /// fondu de sortie.
    private func clearFive() {
        marks = [:]
        freshFilmIDs = []
        replaceOutcome = nil
        isReplacing = false
        sessionID = nil
        fiveAnchorID = nil
        fiveSecondID = nil
        fiveTweak = nil
        fiveStyle = nil
    }

    private func queueFiveExposure(_ id: Int) {
        guard !pendingFiveExposure.contains(id) else { return }
        pendingFiveExposure.append(id)
    }

    /// Les films de départ vus pendant la visite de leur écran partent comme
    /// affiches vues, sans être attendus. Voir `visitStarterIDs`.
    private func recordStarterExposure() {
        guard !visitStarterIDs.isEmpty else { return }
        let ids = visitStarterIDs
        visitStarterIDs = []
        let client = client
        let format = format
        let evening = eveningID
        Task { try? await client.recordExposure(kind: .poster, tmdbIDs: ids, format: format, evening: evening) }
    }

    /// Le tampon et la soirée sont pris tout de suite : la tâche part après
    /// la remise à zéro qui suit souvent, et elle doit écrire dans la soirée
    /// qui s'achève.
    private func flushExposureInBackground() {
        guard !pendingFiveExposure.isEmpty else { return }
        let ids = pendingFiveExposure
        pendingFiveExposure = []
        let client = client
        let format = format
        let evening = eveningID
        Task { try? await client.recordExposure(kind: .five, tmdbIDs: ids, format: format, evening: evening) }
    }
}
