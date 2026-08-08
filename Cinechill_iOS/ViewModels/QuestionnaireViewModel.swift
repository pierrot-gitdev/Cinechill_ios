//
//  QuestionnaireViewModel.swift
//  Cinechill_iOS
//

import Foundation

/// Les questions du cœur adaptatif — celles que `QuestionEngine` choisit une par une.
///
/// Le socle n'y figure plus : avec qui, combien de temps et sous quelle forme tiennent
/// désormais sur un seul écran (`SessionFrameView`), les plateformes viennent des réglages,
/// et les genres se déduisent du cadran (`MoodTransfer`) au lieu d'être demandés.
enum QuestionStep: Int, CaseIterable, Hashable {
    case mood, mindset, dealbreaker, popularity, cast
    case horrorFlavor, comedyFlavor, dramaFlavor, cognitiveMode
    case storyOrigin, attachment, creditsMoment, lastingTrace
    case elimination, surpriseIntensity

    var title: String {
        switch self {
        case .mood: "Quelle ambiance ce soir ?"
        case .mindset: "Là, tout de suite, vous avez plutôt envie de…"
        case .dealbreaker: "Qu'est-ce qui vous ferait le plus décrocher d'un film ?"
        case .popularity: "Blockbuster ou pépite méconnue ?"
        case .cast: "Un casting que vous reconnaissez, ou l'envie de découvrir de nouvelles têtes ?"
        case .horrorFlavor: "Dans l'horreur, vous cherchez plutôt…"
        case .comedyFlavor: "Le genre de comédie que vous aimez ?"
        case .dramaFlavor: "Le drame qui vous touche le plus ?"
        case .cognitiveMode: "Face à l'inconnu, vous préférez…"
        case .storyOrigin: "S'il fallait choisir…"
        case .attachment: "Ce qui vous retient dans un film :"
        case .creditsMoment: "Le générique monte. Dans le meilleur des cas…"
        case .lastingTrace: "Le dernier film qui vous a vraiment marqué·e vous a laissé…"
        case .elimination: "Une chose est sûre : pas envie de ça ce soir"
        case .surpriseIntensity: "À quel point voulez-vous être surpris·e ?"
        }
    }

    var subtitle: String? {
        switch self {
        case .cognitiveMode: "Pas de bonne réponse — ça nous aide à cerner votre approche"
        case .storyOrigin: "Il faut trancher, même si les deux vous vont"
        case .lastingTrace: "On se connaît mieux au passé qu'au futur"
        case .elimination: "Écartez celui qui vous tente le moins"
        case .surpriseIntensity: "Des valeurs sûres jusqu'à l'inattendu total"
        default: nil
        }
    }
}

@Observable
@MainActor
final class QuestionnaireViewModel {
    enum Phase: Equatable {
        case intro
        /// Le cadre : avec qui, combien de temps, sous quelle forme. Un écran.
        case frame
        /// Le cadran : deux appuis, le trajet d'humeur de la soirée.
        case mood
        case poolLoading
        /// Le cœur adaptatif. Une seule phase — la découpe tier 1 / tier 2 a disparu
        /// avec le critère qui la rendait nécessaire (voir `AdaptiveDimension`).
        case asking
        case enriching
        case finalizing
        case results
        case error(String)
    }

    private let recommendationClient: any RecommendationFetching
    private let metadataClient: any HomeMetadataFetching

    /// Ce que le cadre et le cadran ont appris, compté comme deux réponses, pour que
    /// le compteur affiché reflète l'effort déjà fourni.
    private let fixedAnswersCount = 2

    private(set) var phase: Phase = .intro
    private(set) var availablePlatforms: [StreamingPlatform] = []
    private(set) var results: [RecommendationResult] = []
    private(set) var currentDimension: AdaptiveDimension?
    private(set) var pairwiseOptions: (CandidateRow, CandidateRow)?
    private(set) var eliminationOptions: [CandidateRow]?
    var answers = QuestionnaireAnswers()

    /// Les deux repères du cadran. Tant que `moodGoal` est nil, le trajet n'est pas
    /// posé et la séance ne peut pas démarrer.
    var moodNow: MoodPoint?
    var moodGoal: MoodPoint?

