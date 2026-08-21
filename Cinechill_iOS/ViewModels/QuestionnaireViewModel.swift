//
//  QuestionnaireViewModel.swift
//  Cinechill_iOS
//

import Foundation

/// Les questions adaptatives — celles que `QuestionEngine` choisit une par une.
///
/// Le socle n'y figure pas : avec qui, combien de temps et sous quelle forme tiennent
/// sur un écran (`SessionFrameView`), le genre et l'ambiance sur le suivant
/// (`FilmChoiceView`), et les plateformes viennent des réglages.
enum QuestionStep: Int, CaseIterable, Hashable {
    case posterDuel, mindset, dealbreaker, popularity, cast
    case horrorFlavor, comedyFlavor, dramaFlavor, cognitiveMode
    case storyOrigin, attachment, creditsMoment, lastingTrace
    case elimination, surpriseIntensity

    var title: String {
        switch self {
        case .posterDuel: String(localized: "Lequel te tente le plus ce soir ?", bundle: .app)
        case .mindset: String(localized: "Ce soir, tu as surtout envie de…", bundle: .app)
        case .dealbreaker: String(localized: "Qu'est-ce qui te ferait arrêter un film en cours de route ?", bundle: .app)
        case .popularity: String(localized: "Tu préfères un film connu ou une découverte ?", bundle: .app)
        case .cast: String(localized: "Et côté acteurs ?", bundle: .app)
        case .horrorFlavor: String(localized: "Dans un film qui fait peur, tu préfères…", bundle: .app)
        case .comedyFlavor: String(localized: "Quel genre de comédie te fait rire ?", bundle: .app)
        case .dramaFlavor: String(localized: "Quelle histoire te touche le plus ?", bundle: .app)
        case .cognitiveMode: String(localized: "Un bon film, pour toi, c'est plutôt…", bundle: .app)
        case .storyOrigin: String(localized: "S'il fallait choisir entre ces deux films…", bundle: .app)
        case .attachment: String(localized: "Qu'est-ce qui t'accroche le plus dans un film ?", bundle: .app)
        case .creditsMoment: String(localized: "Le film se termine. Dans le meilleur des cas, tu…", bundle: .app)
        case .lastingTrace: String(localized: "Pense au dernier film qui t'a marqué·e. Il t'a laissé…", bundle: .app)
        case .elimination: String(localized: "Lequel ne te tente pas du tout ce soir ?", bundle: .app)
        case .surpriseIntensity: String(localized: "Tu veux être surpris·e jusqu'à quel point ?", bundle: .app)
        }
    }

