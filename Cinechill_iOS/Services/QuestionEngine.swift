//
//  QuestionEngine.swift
//  Cinechill_iOS
//

import Foundation

/// Les dimensions "adaptatives" du quiz — tout ce qui n'est pas le socle (T1-T4). Le moteur
/// choisit laquelle interroger ensuite en estimant, à chaque étape, laquelle séparerait le plus
/// le pool de candidats *actuel* — voir la spec "moteur de préférence actif".
///
/// Tier 1 : calculable sur `CandidateRow` (champs des endpoints de liste TMDB, déjà en main
/// après `getCandidatePool`). Tier 2 : nécessite `EnrichedCandidateRow` (détail TMDB, un appel
/// par film — voir `enrichCandidates`), donc seulement disponible après la bascule de phase.
nonisolated enum AdaptiveDimension: CaseIterable, Hashable {
    case mood, popularity, era, origin, mindset, dealbreaker
    case cast, runtime
    case horrorFlavor, comedyFlavor, dramaFlavor, cognitiveMode, elimination, surpriseIntensity

    var tier: Int {
        switch self {
        case .cast, .runtime: 2
        default: 1
        }
    }

    var questionStep: QuestionStep {
        switch self {
        case .mood: .mood
        case .popularity: .popularity
        case .era: .era
        case .origin: .origin
        case .mindset: .mindset
        case .dealbreaker: .dealbreaker
        case .cast: .cast
        case .runtime: .runtime
        case .horrorFlavor: .horrorFlavor
        case .comedyFlavor: .comedyFlavor
        case .dramaFlavor: .dramaFlavor
        case .cognitiveMode: .cognitiveMode
        case .elimination: .elimination
        case .surpriseIntensity: .surpriseIntensity
        }
    }

    /// Les nuances par genre n'ont de sens que si le genre correspondant a été choisi au socle —
    /// sinon la question tomberait à plat (ex. "quel genre d'horreur" sans avoir choisi Horreur).
    func isEligible(given answers: QuestionnaireAnswers) -> Bool {
        switch self {
        case .horrorFlavor: answers.genres.contains(.horror)
        case .comedyFlavor: answers.genres.contains(.comedy)
        case .dramaFlavor: answers.genres.contains(.drama)
        default: true
        }
    }
}