    /// La lecture : une ligne, affichée après une réponse qui apprend quelque chose
    /// de nommable. `nil` le reste du temps — mieux vaut se taire que commenter
    /// pour commenter.
    private(set) var reading: String?

    /// Renseignée quand le budget a été présélectionné d'après l'heure.
    private(set) var lateHourNote: String?

    /// Ce que la bibliothèque raconte. Chargé en fond dès le seuil : au moment où le
    /// cadran est validé, il est là depuis longtemps. S'il ne l'était pas, la séance
    /// démarrerait simplement sur un profil plat — jamais bloquée par son absence.
    private(set) var taste: TasteProfile = .empty

    /// Ce qu'on croit savoir de la personne. C'est la seule chose que le serveur
    /// recevra en plus des candidats : lui positionne les films, elle dit qui regarde.
    private(set) var belief = BeliefState()

    /// Le vivier de travail. Grossier au départ, remplacé par les candidats enrichis
    /// une fois leurs axes resserrés.
    private var pool: [CandidateRow] = []
    private var enrichedPool: [EnrichedCandidateRow] = []
    private var hasEnriched = false
    private var askedDimensions: Set<AdaptiveDimension> = []
    private var recentFormats: [QuestionFormat] = []
    private var lastFailedAction: (() async -> Void)?

    /// Un instantané complet de l'état, capturé juste avant que chaque question adaptative ne soit
    /// répondue — revenir en arrière restaure l'instantané tel quel plutôt que d'essayer d'annuler
    /// chaque mutation individuellement (croyance, vivier, dimensions déjà posées…).
    private struct AdaptiveSnapshot {
        let dimension: AdaptiveDimension?
        let pairwiseOptions: (CandidateRow, CandidateRow)?
        let eliminationOptions: [CandidateRow]?
        let answers: QuestionnaireAnswers
        let belief: BeliefState
        let pool: [CandidateRow]
        let enrichedPool: [EnrichedCandidateRow]
        let hasEnriched: Bool
        let askedDimensions: Set<AdaptiveDimension>
        let recentFormats: [QuestionFormat]
        let reading: String?
    }
    private var adaptiveHistory: [AdaptiveSnapshot] = []

    init(recommendationClient: any RecommendationFetching, metadataClient: any HomeMetadataFetching) {
        self.recommendationClient = recommendationClient
        self.metadataClient = metadataClient
    }

    // MARK: - Progression affichée

    var questionsAskedCount: Int { fixedAnswersCount + askedDimensions.count }

    /// Les abonnements retenus, tels qu'on les rappelle au seuil. Vide tant que la
    /// liste des fournisseurs n'est pas revenue — la ligne disparaît alors au lieu
    /// d'afficher des identifiants bruts.
    var selectedPlatformNames: [String] {
        availablePlatforms
            .filter { answers.platformIDs.contains($0.id) }
            .map(\.name)
    }

    // MARK: - Le seuil

    /// Ce que le seuil annonce. Le nombre de gestes n'est pas décoratif : il est
    /// tenu, parce qu'il est déduit du même trait qui raccourcira la séance.
    var openingTitle: String {
        taste.establishedAxisCount >= 5 ? "Bonsoir." : "Trois films, ce soir."
    }

    var openingNote: String {
        switch taste.establishedAxisCount {
        case 5...: "Deux gestes suffisent — on connaît le reste."
        case 2...4: "On se connaît un peu. Quelques questions, pas plus."
        default: "Deux réglages, deux appuis, quelques questions. Comptez deux minutes."
        }
    }

    /// La ligne de provenance, seulement quand elle a quelque chose à dire.
    var openingProvenance: String? {
        guard taste.galleryCount > 0 else { return nil }
        let films = "\(taste.galleryCount) film\(taste.galleryCount > 1 ? "s" : "")"
        let axes = taste.establishedAxisCount
        guard axes > 0 else { return "\(films) dans votre galerie" }
        return "\(films) vus · \(axes) trait\(axes > 1 ? "s" : "") cerné\(axes > 1 ? "s" : "")"
    }