    /// Le sous-titre dit **pourquoi** on pose la question. C'était la lacune
    /// principale du questionnaire : sans lui, chaque question ressemblait à un
    /// test de personnalité dont on ne voyait pas le rapport avec un film.
    var subtitle: String? {
        switch self {
        case .posterDuel: String(localized: "Ton choix nous en dit plus que n'importe quelle question.", bundle: .app)
        case .mindset: String(localized: "Pour viser le bon type de film, pas seulement le bon genre.", bundle: .app)
        case .dealbreaker: String(localized: "On évitera les films qui risquent de te faire ça.", bundle: .app)
        case .popularity: String(localized: "Pour savoir jusqu'où aller chercher.", bundle: .app)
        case .cast: nil
        case .horrorFlavor: String(localized: "Il y a plusieurs façons de faire peur.", bundle: .app)
        case .comedyFlavor: nil
        case .dramaFlavor: nil
        case .cognitiveMode: String(localized: "Pas de bonne réponse : les deux existent, on veut juste savoir laquelle te ressemble.", bundle: .app)
        case .storyOrigin: String(localized: "Il faut trancher, même si les deux te vont.", bundle: .app)
        case .attachment: nil
        case .creditsMoment: String(localized: "Ce que tu espères ressentir après nous aide à choisir avant.", bundle: .app)
        case .lastingTrace: String(localized: "On se connaît mieux au passé qu'au futur.", bundle: .app)
        case .elimination: String(localized: "Écarter un film nous apprend autant qu'en choisir un.", bundle: .app)
        case .surpriseIntensity: nil
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
        /// Le film cherché : genre et ambiance. Deux listes d'options.
        case filmChoice
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

    private(set) var phase: Phase = .intro
    private(set) var availablePlatforms: [StreamingPlatform] = []
    private(set) var results: [RecommendationResult] = []
    private(set) var currentDimension: AdaptiveDimension?
    private(set) var pairwiseOptions: (CandidateRow, CandidateRow)?
    private(set) var eliminationOptions: [CandidateRow]?
    /// La question par affiches en cours oppose des films **vus** : le titre
    /// change (« Tu as vu les deux… ») et la réponse s'écrit dans le graphe.
    private(set) var duelSourceIsGallery = false
    var answers = QuestionnaireAnswers()

    /// Les films de la Galerie, positionnés par le serveur (C1) : la matière
    /// des duels entre films vus (C2). Chargés au début de séance, jamais
    /// requis — sans eux, les duels retombent sur le vivier, comme avant.
    private(set) var galleryRows: [CandidateRow] = []
    private var galleryIDs: Set<Int> = []

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

    /// Les films explicitement écartés. Ils quittent le vivier pour de bon :
    /// reproposer dans la question suivante un film qu'on vient de refuser est la
    /// contradiction la plus visible que le parcours puisse produire.
    private var excludedIDs: Set<Int> = []

    /// Les films déjà montrés en affiche. On ne les remontre pas dans une autre
    /// question par affiches — revoir la même affiche donne l'impression que la
    /// réponse précédente n'a pas été prise en compte, même quand elle l'a été.
    private var shownPosterIDs: Set<Int> = []

    /// Le vivier dans lequel on pioche les affiches à montrer. Distinct du vivier
    /// de classement : un film déjà montré reste un candidat parfaitement valable
    /// pour le trio final, il n'a simplement plus rien à nous apprendre.
    private var posterPool: [CandidateRow] {
        pool.filter { !shownPosterIDs.contains($0.id) }
    }

    /// La matière des questions par affiches (C2) : les films **vus**, dès
    /// qu'il en reste assez à montrer. Entre deux affiches inconnues, on
    /// choisit la plus jolie ; entre deux souvenirs, on choisit son goût.
    /// Le vivier reste le repli — un duel de découverte plutôt qu'aucun duel.
    private static let galleryDuelFloor = 6
    private var duelPool: [CandidateRow] {
        let seen = galleryRows.filter { !shownPosterIDs.contains($0.id) }
        return seen.count >= Self.galleryDuelFloor ? seen : posterPool
    }

    /// Le duel courant se joue-t-il entre films vus ?
    private var duelPoolIsGallery: Bool {
        galleryRows.filter { !shownPosterIDs.contains($0.id) }.count >=
            Self.galleryDuelFloor
    }

    /// Un instantané complet de l'état, capturé juste avant que chaque question adaptative ne soit
    /// répondue — revenir en arrière restaure l'instantané tel quel plutôt que d'essayer d'annuler
    /// chaque mutation individuellement (croyance, vivier, dimensions déjà posées…).
    private struct AdaptiveSnapshot {
        let dimension: AdaptiveDimension?
        let pairwiseOptions: (CandidateRow, CandidateRow)?
        let eliminationOptions: [CandidateRow]?
        let duelSourceIsGallery: Bool
        let answers: QuestionnaireAnswers
        let belief: BeliefState
        let pool: [CandidateRow]
        let enrichedPool: [EnrichedCandidateRow]
        let hasEnriched: Bool
        let askedDimensions: Set<AdaptiveDimension>
        let recentFormats: [QuestionFormat]
        let reading: String?
        let excludedIDs: Set<Int>
        let shownPosterIDs: Set<Int>
    }
    private var adaptiveHistory: [AdaptiveSnapshot] = []

    init(recommendationClient: any RecommendationFetching, metadataClient: any HomeMetadataFetching) {
        self.recommendationClient = recommendationClient
        self.metadataClient = metadataClient
    }

    // MARK: - Progression affichée

    /// Le numéro affiché en haut d'une question. On ne compte que les questions
    /// réellement posées : afficher « Question 3 » sur la première question
    /// visible — parce que le cadre et l'humeur comptaient dans le total —
    /// donnait l'impression d'avoir raté deux écrans.
    var questionNumber: Int { askedDimensions.count + 1 }

    // MARK: - Le cadre

    var canAdvanceFrame: Bool {
        answers.audience != nil && answers.contentFormat != nil
    }

    /// - Parameters:
    ///   - preferredPlatformIDs: plateformes déclarées dans les réglages. Elles ne sont
    ///     plus demandés — seulement rappelés au seuil, et modifiables là où ils
    ///     vivent vraiment.
    ///   - bannedGenreIDs: genres exclus dans les réglages. Attention, le backend
    ///     n'en fait qu'un malus de score, pas un filtre dur : c'est
    ///     `availableGenres` qui garantit qu'un genre banni ne sera jamais demandé
    ///     à TMDB, en ne le proposant pas.
    ///   - audience: la réponse déjà donnée sur l'écran d'entrée. Elle est
    ///     reposée **après** la remise à zéro : `answers` est reconstruit ici, et
    ///     l'écrire avant reviendrait à l'effacer.
    func start(preferredPlatformIDs: Set<String>, bannedGenreIDs: Set<Int> = [], audience: Audience? = nil) {
        answers = QuestionnaireAnswers()
        answers.platformIDs = preferredPlatformIDs
        answers.avoidedGenreIDs = bannedGenreIDs
        answers.audience = audience
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
        excludedIDs = []
        shownPosterIDs = []
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
        // La porte n'est pas relue ici : `DoorStore` en est le seul
        // propriétaire, et c'est lui qui décide de ce qui se fête.
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

    /// « Ce n'est pas lui » — le refus du verdict, à la granularité du film.
    ///
    /// Le client ne recompose rien : le classement complet est déjà là, il ne
    /// fait que révéler le suivant. Le refus, lui, part au serveur (le trait
    /// s'en souviendra, par film et daté) et infléchit la croyance locale —
    /// utile si la séance repart sur « Aucun ne me tente ».
    func passFilm(tmdbID: Int) {
        Task { try? await recommendationClient.recordPass(tmdbID: tmdbID) }
        if let row = pool.first(where: { $0.id == tmdbID }) {
            belief.observe(AnswerObservations.fromRejectedTrio([row]))
        }
    }

    /// « Aucun des trois ne me tente » — le geste qui manquait à la boucle.
    ///
    /// Trois effets : le refus est écrit dans l'historique (le trait s'en
    /// souviendra), la croyance s'éloigne de la position moyenne du trio, et un
    /// second trio est composé dans ce qui reste du vivier — délibérément
    /// ailleurs, puisque la croyance vient de bouger. Sans ce geste, le cas
    /// d'échec le plus fréquent ne laissait aucune trace.
    func rejectTrio() {
        guard phase == .results, !results.isEmpty else { return }
        let rejectedIDs = Set(results.map(\.item.tmdbId))
        Task {
            try? await recommendationClient.recordRejection(tmdbIDs: Array(rejectedIDs))
        }

        let rejectedRows = pool.filter { rejectedIDs.contains($0.id) }
        belief.observe(AnswerObservations.fromRejectedTrio(rejectedRows))

        pool.removeAll { rejectedIDs.contains($0.id) }
        enrichedPool.removeAll { rejectedIDs.contains($0.id) }
        guard !enrichedPool.isEmpty else {
            phase = .error(String(localized: "On n'a plus d'autres films à te proposer avec ces critères. Recommence une recherche pour élargir.", bundle: .app))
            return
        }
        results = []
        Task { await finish() }
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
        let formatted = String(format: "%d h %02d", hour, minute)
        lateHourNote = String(localized: "Il est \(formatted) : on a présélectionné un format court pour que tu puisses le finir ce soir.", bundle: .app)
    }

    func loadPlatformsIfNeeded() async {
        guard availablePlatforms.isEmpty else { return }
        guard let providers = try? await metadataClient.movieProviders() else { return }
        availablePlatforms = StreamingPlatform.curated(from: providers)
    }

    func goNextFrame() {
        guard canAdvanceFrame else { return }
        // Revenir en arrière pour changer de public peut rendre un genre déjà
        // coché indisponible. On le retire plutôt que de partir chercher un
        // genre qu'on ne propose plus.
        let allowed = Set(availableGenres)
        answers.genres.formIntersection(allowed)
        phase = .filmChoice
    }

    // MARK: - Le film cherché

    /// Les genres proposés.
    ///
    /// Trois retraits. Les genres bannis dans les réglages, d'abord : les proposer
    /// reviendrait à demander de reconfirmer un refus déjà exprimé, et le backend
    /// n'en fait qu'un malus de score — c'est donc ici, et nulle part ailleurs,
    /// qu'un genre banni cesse d'être demandé à TMDB. L'animation ensuite, déjà
    /// tranchée à l'écran précédent : la proposer une seconde fois créerait deux
    /// réponses qui peuvent se contredire. L'horreur enfin, quand on regarde avec
    /// des enfants : le serveur l'exclut de toute façon dans ce cas, et la
    /// proposer quand même mènerait à une recherche sans résultat que personne ne
    /// saurait s'expliquer.
    var availableGenres: [Genre] {
        Genre.allCases.filter { genre in
            guard genre != .animation else { return false }
            guard genre != .horror || answers.audience != .family else { return false }
            return genre.tmdbIDs.isDisjoint(with: answers.avoidedGenreIDs)
        }
    }

    var maxGenres: Int { QuestionnaireAnswers.maxGenres }

    /// Au-delà de deux genres, le OU de TMDB élargit le vivier au lieu de le
    /// cadrer — c'est l'inverse de l'effet recherché. La limite est donc tenue
    /// ici plutôt qu'expliquée à l'utilisateur.
    func toggleGenre(_ genre: Genre) {
        if answers.genres.contains(genre) {
            answers.genres.remove(genre)
        } else if answers.genres.count < QuestionnaireAnswers.maxGenres {
            answers.genres.insert(genre)
        }
    }

    func isGenreSelectable(_ genre: Genre) -> Bool {
        answers.genres.contains(genre) || answers.genres.count < QuestionnaireAnswers.maxGenres
    }

    var maxOriginCountries: Int { QuestionnaireAnswers.maxOriginCountries }

    func toggleOriginCountry(_ origin: OriginCountry) {
        if answers.originCountries.contains(origin) {
            answers.originCountries.remove(origin)
        } else if answers.originCountries.count < QuestionnaireAnswers.maxOriginCountries {
            answers.originCountries.insert(origin)
        }
    }

    func isOriginCountrySelectable(_ origin: OriginCountry) -> Bool {
        answers.originCountries.contains(origin)
            || answers.originCountries.count < QuestionnaireAnswers.maxOriginCountries
    }

    /// L'ambiance demande une réponse — mais « peu importe » en est une (C3) :
    /// le prior du trait fait alors le travail seul, ce que le moteur bayésien
    /// sait déjà faire. Le genre reste facultatif : quelqu'un d'ouvert à tout
    /// ne doit pas être forcé de restreindre sa recherche pour avancer.
    var canConfirmFilmChoice: Bool { answers.mood != nil || answers.moodDecided }

    /// L'ambiance choisie. Passer par ici et non par le binding : c'est ce qui
    /// permet de distinguer « pas encore répondu » de « peu importe ».
    func pickMood(_ mood: Mood) {
        answers.mood = mood
        answers.moodDecided = true
    }

    /// « Peu importe » sur l'ambiance : une réponse qu'on choisit, pas
    /// seulement un champ qu'on laisse vide.
    func pickMoodAny() {
        answers.mood = nil
        answers.moodDecided = true
    }

    var isMoodAny: Bool { answers.mood == nil && answers.moodDecided }

    /// La lecture, dès que l'ambiance est choisie et avant même de valider — pour
    /// que le choix ait une réponse immédiate.
    var ambianceReading: String? {
        if let mood = answers.mood { return mood.reading }
        guard answers.moodDecided else { return nil }
        return String(localized: "On partira de ce que ta galerie raconte, sans contrainte d'ambiance.", bundle: .app)
    }

    /// Ouvre la croyance avec ce que les deux écrans ont appris, puis lance la
    /// recherche. C'est ici, et seulement ici, que l'ambiance entre dans le
    /// modèle : ensuite ce sont les questions et les affiches qui la corrigent.
    func confirmFilmChoice() {
        guard canConfirmFilmChoice else { return }

        // On repart de ce qu'on savait déjà, élargi — puis le cadre et l'ambiance
        // viennent par-dessus. C'est ici, et nulle part ailleurs, que les « régimes »
        // se décident : plus le trait est établi, plus les σ sont bas dès le départ,
        // plus vite la valeur de décision s'effondre, moins il y a de questions.
        // Aucun compteur de films n'intervient dans ce raisonnement.
        belief = BeliefState(prior: taste)
        belief.observe(AnswerObservations.fromBudget(answers.runtime))
        belief.observe(AnswerObservations.fromAudience(answers.audience))
        if let mood = answers.mood {
            belief.observe(AnswerObservations.fromAmbiance(mood))
        }

        reading = answers.mood?.reading
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
        record(.posterDuel, observations: AnswerObservations.fromDuel(winner: winner, loser: loser))
        // Les deux affiches ont été vues : elles n'apprendront plus rien. Le
        // perdant reste dans le vivier — lui préférer un autre film n'est pas
        // le refuser, et il peut très bien finir dans le trio.
        shownPosterIDs.formUnion([winner.id, loser.id])

        // Un duel entre deux films vus fait double emploi : l'observation du
        // soir ci-dessus, et une écriture durable dans le graphe de
        // préférence (C2). Perdre n'est pas un rejet — c'est la répétition,
        // duel après duel, qui fera signal.
        if galleryIDs.contains(winner.id), galleryIDs.contains(loser.id) {
            Task {
                try? await recommendationClient.recordFilmDuel(
                    winnerID: winner.id, loserID: loser.id
                )
            }
        }

        pairwiseOptions = nil
        reading = Self.reading(winner: winner, loser: loser)
        advance()
    }

    func recordElimination(loser: CandidateRow) {
        pushAdaptiveSnapshot()
        let shown = eliminationOptions ?? []
        let others = shown.filter { $0.id != loser.id }
        record(.elimination, observations: AnswerObservations.fromElimination(loser: loser, others: others))

        // L'élimination n'écrit rien dans le graphe de préférence, même entre
        // films vus, et c'est un choix : écarter « pour ce soir » n'est pas
        // perdre un duel de goût, et un geste ne doit produire qu'une
        // écriture durable au plus. Le duel, lui, pose la question du goût.
        //
        // Le film écarté sort du vivier, définitivement. Le laisser dedans le
        // rendait reproposable dans la question suivante, et jusque dans le trio
        // final — on demandait à quelqu'un d'écarter un film pour le lui remontrer
        // aussitôt.
        excludedIDs.insert(loser.id)
        pool.removeAll { $0.id == loser.id }
        enrichedPool.removeAll { $0.id == loser.id }
        shownPosterIDs.formUnion(shown.map(\.id))

        eliminationOptions = nil
        reading = String(localized: "Noté : on s'éloignera de ce genre de film.", bundle: .app)
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
            phase = .filmChoice
            reading = nil
            return
        }
        currentDimension = snapshot.dimension
        pairwiseOptions = snapshot.pairwiseOptions
        eliminationOptions = snapshot.eliminationOptions
        duelSourceIsGallery = snapshot.duelSourceIsGallery
        answers = snapshot.answers
        belief = snapshot.belief
        pool = snapshot.pool
        enrichedPool = snapshot.enrichedPool
        hasEnriched = snapshot.hasEnriched
        askedDimensions = snapshot.askedDimensions
        recentFormats = snapshot.recentFormats
        reading = snapshot.reading
        excludedIDs = snapshot.excludedIDs
        shownPosterIDs = snapshot.shownPosterIDs
        phase = .asking
    }

    private func pushAdaptiveSnapshot() {
        adaptiveHistory.append(AdaptiveSnapshot(
            dimension: currentDimension,
            pairwiseOptions: pairwiseOptions,
            eliminationOptions: eliminationOptions,
            duelSourceIsGallery: duelSourceIsGallery,
            answers: answers,
            belief: belief,
            pool: pool,
            enrichedPool: enrichedPool,
            hasEnriched: hasEnriched,
            askedDimensions: askedDimensions,
            recentFormats: recentFormats,
            reading: reading,
            excludedIDs: excludedIDs,
            shownPosterIDs: shownPosterIDs
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
        duelSourceIsGallery = false
        excludedIDs = []
        shownPosterIDs = []
        reading = nil
        // `galleryRows` reste : la Galerie ne change pas d'une séance à
        // l'autre, et la recharger ferait attendre pour rien.
    }

    func retrySubmit() {
        guard let lastFailedAction else { return }
        Task { await lastFailedAction() }
    }

    // MARK: - La boucle

    private func beginSession() async {
        phase = .poolLoading
        do {
            // Les positions de la Galerie se chargent en même temps que le
            // vivier, et ne le retardent jamais : sans elles, les duels
            // retombent sur le vivier, comme avant.
            let galleryTask = Task { [recommendationClient] in
                try? await recommendationClient.fetchGalleryAxes()
            }
            // Toute sortie anticipée — vivier vide, erreur réseau — libère la
            // tâche ; l'annuler après coup est sans effet.
            defer { galleryTask.cancel() }
            let response = try await recommendationClient.fetchCandidatePool(trunk: answers)
            guard !response.candidates.isEmpty else {
                phase = .error(String(localized: "Aucun film ne correspond à ces critères pour le moment.", bundle: .app))
                return
            }
            pool = response.candidates
            if let rows = await galleryTask.value {
                galleryRows = rows
                galleryIDs = Set(rows.map(\.id))
            }
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
            posterOptionsProvider: { [duelPool, belief] dimension in
                QuestionEngine.posterOutcomes(for: dimension, pool: duelPool, belief: belief)
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
        case .posterDuel:
            var options = QuestionEngine.pickDuel(from: duelPool, belief: belief)
            var fromGallery = duelPoolIsGallery
            if options == nil, fromGallery {
                // Une galerie trop homogène n'offre pas de paire contrastée :
                // le vivier reprend la main plutôt que de classer la question
                // la plus informative du parcours.
                options = QuestionEngine.pickDuel(from: posterPool, belief: belief)
                fromGallery = false
            }
            guard let options else {
                // Plus assez de films jamais montrés pour opposer deux affiches —
                // on classe la question plutôt que de boucler dessus.
                askedDimensions.insert(.posterDuel)
                advance()
                return
            }
            duelSourceIsGallery = fromGallery
            pairwiseOptions = options
            eliminationOptions = nil
        case .elimination:
            var options = QuestionEngine.pickElimination(from: duelPool, belief: belief)
            var fromGallery = duelPoolIsGallery
            if options == nil, fromGallery {
                options = QuestionEngine.pickElimination(from: posterPool, belief: belief)
                fromGallery = false
            }
            guard let options else {
                askedDimensions.insert(.elimination)
                advance()
                return
            }
            duelSourceIsGallery = fromGallery
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
            var finalCandidates: [EnrichedCandidateRow]
            if enrichedPool.isEmpty {
                let toEnrich = QuestionEngine.candidatesForEnrichment(pool: pool, belief: belief)
                finalCandidates = try await recommendationClient.enrichCandidates(toEnrich)
            } else {
                finalCandidates = enrichedPool
            }
            // La garantie, tenue au dernier moment plutôt que supposée : un film
            // écarté ne peut pas atteindre le trio, quel que soit le chemin par
            // lequel il serait revenu dans le vivier.
            finalCandidates.removeAll { excludedIDs.contains($0.id) }
            guard !finalCandidates.isEmpty else {
                phase = .error(String(localized: "Aucun film ne correspond à ces critères pour le moment.", bundle: .app))
                return
            }
            // Conservé pour que le refus du trio puisse recomposer une sélection
            // sans repayer l'enrichissement — le vivier de la séance reste chaud.
            enrichedPool = finalCandidates
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

    /// Ce que la réponse change concrètement pour la sélection, en une ligne.
    ///
    /// Elle dit toujours une conséquence (« on écartera… », « on ira chercher… »)
    /// et jamais un constat sur la personne : c'est ce qui rend le questionnaire
    /// lisible comme une recherche en cours plutôt que comme un test de
    /// personnalité. Rien n'est produit quand la réponse ne se résume pas
    /// honnêtement — une ligne creuse coûte plus cher que pas de ligne du tout.
    private static func reading(for dimension: AdaptiveDimension, answers: QuestionnaireAnswers) -> String? {
        switch dimension {
        case .dealbreaker:
            switch answers.dealbreaker {
            case .slowPace: String(localized: "On écartera les films qui traînent en longueur.", bundle: .app)
            case .heavyMood: String(localized: "On écartera les films trop lourds.", bundle: .app)
            case .tooLong: String(localized: "On surveillera la durée.", bundle: .app)
            case .predictablePlot: String(localized: "On cherchera une histoire qui surprend.", bundle: .app)
            case nil: nil
            }
        case .popularity:
            switch answers.popularity {
            case .hiddenGem: String(localized: "On ira chercher au-delà des films les plus vus.", bundle: .app)
            case .mainstream: String(localized: "On restera sur des films largement appréciés.", bundle: .app)
            default: nil
            }
        case .cognitiveMode:
            answers.cognitiveMode == .understand
                ? String(localized: "On privilégiera les films qui donnent à réfléchir.", bundle: .app)
                : String(localized: "On privilégiera les films qui font d'abord ressentir.", bundle: .app)
        default:
            nil
        }
    }

    /// Après un duel d'affiches. On ne commente que si l'écart de notoriété entre
    /// les deux films est net — sinon le choix a tranché autre chose, qu'on ne
    /// saurait pas nommer sans inventer.
    private static func reading(winner: CandidateRow, loser: CandidateRow) -> String? {
        let gap = winner.axes[.familiarite] - loser.axes[.familiarite]
        guard abs(gap) > 0.4 else { return nil }
        return gap < 0
            ? String(localized: "Tu vas vers les films connus : on en tient compte.", bundle: .app)
            : String(localized: "Tu vas vers les films moins connus : on en tient compte.", bundle: .app)
    }
}
