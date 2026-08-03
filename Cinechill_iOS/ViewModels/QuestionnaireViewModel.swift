//
//  QuestionnaireViewModel.swift
//  Cinechill_iOS
//

import Foundation

/// Le socle (T1-T4, voir la spec "moteur de préférence actif") — toujours posé, dans cet ordre,
/// jamais assoupli. Au-delà, les questions viennent de `AdaptiveDimension`, choisies dynamiquement
/// par `QuestionEngine` plutôt que dans un ordre fixe.
enum QuestionStep: Int, CaseIterable, Hashable {
    case contentFormat, genres, platforms, audience, mood, origin, mindset, dealbreaker, popularity, cast, runtime, era
    case horrorFlavor, comedyFlavor, dramaFlavor, cognitiveMode, elimination, surpriseIntensity

    var title: String {
        switch self {
        case .contentFormat: "Dessin animé ou film ?"
        case .genres: "Genres qui vous attirent"
        case .platforms: "Sur quelles plateformes pouvez-vous regarder ?"
        case .audience: "Avec qui regardez-vous ?"
        case .mood: "Quelle ambiance ce soir ?"
        case .origin: "Cinéma français ou plutôt international ?"
        case .mindset: "Là, tout de suite, vous avez plutôt envie de…"
        case .dealbreaker: "Qu'est-ce qui vous ferait le plus décrocher d'un film ?"
        case .popularity: "Blockbuster ou pépite méconnue ?"
        case .cast: "Un casting que vous reconnaissez, ou l'envie de découvrir de nouvelles têtes ?"
        case .runtime: "Combien de temps devant vous ?"
        case .era: "Récent ou vintage ?"
        case .horrorFlavor: "Dans l'horreur, vous cherchez plutôt…"
        case .comedyFlavor: "Le genre de comédie que vous aimez ?"
        case .dramaFlavor: "Le drame qui vous touche le plus ?"
        case .cognitiveMode: "Face à l'inconnu, vous préférez…"
        case .elimination: "Une chose est sûre : pas envie de ça ce soir"
        case .surpriseIntensity: "À quel point voulez-vous être surpris·e ?"
        }
    }