    // MARK: - Le cadre

    var canAdvanceFrame: Bool {
        answers.audience != nil && answers.contentFormat != nil
    }

    /// - Parameters:
    ///   - preferredPlatformIDs: abonnements déclarés dans les réglages. Ils ne sont
    ///     plus demandés — seulement rappelés au seuil, et modifiables là où ils
    ///     vivent vraiment.
    ///   - bannedGenreIDs: genres exclus dans les réglages. Attention, le backend
    ///     n'en fait qu'un malus de score, pas un filtre dur : c'est
    ///     `QuestionnaireAnswers.apply(_:)` qui garantit qu'un genre banni ne sera
    ///     jamais demandé à TMDB.
    func start(preferredPlatformIDs: Set<String>, bannedGenreIDs: Set<Int> = []) {
        answers = QuestionnaireAnswers()
        answers.platformIDs = preferredPlatformIDs
        answers.avoidedGenreIDs = bannedGenreIDs
        presetBudgetForHour()
        belief = BeliefState()
        pool = []
        enrichedPool = []
        hasEnriched = false
        askedDimensions = []
        recentFormats = []
        adaptiveHistory = []
        currentDimension = nil
        pairwiseOptions = nil
        eliminationOptions = nil
        moodNow = nil
        moodGoal = nil
        reading = nil
        results = []
        phase = .frame
        Task { await loadPlatformsIfNeeded() }
        Task { await loadTasteProfile() }
    }

    /// Le trait n'est jamais requis : un échec réseau laisse simplement le profil
    /// plat, et la séance se déroule au questionnaire seul.
    func loadTasteProfile() async {
        guard let profile = try? await recommendationClient.fetchTasteProfile() else { return }
        taste = profile
    }

    /// Une correction posée sur la Fiche. On relit le profil derrière plutôt que de
    /// modifier l'état local : le serveur seul sait ce que la correction donne une
    /// fois recombinée avec ce que la bibliothèque raconte.
    func correctTaste(axis: Axis, value: Double?) async {
        try? await recommendationClient.setTasteCorrection(axis: axis, value: value)
        await loadTasteProfile()
    }

    // MARK: - La boucle

    /// Le film qu'on est allé lancer. C'est aussi ce qui ouvrira la question du
    /// lendemain — sans ce signal, on ne saurait jamais lequel des trois a servi.
    func recordLaunch(tmdbID: Int) {
        Task { try? await recommendationClient.recordLaunch(tmdbID: tmdbID) }
    }

    /// La réponse à la question du lendemain. On efface la question tout de suite —
    /// attendre le serveur pour retirer une carte à laquelle on vient de répondre
    /// donnerait l'impression que le geste n'a pas pris.
    func answerVerdict(_ verdict: FilmVerdict) {
        guard let pending = taste.pendingVerdict else { return }
        taste.pendingVerdict = nil
        Task {
            try? await recommendationClient.recordVerdict(tmdbID: pending.tmdbID, verdict: verdict)
            await loadTasteProfile()
        }
    }

    /// « Une autre fois » : on retire la carte pour cette ouverture, sans rien
    /// écrire. Le serveur la reproposera tant qu'elle n'a pas expiré.
    func dismissVerdict() {
        taste.pendingVerdict = nil
    }

    /// Passé une certaine heure, on part sur court — et on le dit. La note n'existe
    /// que parce que la présélection est réelle : annoncer une attention qu'on
    /// n'aurait pas serait pire que se taire.
    private func presetBudgetForHour() {
        let hour = Calendar.current.component(.hour, from: .now)
        let minute = Calendar.current.component(.minute, from: .now)
        guard hour >= 22 || (hour == 21 && minute >= 30) else {
            answers.runtime = .medium
            lateHourNote = nil
            return
        }
        answers.runtime = .short
        let formatted = String(format: "%dh%02d", hour, minute)
        lateHourNote = "Il est \(formatted) — on part sur quelque chose de court."
    }

    func loadPlatformsIfNeeded() async {
        guard availablePlatforms.isEmpty else { return }
        guard let providers = try? await metadataClient.movieProviders() else { return }
        availablePlatforms = StreamingPlatform.curated(from: providers)
    }