/// Moteur de sélection par gain d'information. Tourne entièrement côté client — aucun aller-retour
/// réseau par question, seulement sur les données déjà rapatriées (`CandidateRow`/`EnrichedCandidateRow`).
///
/// Le "gain" estimé ici est une heuristique volontairement simple (répartition des candidats
/// actuels entre les réponses possibles d'une question) — pas une réplique de la formule de score
/// pondéré du backend, qui reste la seule source de vérité pour le score final. Le but n'est pas
/// de calculer un score exact localement, mais de savoir *laquelle* des questions restantes vaut
/// la peine d'être posée maintenant.
nonisolated enum QuestionEngine {
    static let confidenceThreshold = 0.15
    static let minimumQuestionsBeforeAutoStop = 6
    static let focusPoolSize = 60
    static let enrichmentBatchSize = 35

    // MARK: - Choix de la prochaine question

    static func nextTier1Dimension(
        pool: [CandidateRow], answers: QuestionnaireAnswers, asked: Set<AdaptiveDimension>
    ) -> AdaptiveDimension? {
        let eligible = AdaptiveDimension.allCases.filter {
            $0.tier == 1 && !asked.contains($0) && $0.isEligible(given: answers)
        }
        guard !eligible.isEmpty else { return nil }
        let focus = topCandidates(pool, answers: answers, limit: focusPoolSize)
        return eligible.max { tier1Gain(for: $0, in: focus) < tier1Gain(for: $1, in: focus) }
    }

    static func nextTier2Dimension(
        pool: [EnrichedCandidateRow], asked: Set<AdaptiveDimension>
    ) -> AdaptiveDimension? {
        let eligible = AdaptiveDimension.allCases.filter { $0.tier == 2 && !asked.contains($0) }
        guard !eligible.isEmpty else { return nil }
        return eligible.max { tier2Gain(for: $0, in: pool) < tier2Gain(for: $1, in: pool) }
    }

    // MARK: - Condition d'arrêt par confiance

    /// Écart normalisé entre le score du rang 3 et celui du rang 4 du classement local actuel —
    /// voir la spec, section "condition d'arrêt par confiance". `nil` si le pool a moins de 4
    /// candidats (pas assez pour que la notion de "top 3 séparé du reste" ait un sens).
    static func confidenceGap(pool: [CandidateRow], answers: QuestionnaireAnswers) -> Double? {
        let ranked = pool
            .map { localProvisionalScore($0, answers: answers) }
            .sorted(by: >)
        guard ranked.count >= 4, ranked[2] > 0 else { return nil }
        return (ranked[2] - ranked[3]) / ranked[2]
    }

    static func confidenceGap(pool: [EnrichedCandidateRow], answers: QuestionnaireAnswers) -> Double? {
        let ranked = pool
            .map { localProvisionalScore($0.base, enriched: $0, answers: answers) }
            .sorted(by: >)
        guard ranked.count >= 4, ranked[2] > 0 else { return nil }
        return (ranked[2] - ranked[3]) / ranked[2]
    }

    static func isConfident(gap: Double?, questionsAsked: Int) -> Bool {
        guard let gap, questionsAsked >= minimumQuestionsBeforeAutoStop else { return false }
        return gap >= confidenceThreshold
    }

    // MARK: - Sous-ensemble à enrichir (bascule de phase)

    /// Les meilleurs candidats du pool grossier, à envoyer à `enrichCandidates` — voir
    /// `enrichmentBatchSize`, calé sur le plafond `ENRICH_BATCH_MAX` du backend.
    static func candidatesForEnrichment(
        pool: [CandidateRow], answers: QuestionnaireAnswers
    ) -> [CandidateRow] {
        topCandidates(pool, answers: answers, limit: enrichmentBatchSize)
    }

    static func topCandidates(
        _ pool: [CandidateRow], answers: QuestionnaireAnswers, limit: Int
    ) -> [CandidateRow] {
        pool
            .sorted { localProvisionalScore($0, answers: answers) > localProvisionalScore($1, answers: answers) }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - Décrocheur — filtre local une fois répondu

    /// `heavyMood`/`slowPace` filtraient la requête TMDB elle-même dans l'ancienne architecture ;
    /// le décrocheur est maintenant une question adaptative posée *après* avoir déjà le pool en
    /// main, donc appliqué ici comme un filtre local sur les champs déjà connus (`genre_ids`,
    /// `vote_count`). `tooLong`/`predictablePlot` ont besoin de champs indisponibles avant
    /// enrichissement (durée, franchise) — `tooLong` est approché via `runtimeProximity` en tier 2,
    /// `predictablePlot` reste filtré côté serveur à la finalisation, comme avant.
    /// Ne s'applique jamais si ça ferait passer le pool sous le plancher — mieux vaut un décrocheur
    /// ignoré qu'un pool vide.
    static func applyDealbreakerFilter(to pool: [CandidateRow], dealbreaker: Dealbreaker) -> [CandidateRow] {
        let filtered: [CandidateRow]
        switch dealbreaker {
        case .heavyMood:
            filtered = pool.filter { !$0.genreIds.contains(GenreMirror.war) && !$0.genreIds.contains(GenreMirror.history) }
        case .slowPace:
            filtered = pool.filter { ($0.voteCount ?? 0) >= 300 }
        case .tooLong, .predictablePlot:
            return pool
        }
        return filtered.count >= 20 ? filtered : pool
    }

    // MARK: - Nuances par genre / question projective — traduites en boost de genre

    /// Les nuances par genre et la question projective n'ont pas de champ dédié côté scoring —
    /// elles se traduisent en un boost/malus sur `preferredGenreIDs`/`avoidedGenreIDs`, exactement
    /// comme la comparaison directe (voir `recordPairwiseChoice`), plutôt que d'ajouter un chemin
    /// de score séparé pour chacune.
    static func applyFlavorChoice(dimension: AdaptiveDimension, answers: inout QuestionnaireAnswers) {
        switch dimension {
        case .horrorFlavor:
            if answers.horrorFlavor == .suspense { answers.preferredGenreIDs.insert(GenreMirror.thriller) }
        case .comedyFlavor:
            if answers.comedyFlavor == .family {
                answers.preferredGenreIDs.insert(GenreMirror.family)
            } else if answers.comedyFlavor == .edgy {
                answers.avoidedGenreIDs.insert(GenreMirror.family)
            }
        case .dramaFlavor:
            if answers.dramaFlavor == .intimate { answers.preferredGenreIDs.insert(GenreMirror.romance) }
        case .cognitiveMode:
            if answers.cognitiveMode == .understand {
                answers.preferredGenreIDs.formUnion(GenreMirror.understand)
            } else if answers.cognitiveMode == .feel {
                answers.preferredGenreIDs.formUnion(GenreMirror.feel)
            }
        default:
            break
        }
    }

    // MARK: - Comparaison directe (mood)

    /// Choisit deux candidats du pool aussi différents que possible en ambiance, pour
    /// `PairwiseComparisonView` — comparer deux films quasi identiques n'apporterait aucun signal.
    /// `nil` si le pool restreint n'offre pas deux buckets d'ambiance distincts.
    static func pickPairwiseOptions(
        from pool: [CandidateRow], answers: QuestionnaireAnswers
    ) -> (CandidateRow, CandidateRow)? {
        let focus = topCandidates(pool, answers: answers, limit: focusPoolSize)
        let byBucket = Dictionary(grouping: focus, by: { moodBucket(for: $0.genreIds) })
        let buckets = byBucket.keys.compactMap { $0 }
        guard buckets.count >= 2 else { return nil }
        let sortedBuckets = buckets.sorted { (byBucket[$0]?.count ?? 0) > (byBucket[$1]?.count ?? 0) }
        guard let first = byBucket[sortedBuckets[0]]?.first,
              let second = byBucket[sortedBuckets[1]]?.first else { return nil }
        return (first, second)
    }

    // MARK: - Élimination

    /// Quatre candidats aussi variés que possible pour `EliminationView` — un signal de rejet plus
    /// large qu'un simple duel (voir `recordPairwiseChoice`), puisqu'il écarte un film parmi quatre
    /// plutôt que deux. `nil` si le pool restreint est trop petit pour en proposer quatre.
    static func pickEliminationOptions(
        from pool: [CandidateRow], answers: QuestionnaireAnswers
    ) -> [CandidateRow]? {
        let focus = topCandidates(pool, answers: answers, limit: focusPoolSize)
        guard focus.count >= 4 else { return nil }
        let byBucket = Dictionary(grouping: focus, by: { moodBucket(for: $0.genreIds) })
        let diverse = byBucket.values.compactMap(\.first)
        return Array((diverse.count >= 4 ? diverse : focus).prefix(4))
    }

    // MARK: - Gain d'information (tier 1 — CandidateRow)

    private static func tier1Gain(for dimension: AdaptiveDimension, in pool: [CandidateRow]) -> Double {
        guard !pool.isEmpty else { return 0 }
        switch dimension {
        case .mood:
            return bucketSpread(pool.map { moodBucket(for: $0.genreIds) })
        case .popularity:
            return bucketSpread(pool.map { tertileBucket($0.popularity ?? 0, in: pool.map { $0.popularity ?? 0 }) })
        case .era:
            return bucketSpread(pool.map { $0.releaseYear.map { $0 / 10 } })
        case .origin:
            let frCount = pool.filter { $0.originCountry.contains("FR") }.count
            let frFraction = Double(frCount) / Double(pool.count)
            return 2 * min(frFraction, 1 - frFraction)
        case .mindset:
            return bucketSpread(pool.map { mindsetBucket(genreIds: $0.genreIds, popularity: $0.popularity) })
        case .dealbreaker:
            let heavyMoodExcluded = pool.filter { $0.genreIds.contains(GenreMirror.war) || $0.genreIds.contains(GenreMirror.history) }.count
            let slowPaceExcluded = pool.filter { ($0.voteCount ?? 0) < 300 }.count
            let bestFraction = [heavyMoodExcluded, slowPaceExcluded].map { Double($0) / Double(pool.count) }.max() ?? 0
            return 1 - abs(bestFraction - 0.5) * 2
        case .horrorFlavor:
            return genreSplitGain(pool, genreId: GenreMirror.thriller)
        case .comedyFlavor:
            return genreSplitGain(pool, genreId: GenreMirror.family)
        case .dramaFlavor:
            return genreSplitGain(pool, genreId: GenreMirror.romance)
        case .cognitiveMode:
            let understandCount = pool.filter { !GenreMirror.understand.isDisjoint(with: $0.genreIds) }.count
            let feelCount = pool.filter { !GenreMirror.feel.isDisjoint(with: $0.genreIds) }.count
            let total = understandCount + feelCount
            guard total > 0 else { return 0 }
            let coverage = Double(total) / Double(pool.count)
            return 2 * min(Double(understandCount), Double(feelCount)) / Double(total) * coverage
        case .elimination:
            return bucketSpread(pool.map { moodBucket(for: $0.genreIds) })
        case .surpriseIntensity:
            // Pas de champ discriminant côté pool grossier (voir la spec) — gain fixe modéré pour
            // rester compétitif face aux autres dimensions sans jamais les éclipser.
            return 0.35
        case .cast, .runtime:
            return 0
        }
    }

    /// Fraction du pool qui porte `genreId`, transformée en un score de 0 (quasi tout le monde ou
    /// personne) à 1 (coupure parfaite en deux) — même logique que `.origin` ci-dessus.
    private static func genreSplitGain(_ pool: [CandidateRow], genreId: Int) -> Double {
        let withCount = pool.filter { $0.genreIds.contains(genreId) }.count
        let fraction = Double(withCount) / Double(pool.count)
        return 2 * min(fraction, 1 - fraction)
    }

    // MARK: - Gain d'information (tier 2 — EnrichedCandidateRow)

    private static func tier2Gain(for dimension: AdaptiveDimension, in pool: [EnrichedCandidateRow]) -> Double {
        guard !pool.isEmpty else { return 0 }
        switch dimension {
        case .cast:
            let averages = pool.map { row -> Double in
                guard !row.castPopularities.isEmpty else { return 0 }
                return row.castPopularities.reduce(0, +) / Double(row.castPopularities.count)
            }
            return bucketSpread(averages.map { tertileBucket($0, in: averages) })
        case .runtime:
            return bucketSpread(pool.map { $0.runtimeMinutes.map { $0 / 20 } })
        default:
            return 0
        }
    }

    // MARK: - Score local provisoire (classement/confiance uniquement — jamais le score final)

    private static func localProvisionalScore(_ row: CandidateRow, answers: QuestionnaireAnswers) -> Double {
        var score = 0.0
        if let mood = answers.mood {
            score += 0.30 * (GenreMirror.mood[mood]?.isDisjoint(with: row.genreIds) == false ? 1 : 0.3)
        } else {
            score += 0.15
        }
        if !answers.preferredGenreIDs.isEmpty, !answers.preferredGenreIDs.isDisjoint(with: Set(row.genreIds)) {
            score += 0.1
        }
        if !answers.avoidedGenreIDs.isEmpty, !answers.avoidedGenreIDs.isDisjoint(with: Set(row.genreIds)) {
            score -= 0.1
        }
        score += 0.15 * ((row.voteAverage ?? 5) / 10)
        if answers.origin != .any, !row.originCountry.isEmpty {
            let isFrench = row.originCountry.contains("FR")
            score += 0.10 * (answers.origin == .french ? (isFrench ? 1 : 0.15) : (isFrench ? 0.15 : 1))
        }
        if answers.era != .any, let year = row.releaseYear {
            score += 0.10 * eraProximity(year: year, era: answers.era)
        }
        return max(0, score)
    }

    private static func localProvisionalScore(
        _ base: CandidateRow, enriched: EnrichedCandidateRow, answers: QuestionnaireAnswers
    ) -> Double {
        var score = localProvisionalScore(base, answers: answers)
        if answers.runtime != .any, let minutes = enriched.runtimeMinutes {
            score += 0.10 * runtimeProximity(minutes: minutes, preference: answers.runtime)
        }
        return score
    }

    private static func eraProximity(year: Int, era: EraPreference) -> Double {
        let age = Calendar.current.component(.year, from: .now) - year
        switch era {
        case .thisYear: return age <= 0 ? 1 : max(0, 1 - Double(age) / 4)
        case .lastFiveYears: return age <= 5 ? 1 : max(0, 1 - Double(age - 5) / 6)
        case .cultClassic: return min(1, Double(age) / 40)
        case .any: return 0.5
        }
    }

    private static func runtimeProximity(minutes: Int, preference: RuntimePreference) -> Double {
        switch preference {
        case .short: return minutes <= 95 ? 1 : max(0, 1 - Double(minutes - 95) / 25)
        case .medium: return (90...125).contains(minutes) ? 1 : 0.4
        case .long: return minutes >= 120 ? 1 : max(0, 1 - Double(120 - minutes) / 25)
        case .any: return 0.5
        }
    }

    // MARK: - Buckets et dispersion

    private static func moodBucket(for genreIds: [Int]) -> Mood? {
        Mood.allCases.first { mood in
            guard let genres = GenreMirror.mood[mood] else { return false }
            return !genres.isDisjoint(with: genreIds)
        }
    }

    private static func mindsetBucket(genreIds: [Int], popularity: Double?) -> String {
        if genreIds.contains(GenreMirror.documentary) || genreIds.contains(GenreMirror.history) { return "learn" }
        if genreIds.contains(GenreMirror.drama) { return "recognize" }
        if (popularity ?? 0) > 40 { return "noThinking" }
        return "surprise"
    }

    private static func tertileBucket(_ value: Double, in all: [Double]) -> Int {
        let sorted = all.sorted()
        guard !sorted.isEmpty else { return 0 }
        let rank = sorted.firstIndex(where: { $0 >= value }) ?? sorted.count - 1
        let fraction = Double(rank) / Double(max(1, sorted.count - 1))
        return fraction < 0.33 ? 0 : (fraction < 0.66 ? 1 : 2)
    }

    /// 1 = les candidats sont répartis également entre les buckets (question très discriminante),
    /// 0 = tous dans le même bucket (question qui ne trancherait plus rien).
    private static func bucketSpread<T: Hashable>(_ buckets: [T]) -> Double {
        guard !buckets.isEmpty else { return 0 }
        let counts = Dictionary(grouping: buckets, by: { $0 }).mapValues(\.count)
        let maxFraction = Double(counts.values.max() ?? 0) / Double(buckets.count)
        return 1 - maxFraction
    }
}

/// Tables de correspondance genre TMDB dupliquées à dessein depuis le backend (`GENRE_*`,
/// `MOOD_GENRES`) — pour l'estimation locale du gain d'information uniquement. Si le mapping
/// backend change, garder ces valeurs synchronisées.
private nonisolated enum GenreMirror {
    static let mood: [Mood: Set<Int>] = [
        .lightFun: [35],
        .intense: [28, 53],
        .emotional: [18, 10749],
        .scary: [27, 53],
        .escapist: [12, 14, 878, 28],
        .thoughtful: [9648, 878, 18],
    ]
    static let documentary = 99
    static let history = 36
    static let drama = 18
    static let war = 10752
    static let thriller = 53
    static let family = 10751
    static let romance = 10749
    static let mystery = 9648
    static let horror = 27

    /// Nuances par genre (voir `applyFlavorChoice`) — "comprendre" penche vers mystère/documentaire,
    /// "ressentir" vers horreur/romance. Proxy heuristique par genre, pas une vraie mesure du mode
    /// cognitif — même principe honnête que le reste de `GenreMirror`.
    static let understand: Set<Int> = [mystery, documentary]
    static let feel: Set<Int> = [horror, romance]
}