    var subtitle: String? {
        switch self {
        case .genres: "Jusqu'à \(QuestionnaireAnswers.maxGenres) genres"
        case .platforms: "On ne vous proposera que ce que vous pouvez regarder tout de suite"
        case .cognitiveMode: "Pas de bonne réponse — ça nous aide à cerner votre approche"
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
        case trunk
        case poolLoading
        case tier1
        case enriching
        case tier2
        case finalizing
        case results
        case error(String)
    }

    private let recommendationClient: any RecommendationFetching
    private let metadataClient: any HomeMetadataFetching
    private let trunkSteps: [QuestionStep] = [.contentFormat, .genres, .platforms, .audience]

    private(set) var phase: Phase = .intro
    private(set) var trunkIndex = 0
    private(set) var availablePlatforms: [StreamingPlatform] = []
    private(set) var results: [RecommendationResult] = []
    private(set) var currentDimension: AdaptiveDimension?
    private(set) var pairwiseOptions: (CandidateRow, CandidateRow)?
    private(set) var eliminationOptions: [CandidateRow]?
    var answers = QuestionnaireAnswers()

    private var coarsePool: [CandidateRow] = []
    private var enrichedPool: [EnrichedCandidateRow] = []
    private var askedDimensions: Set<AdaptiveDimension> = []
    private var lastFailedAction: (() async -> Void)?

    /// Un instantané complet de l'état, capturé juste avant que chaque question adaptative ne soit
    /// répondue — revenir en arrière restaure l'instantané tel quel plutôt que d'essayer d'annuler
    /// chaque mutation individuellement (pool local, réponses, dimensions déjà posées…).
    private struct AdaptiveSnapshot {
        let phase: Phase
        let dimension: AdaptiveDimension?
        let pairwiseOptions: (CandidateRow, CandidateRow)?
        let eliminationOptions: [CandidateRow]?
        let answers: QuestionnaireAnswers
        let coarsePool: [CandidateRow]
        let enrichedPool: [EnrichedCandidateRow]
        let askedDimensions: Set<AdaptiveDimension>
    }
    private var adaptiveHistory: [AdaptiveSnapshot] = []

    init(recommendationClient: any RecommendationFetching, metadataClient: any HomeMetadataFetching) {
        self.recommendationClient = recommendationClient
        self.metadataClient = metadataClient
    }

    // MARK: - Progression affichée

    /// Nombre de questions déjà répondues (socle + adaptatif) — affiché comme un compteur ouvert
    /// plutôt qu'une fraction, puisque le total n'est plus connu à l'avance.
    var questionsAskedCount: Int { trunkIndex + askedDimensions.count }

    // MARK: - Socle (T1-T4)

    var currentTrunkStep: QuestionStep { trunkSteps[trunkIndex] }
    var isFirstTrunkStep: Bool { trunkIndex == 0 }

    var canAdvanceTrunk: Bool {
        switch currentTrunkStep {
        case .contentFormat: answers.contentFormat != nil
        case .genres: !answers.genres.isEmpty
        case .platforms: !answers.platformIDs.isEmpty
        case .audience: answers.audience != nil
        default: true
        }
    }

    func start(preferredPlatformIDs: Set<String>) {
        answers = QuestionnaireAnswers()
        answers.platformIDs = preferredPlatformIDs
        coarsePool = []
        enrichedPool = []
        askedDimensions = []
        adaptiveHistory = []
        currentDimension = nil
        pairwiseOptions = nil
        eliminationOptions = nil
        results = []
        trunkIndex = 0
        phase = .trunk
        Task { await loadPlatformsIfNeeded() }
    }

    func loadPlatformsIfNeeded() async {
        guard availablePlatforms.isEmpty else { return }
        guard let providers = try? await metadataClient.movieProviders() else { return }
        availablePlatforms = StreamingPlatform.curated(from: providers)
    }

    func goBackTrunk() {
        guard trunkIndex > 0 else { return }
        trunkIndex -= 1
    }

    func goNextTrunk() {
        guard canAdvanceTrunk else { return }
        guard trunkIndex < trunkSteps.count - 1 else {
            Task { await beginAdaptivePhase() }
            return
        }
        trunkIndex += 1
    }

    func toggleGenre(_ genre: Genre) {
        if answers.genres.contains(genre) {
            answers.genres.remove(genre)
        } else if answers.genres.count < QuestionnaireAnswers.maxGenres {
            answers.genres.insert(genre)
        }
    }

    func togglePlatform(_ id: String) {
        if answers.platformIDs.contains(id) {
            answers.platformIDs.remove(id)
        } else {
            answers.platformIDs.insert(id)
        }
    }

    func select<T: QuestionOption>(_ value: T, in keyPath: WritableKeyPath<QuestionnaireAnswers, T>) {
        answers[keyPath: keyPath] = value
    }

    func select<T: QuestionOption>(_ value: T, in keyPath: WritableKeyPath<QuestionnaireAnswers, T?>) {
        answers[keyPath: keyPath] = value
    }

    // MARK: - Phase adaptative (tier 1 / tier 2)

    var canAdvanceAdaptive: Bool {
        switch currentDimension {
        case .mindset: answers.mindset != nil
        case .dealbreaker: answers.dealbreaker != nil
        case .horrorFlavor: answers.horrorFlavor != nil
        case .comedyFlavor: answers.comedyFlavor != nil
        case .dramaFlavor: answers.dramaFlavor != nil
        case .cognitiveMode: answers.cognitiveMode != nil
        case nil: false
        default: true
        }
    }

    /// Validée par un tap sur une chip classique — la comparaison directe (mood) avance d'elle-même
    /// via `recordPairwiseChoice`, sans passer par ce bouton.
    func goNextAdaptive() {
        guard let dimension = currentDimension, canAdvanceAdaptive else { return }
        pushAdaptiveSnapshot()
        askedDimensions.insert(dimension)
        if dimension == .dealbreaker, let choice = answers.dealbreaker {
            coarsePool = QuestionEngine.applyDealbreakerFilter(to: coarsePool, dealbreaker: choice)
        }
        QuestionEngine.applyFlavorChoice(dimension: dimension, answers: &answers)
        if phase == .tier1 {
            advanceTier1()
        } else if phase == .tier2 {
            advanceTier2()
        }
    }

    func recordPairwiseChoice(winner: CandidateRow, loser: CandidateRow) {
        pushAdaptiveSnapshot()
        answers.preferredGenreIDs.formUnion(winner.genreIds)
        answers.avoidedGenreIDs.formUnion(loser.genreIds)
        askedDimensions.insert(.mood)
        pairwiseOptions = nil
        advanceTier1()
    }

    /// Signal plus large qu'un duel — voir `QuestionEngine.pickEliminationOptions` — donc on écarte
    /// seulement les genres du film rejeté, sans booster les trois autres (aucun n'a été choisi).
    func recordElimination(loser: CandidateRow) {
        pushAdaptiveSnapshot()
        answers.avoidedGenreIDs.formUnion(loser.genreIds)
        askedDimensions.insert(.elimination)
        eliminationOptions = nil
        advanceTier1()
    }

    /// Disponible dès qu'au moins une question adaptative a été répondue — sinon "restart" (le
    /// bouton "x") reste le seul retour possible, même comportement que dans le socle.
    var canGoBackAdaptive: Bool { !adaptiveHistory.isEmpty }

    func goBackAdaptive() {
        guard let snapshot = adaptiveHistory.popLast() else { return }
        phase = snapshot.phase
        currentDimension = snapshot.dimension
        pairwiseOptions = snapshot.pairwiseOptions
        eliminationOptions = snapshot.eliminationOptions
        answers = snapshot.answers
        coarsePool = snapshot.coarsePool
        enrichedPool = snapshot.enrichedPool
        askedDimensions = snapshot.askedDimensions
    }

    private func pushAdaptiveSnapshot() {
        adaptiveHistory.append(AdaptiveSnapshot(
            phase: phase,
            dimension: currentDimension,
            pairwiseOptions: pairwiseOptions,
            eliminationOptions: eliminationOptions,
            answers: answers,
            coarsePool: coarsePool,
            enrichedPool: enrichedPool,
            askedDimensions: askedDimensions
        ))
    }

    /// La porte de sortie manuelle, disponible à tout instant une fois le socle passé — voir la
    /// spec, section "condition d'arrêt par confiance".
    func finishNow() {
        Task { await finish() }
    }

    func restart() {
        phase = .intro
        trunkIndex = 0
        results = []
        coarsePool = []
        enrichedPool = []
        askedDimensions = []
        adaptiveHistory = []
        currentDimension = nil
        pairwiseOptions = nil
        eliminationOptions = nil
    }

    func retrySubmit() {
        guard let lastFailedAction else { return }
        Task { await lastFailedAction() }
    }

    // MARK: - Phase A → B → C → D

    private func beginAdaptivePhase() async {
        phase = .poolLoading
        do {
            let response = try await recommendationClient.fetchCandidatePool(trunk: answers)
            guard !response.candidates.isEmpty else {
                phase = .error("Aucun film ne correspond à ces critères pour le moment.")
                return
            }
            coarsePool = response.candidates
            advanceTier1()
        } catch {
            fail(error, retry: { [weak self] in await self?.beginAdaptivePhase() })
        }
    }

    /// Vérifie la confiance, sinon pose la question au gain d'information le plus élevé parmi les
    /// dimensions tier 1 restantes ; bascule en phase d'enrichissement quand il n'y en a plus.
    private func advanceTier1() {
        let gap = QuestionEngine.confidenceGap(pool: coarsePool, answers: answers)
        if QuestionEngine.isConfident(gap: gap, questionsAsked: questionsAskedCount) {
            Task { await finish() }
            return
        }
        guard let dimension = QuestionEngine.nextTier1Dimension(
            pool: coarsePool, answers: answers, asked: askedDimensions
        ) else {
            Task { await beginEnrichment() }
            return
        }

        if dimension == .mood {
            if let options = QuestionEngine.pickPairwiseOptions(from: coarsePool, answers: answers) {
                currentDimension = .mood
                pairwiseOptions = options
                phase = .tier1
                return
            }
            // Pool trop homogène pour comparer deux affiches distinctes — on saute la question
            // plutôt que de boucler dessus indéfiniment.
            askedDimensions.insert(.mood)
            advanceTier1()
            return
        }

        if dimension == .elimination {
            if let options = QuestionEngine.pickEliminationOptions(from: coarsePool, answers: answers) {
                currentDimension = .elimination
                eliminationOptions = options
                phase = .tier1
                return
            }
            askedDimensions.insert(.elimination)
            advanceTier1()
            return
        }

        currentDimension = dimension
        pairwiseOptions = nil
        eliminationOptions = nil
        phase = .tier1
    }

    private func beginEnrichment() async {
        phase = .enriching
        do {
            let toEnrich = QuestionEngine.candidatesForEnrichment(pool: coarsePool, answers: answers)
            enrichedPool = try await recommendationClient.enrichCandidates(toEnrich)
            guard !enrichedPool.isEmpty else {
                Task { await finish() }
                return
            }
            advanceTier2()
        } catch {
            fail(error, retry: { [weak self] in await self?.beginEnrichment() })
        }
    }

    private func advanceTier2() {
        let gap = QuestionEngine.confidenceGap(pool: enrichedPool, answers: answers)
        if QuestionEngine.isConfident(gap: gap, questionsAsked: questionsAskedCount) {
            Task { await finish() }
            return
        }
        guard let dimension = QuestionEngine.nextTier2Dimension(pool: enrichedPool, asked: askedDimensions) else {
            Task { await finish() }
            return
        }
        currentDimension = dimension
        pairwiseOptions = nil
        eliminationOptions = nil
        phase = .tier2
    }

    private func finish() async {
        phase = .finalizing
        do {
            let finalCandidates: [EnrichedCandidateRow]
            if enrichedPool.isEmpty {
                // Jamais passé en phase B (confiance atteinte dès le tier 1) — on enrichit
                // maintenant les meilleurs candidats pour pouvoir calculer le score final.
                let toEnrich = QuestionEngine.candidatesForEnrichment(pool: coarsePool, answers: answers)
                finalCandidates = try await recommendationClient.enrichCandidates(toEnrich)
            } else {
                finalCandidates = enrichedPool
            }
            guard !finalCandidates.isEmpty else {
                phase = .error("Aucun film ne correspond à ces critères pour le moment.")
                return
            }
            results = try await recommendationClient.finalizeRecommendations(
                answers: answers, candidates: finalCandidates
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
}