    func goNextFrame() {
        guard canAdvanceFrame else { return }
        phase = .mood
    }

    // MARK: - Le cadran

    var canConfirmMood: Bool { moodNow != nil && moodGoal != nil }

    /// La lecture du trajet, dès que les deux repères sont posés — affichée sous le
    /// cadran avant même de valider, pour que le geste ait une réponse immédiate.
    var moodStrategy: MoodStrategy? {
        guard let moodNow, let moodGoal else { return nil }
        return MoodStrategy.from(MoodTrajectory(now: moodNow, goal: moodGoal))
    }

    /// Ouvre la croyance avec ce que le cadre et le cadran ont appris, puis lance la
    /// séance. C'est ici, et seulement ici, que le trajet d'humeur entre dans le
    /// modèle : ensuite ce sont les questions et les affiches qui le corrigent.
    func confirmMood() {
        guard let moodNow, let moodGoal else { return }
        let trajectory = MoodTrajectory(now: moodNow, goal: moodGoal)
        let profile = MoodTransfer.profile(for: trajectory)

        // `answers` reste alimenté : ses genres cadrent la requête de vivier, qui part
        // avant que la moindre croyance n'existe côté serveur.
        answers.apply(profile)

        // On repart de ce qu'on savait déjà, élargi — puis le cadre et le cadran
        // viennent par-dessus. C'est ici, et nulle part ailleurs, que les « régimes »
        // se décident : plus le trait est établi, plus les σ sont bas dès le départ,
        // plus vite la valeur de décision s'effondre, moins il y a de questions.
        // Aucun compteur de films n'intervient dans ce raisonnement.
        belief = BeliefState(prior: taste)
        belief.observe(AnswerObservations.fromBudget(answers.runtime))
        belief.observe(AnswerObservations.fromAudience(answers.audience))
        belief.observe(AnswerObservations.fromMood(profile))

        reading = MoodStrategy.from(trajectory).reading
        Task { await beginSession() }
    }

    func goBackToFrame() {
        phase = .frame
    }

    func select<T: QuestionOption>(_ value: T, in keyPath: WritableKeyPath<QuestionnaireAnswers, T>) {
        answers[keyPath: keyPath] = value
    }

    func select<T: QuestionOption>(_ value: T, in keyPath: WritableKeyPath<QuestionnaireAnswers, T?>) {
        answers[keyPath: keyPath] = value
    }

    // MARK: - Le cœur adaptatif

    var canAdvanceAdaptive: Bool {
        switch currentDimension {
        case .mindset: answers.mindset != nil
        case .dealbreaker: answers.dealbreaker != nil
        case .horrorFlavor: answers.horrorFlavor != nil
        case .comedyFlavor: answers.comedyFlavor != nil
        case .dramaFlavor: answers.dramaFlavor != nil
        case .cognitiveMode: answers.cognitiveMode != nil
        case .storyOrigin: answers.storyOrigin != nil
        case .attachment: answers.attachment != nil
        case .creditsMoment: answers.creditsMoment != nil
        case .lastingTrace: answers.lastingTrace != nil
        case nil: false
        default: true
        }
    }

    /// Validée par un tap sur une puce — les affiches avancent d'elles-mêmes.
    func goNextAdaptive() {
        guard let dimension = currentDimension, canAdvanceAdaptive else { return }
        pushAdaptiveSnapshot()
        record(dimension, observations: AnswerObservations.from(dimension, answers: answers))
        reading = Self.reading(for: dimension, answers: answers)
        advance()
    }

    func recordPairwiseChoice(winner: CandidateRow, loser: CandidateRow) {
        pushAdaptiveSnapshot()
        record(.mood, observations: AnswerObservations.fromDuel(winner: winner, loser: loser))
        pairwiseOptions = nil
        reading = Self.reading(winner: winner, loser: loser)
        advance()
    }

    func recordElimination(loser: CandidateRow) {
        pushAdaptiveSnapshot()
        let others = (eliminationOptions ?? []).filter { $0.id != loser.id }
        record(.elimination, observations: AnswerObservations.fromElimination(loser: loser, others: others))
        eliminationOptions = nil
        reading = "Écarté. On s'éloigne de ce côté-là."
        advance()
    }

    private func record(_ dimension: AdaptiveDimension, observations: [AxisObservation]) {
        askedDimensions.insert(dimension)
        recentFormats.append(dimension.format)
        belief.observe(observations)
    }

    /// Toujours disponible : quand il n'y a plus d'instantané à dépiler, on remonte au
    /// cadran plutôt que de rendre le bouton inerte — le trajet d'humeur est la
    /// première chose qu'on veut pouvoir corriger.
    var canGoBackAdaptive: Bool { true }

    func goBackAdaptive() {
        guard let snapshot = adaptiveHistory.popLast() else {
            phase = .mood
            reading = nil
            return
        }
        currentDimension = snapshot.dimension
        pairwiseOptions = snapshot.pairwiseOptions
        eliminationOptions = snapshot.eliminationOptions
        answers = snapshot.answers
        belief = snapshot.belief
        pool = snapshot.pool
        enrichedPool = snapshot.enrichedPool
        hasEnriched = snapshot.hasEnriched
        askedDimensions = snapshot.askedDimensions
        recentFormats = snapshot.recentFormats
        reading = snapshot.reading
        phase = .asking
    }

    private func pushAdaptiveSnapshot() {
        adaptiveHistory.append(AdaptiveSnapshot(
            dimension: currentDimension,
            pairwiseOptions: pairwiseOptions,
            eliminationOptions: eliminationOptions,
            answers: answers,
            belief: belief,
            pool: pool,
            enrichedPool: enrichedPool,
            hasEnriched: hasEnriched,
            askedDimensions: askedDimensions,
            recentFormats: recentFormats,
            reading: reading
        ))
    }

    /// La porte de sortie manuelle, disponible à tout instant.
    func finishNow() {
        Task { await finish() }
    }

    func restart() {
        phase = .intro
        results = []
        belief = BeliefState()
        pool = []
        enrichedPool = []
        hasEnriched = false
        askedDimensions = []
        recentFormats = []
        adaptiveHistory = []
        currentDimension = nil
        pairwiseOptions = nil
        eliminationOptions = nil
        moodNow = nil
        moodGoal = nil
        reading = nil
    }

    func retrySubmit() {
        guard let lastFailedAction else { return }
        Task { await lastFailedAction() }
    }

    // MARK: - La boucle

    private func beginSession() async {
        phase = .poolLoading
        do {
            let response = try await recommendationClient.fetchCandidatePool(trunk: answers)
            guard !response.candidates.isEmpty else {
                phase = .error("Aucun film ne correspond à ces critères pour le moment.")
                return
            }
            pool = response.candidates
            advance()
        } catch {
            fail(error, retry: { [weak self] in await self?.beginSession() })
        }
    }

    /// Pose la question la plus décisive, ou conclut. C'est la seule boucle du moteur :
    /// il n'y a plus de phases de questions, seulement un critère et son seuil.
    private func advance() {
        let asked = askedDimensions.count
        let best = QuestionEngine.nextDimension(
            pool: pool,
            belief: belief,
            asked: askedDimensions,
            recentFormats: recentFormats,
            posterOptionsProvider: { [pool, belief] dimension in
                QuestionEngine.posterOutcomes(for: dimension, pool: pool, belief: belief)
            }
        )

        if QuestionEngine.shouldStop(
            bestValue: best?.value,
            questionsAsked: asked,
            establishedAxes: taste.establishedAxisCount
        ) {
            // Plus rien à demander sur les données grossières — mais l'enrichissement
            // apporte la durée, le budget et la franchise, donc de nouveaux écarts
            // entre les films, donc peut-être de nouvelles questions qui valent la
            // peine. On enrichit avant de conclure, jamais l'inverse.
            if !hasEnriched && asked < QuestionEngine.maximumQuestions {
                Task { await beginEnrichment() }
            } else {
                Task { await finish() }
            }
            return
        }

        guard let best else {
            Task { await finish() }
            return
        }
        present(best.dimension)
    }

    private func present(_ dimension: AdaptiveDimension) {
        switch dimension {
        case .mood:
            guard let options = QuestionEngine.pickDuel(from: pool, belief: belief) else {
                // Vivier trop homogène pour opposer deux affiches — on classe la
                // question plutôt que de boucler dessus.
                askedDimensions.insert(.mood)
                advance()
                return
            }
            pairwiseOptions = options
            eliminationOptions = nil
        case .elimination:
            guard let options = QuestionEngine.pickElimination(from: pool, belief: belief) else {
                askedDimensions.insert(.elimination)
                advance()
                return
            }
            eliminationOptions = options
            pairwiseOptions = nil
        default:
            pairwiseOptions = nil
            eliminationOptions = nil
        }
        currentDimension = dimension
        phase = .asking
    }

    private func beginEnrichment() async {
        phase = .enriching
        do {
            let toEnrich = QuestionEngine.candidatesForEnrichment(pool: pool, belief: belief)
            enrichedPool = try await recommendationClient.enrichCandidates(toEnrich)
            hasEnriched = true
            guard !enrichedPool.isEmpty else {
                Task { await finish() }
                return
            }
            // Le vivier de travail devient l'enrichi : mêmes films, axes resserrés.
            pool = enrichedPool.map(\.base)
            advance()
        } catch {
            fail(error, retry: { [weak self] in await self?.beginEnrichment() })
        }
    }

    private func finish() async {
        phase = .finalizing
        do {
            let finalCandidates: [EnrichedCandidateRow]
            if enrichedPool.isEmpty {
                let toEnrich = QuestionEngine.candidatesForEnrichment(pool: pool, belief: belief)
                finalCandidates = try await recommendationClient.enrichCandidates(toEnrich)
            } else {
                finalCandidates = enrichedPool
            }
            guard !finalCandidates.isEmpty else {
                phase = .error("Aucun film ne correspond à ces critères pour le moment.")
                return
            }
            results = try await recommendationClient.finalizeRecommendations(
                answers: answers, belief: belief, candidates: finalCandidates
            )
            phase = .results
        } catch {
            fail(error, retry: { [weak self] in await self?.finish() })
        }
    }

    private func fail(_ error: Error, retry: @escaping () async -> Void) {
        if error is CancellationError { return }
        lastFailedAction = retry
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        phase = .error(message)
    }

    // MARK: - Les lectures

    /// Ce que le système vient de comprendre, dit en une ligne. Rien n'est produit
    /// pour les dimensions dont la réponse ne se résume pas honnêtement — une
    /// lecture creuse coûte plus cher que pas de lecture du tout.
    private static func reading(for dimension: AdaptiveDimension, answers: QuestionnaireAnswers) -> String? {
        switch dimension {
        case .dealbreaker:
            switch answers.dealbreaker {
            case .slowPace: "Noté : rien qui traîne."
            case .heavyMood: "Noté : on garde ça respirable."
            case .tooLong: "Noté : on surveille la durée."
            case .predictablePlot: "Noté : il faudra que ça surprenne."
            case nil: nil
            }
        case .popularity:
            switch answers.popularity {
            case .hiddenGem: "On va chercher plus loin que les têtes d'affiche."
            case .mainstream: "On reste sur des valeurs sûres."
            default: nil
            }
        case .cognitiveMode:
            answers.cognitiveMode == .understand
                ? "Vous voulez comprendre — on privilégie ce qui se déchiffre."
                : "Vous voulez ressentir avant de comprendre."
        default:
            nil
        }
    }

    /// Comparaison honnête : on ne commente que si l'écart de notoriété entre les deux
    /// affiches est net, sinon le duel a tranché autre chose qu'on ne sait pas nommer.
    private static func reading(winner: CandidateRow, loser: CandidateRow) -> String? {
        let gap = winner.axes[.familiarite] - loser.axes[.familiarite]
        guard abs(gap) > 0.4 else { return nil }
        return gap < 0
            ? "Le terrain connu vous va, ce soir."
            : "Vous préférez ce qu'on vous a moins vendu."
    }
}
