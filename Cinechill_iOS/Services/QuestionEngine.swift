//
//  QuestionEngine.swift
//  Cinechill_iOS
//

import Foundation

/// Les questions que le moteur peut poser, une fois le cadre et le cadran passés.
///
/// Il n'y a plus de « tier 1 » et de « tier 2 » : la contrainte que cette découpe
/// exprimait à la main — ne pas interroger la durée avant de la connaître — se
/// produit maintenant toute seule. Tant qu'aucun film n'a de durée mesurée, leur
/// position sur cet axe est identique, aucune réponse ne déplacerait le classement,
/// la valeur de décision est nulle, et la question n'est pas choisie. Après
/// enrichissement, les durées arrivent, les films se dispersent, et la même question
/// redevient l'une des plus rentables. Au film près, pas à la phase près.
///
/// `origin` et `era` ont disparu : elles ne se projettent sur aucun des huit axes,
/// donc le scoring par croyance les ignorerait. Les poser en le sachant aurait été
/// malhonnête ; les rétablir demandera soit un axe de plus, soit un filtre de vivier.
nonisolated enum AdaptiveDimension: CaseIterable, Hashable {
    case mood, mindset, dealbreaker, popularity, cast
    case horrorFlavor, comedyFlavor, dramaFlavor, cognitiveMode
    case storyOrigin, attachment, creditsMoment, lastingTrace
    case elimination, surpriseIntensity

    var questionStep: QuestionStep {
        switch self {
        case .mood: .mood
        case .mindset: .mindset
        case .dealbreaker: .dealbreaker
        case .popularity: .popularity
        case .cast: .cast
        case .horrorFlavor: .horrorFlavor
        case .comedyFlavor: .comedyFlavor
        case .dramaFlavor: .dramaFlavor
        case .cognitiveMode: .cognitiveMode
        case .storyOrigin: .storyOrigin
        case .attachment: .attachment
        case .creditsMoment: .creditsMoment
        case .lastingTrace: .lastingTrace
        case .elimination: .elimination
        case .surpriseIntensity: .surpriseIntensity
        }
    }

    /// Les nuances par genre n'ont de sens que si le genre pèse encore dans le vivier
    /// *courant* — et non parce qu'il aurait été coché au départ. C'est plus dynamique,
    /// et ça survit au resserrement du vivier.
    func isEligible(pool: [CandidateRow]) -> Bool {
        switch self {
        case .horrorFlavor: Self.genreShare(27, in: pool) > 0.15
        case .comedyFlavor: Self.genreShare(35, in: pool) > 0.15
        case .dramaFlavor: Self.genreShare(18, in: pool) > 0.15
        default: true
        }
    }

    private static func genreShare(_ genreID: Int, in pool: [CandidateRow]) -> Double {
        guard !pool.isEmpty else { return 0 }
        return Double(pool.filter { $0.genreIds.contains(genreID) }.count) / Double(pool.count)
    }

    /// La famille d'interaction, pour éviter d'enchaîner trois fois le même format.
    var format: QuestionFormat {
        switch self {
        case .mood, .elimination: .posters
        case .surpriseIntensity: .slider
        default: .chips
        }
    }
}

nonisolated enum QuestionFormat: Hashable {
    case chips, slider, posters
}

/// Le moteur de sélection par valeur de décision.
///
/// Il tourne entièrement côté client, entre deux appels réseau, sur des données déjà
/// rapatriées. Sa règle tient en une phrase : **on ne cherche pas la question qui
/// divise le catalogue, on cherche celle qui change la réponse.** Une question dont
/// toutes les réponses mènent au même trio vaut zéro et ne sera jamais posée, même si
/// elle sépare magnifiquement le vivier.
nonisolated enum QuestionEngine {
    /// En deçà, plus aucune question ne vaut la peine d'être posée.
    ///
    /// Calibré sur l'échelle de `divergence` : deux films d'archétypes différents sont
    /// distants d'environ 0,4, donc échanger la troisième place contre un tout autre
    /// genre de film vaut ~0,08, et un simple remaniement entre films voisins ~0,04.
    /// Le seuil passe entre les deux — on continue tant qu'une réponse pourrait
    /// changer la *nature* d'une des trois propositions, pas seulement leur ordre.
    static let decisionThreshold = 0.06
    /// Le plancher de questions, selon ce qu'on sait déjà de la personne.
    ///
    /// C'est la seule partie du parcours qui **n'émerge pas** du critère de décision :
    /// c'est une décision de produit, assumée comme telle. Deux raisons la justifient.
    /// D'abord la crédibilité — trois films sortis après une seule question ne se
    /// croient pas, même s'ils sont justes. Ensuite l'investissement : chez quelqu'un
    /// dont on ne sait rien, une question qui ne change pas le trio de ce soir nourrit
    /// quand même le trait, et raccourcira toutes les séances suivantes. Elle n'est
    /// donc pas perdue, elle est placée.
    ///
    /// Chez un habitué, cet argument tombe — on sait déjà — et le plancher s'efface.
    static func minimumQuestions(establishedAxes: Int) -> Int {
        switch establishedAxes {
        case 6...: 2
        case 3...5: 4
        default: 6
        }
    }
    /// Au-delà, la fatigue coûte plus cher que la précision ne rapporte.
    static let maximumQuestions = 10
    /// Le sous-ensemble sur lequel on simule. Un film classé 200ᵉ ne remonte pas dans
    /// le trio sur une seule observation : simuler au-delà coûterait sans rien changer.
    static let simulationDepth = 50
    static let enrichmentBatchSize = 35

    // MARK: - Le classement

    /// Le score d'un film : une proximité tolérante au doute. Si l'on ignore où se
    /// situe la personne (σ grand) *ou* où se situe le film (s grand), le terme
    /// s'aplatit et l'axe cesse de départager. Le modèle ne bluffe jamais.
    ///
    /// Reproduit `beliefScore` côté serveur — les deux doivent rester d'accord, sans
    /// quoi le classement local et le résultat final divergeraient.
    static func score(_ axes: AxisValues, sigma: AxisValues, belief: BeliefState) -> Double {
        var weighted = 0.0
        var total = 0.0
        for axis in Axis.allCases {
            let w = belief.weight(axis)
            guard w > 0 else { continue }
            let beliefSigma = belief.sigma(axis)
            let filmSigma = sigma.sigma(axis)
            let spread = beliefSigma * beliefSigma + filmSigma * filmSigma
            guard spread > 0 else { continue }
            let delta = belief.mean(axis) - axes[axis]
            weighted += w * exp(-(delta * delta) / (2 * spread))
            total += w
        }
        guard total > 0 else { return 0.5 }
        return weighted / total
    }

    static func score(_ row: CandidateRow, belief: BeliefState) -> Double {
        score(row.axes, sigma: row.axisSigma, belief: belief)
    }

    static func ranked(_ pool: [CandidateRow], belief: BeliefState) -> [CandidateRow] {
        pool
            .map { (row: $0, value: score($0, belief: belief)) }
            .sorted { $0.value > $1.value }
            .map(\.row)
    }

    static func topCandidates(_ pool: [CandidateRow], belief: BeliefState, limit: Int) -> [CandidateRow] {
        Array(ranked(pool, belief: belief).prefix(limit))
    }

    static func candidatesForEnrichment(pool: [CandidateRow], belief: BeliefState) -> [CandidateRow] {
        topCandidates(pool, belief: belief, limit: enrichmentBatchSize)
    }

    // MARK: - La valeur de décision

    /// De combien le trio bougerait, en moyenne, si l'on posait cette question.
    ///
    /// Les réponses sont supposées équiprobables. C'est une approximation assumée :
    /// on pourrait estimer leur vraisemblance depuis la croyance courante, mais une
    /// erreur de prédiction ne coûterait qu'une question un peu moins pertinente —
    /// jamais une recommandation absurde — et la complexité n'en vaut pas la peine
    /// tant que rien ne calibre ce modèle.
    static func decisionValue(
        for dimension: AdaptiveDimension,
        pool: [CandidateRow],
        belief: BeliefState,
        posterOptions: [[AxisObservation]] = []
    ) -> Double {
        let focus = topCandidates(pool, belief: belief, limit: simulationDepth)
        guard focus.count >= 4 else { return 0 }

        let outcomes = dimension.format == .posters
            ? posterOptions
            : AnswerObservations.table(for: dimension).map(\.observations)
        guard !outcomes.isEmpty else { return 0 }

        let before = topRows(focus, belief: belief)
        let total = outcomes.reduce(0.0) { sum, observations in
            let after = topRows(focus, belief: belief.observing(observations))
            return sum + divergence(before, after)
        }
        return total / Double(outcomes.count)
    }

    /// La question la plus décisive parmi celles qui restent, ou `nil` s'il n'en reste
    /// aucune. Rend l'argmax **même sous le seuil** : décider s'il vaut la peine de la
    /// poser revient à `shouldStop`, qui seul connaît le plancher de questions. Les
    /// mélanger ferait taire le moteur dès la première question quand toutes les
    /// valeurs sont basses, alors qu'on veut justement en poser quelques-unes.
    ///
    /// Un correctif tempère l'argmax : la variété, qui pénalise un troisième format
    /// identique d'affilée.
    static func nextDimension(
        pool: [CandidateRow],
        belief: BeliefState,
        asked: Set<AdaptiveDimension>,
        recentFormats: [QuestionFormat],
        posterOptionsProvider: (AdaptiveDimension) -> [[AxisObservation]]
    ) -> (dimension: AdaptiveDimension, value: Double)? {
        let eligible = AdaptiveDimension.allCases.filter {
            !asked.contains($0) && $0.isEligible(pool: pool)
        }
        guard !eligible.isEmpty else { return nil }

        var best: (AdaptiveDimension, Double)?
        for dimension in eligible {
            let raw = decisionValue(
                for: dimension,
                pool: pool,
                belief: belief,
                posterOptions: posterOptionsProvider(dimension)
            )
            let adjusted = raw * varietyFactor(for: dimension, recentFormats: recentFormats)
            if adjusted > (best?.1 ?? -1) {
                best = (dimension, adjusted)
            }
        }
        guard let best else { return nil }
        return (best.0, best.1)
    }

    static func shouldStop(
        bestValue: Double?, questionsAsked: Int, establishedAxes: Int
    ) -> Bool {
        if questionsAsked >= maximumQuestions { return true }
        guard questionsAsked >= minimumQuestions(establishedAxes: establishedAxes) else { return false }
        guard let bestValue else { return true }
        return bestValue < decisionThreshold
    }

    /// Deux questions du même format d'affilée passent ; la troisième lasse.
    private static func varietyFactor(
        for dimension: AdaptiveDimension, recentFormats: [QuestionFormat]
    ) -> Double {
        let sameInARow = recentFormats.suffix(2).filter { $0 == dimension.format }.count
        return sameInARow >= 2 ? 0.6 : 1
    }

    private static func topRows(_ pool: [CandidateRow], belief: BeliefState) -> [CandidateRow] {
        Array(ranked(pool, belief: belief).prefix(3))
    }

    /// De combien le trio changerait *réellement*, rang par rang.
    ///
    /// On mesure la distance dans l'espace des axes entre le film qui occupait un rang
    /// et celui qui l'occuperait — et non la simple identité des films. La différence
    /// est décisive : remplacer une comédie chaude par une autre comédie chaude ne
    /// change rien pour la personne qui regarde, alors qu'un décompte d'identifiants
    /// y verrait un bouleversement et continuerait de poser des questions bien après
    /// que la décision est prise.
    ///
    /// Pondéré par le rang : perdre la tête d'affiche compte plus que la troisième place.
    private static func divergence(_ before: [CandidateRow], _ after: [CandidateRow]) -> Double {
        guard !before.isEmpty else { return 0 }
        let weights = [0.5, 0.3, 0.2]
        var total = 0.0
        for rank in 0..<min(3, before.count) {
            guard rank < after.count else {
                total += weights[rank]
                continue
            }
            total += weights[rank] * axisDistance(before[rank], after[rank])
        }
        return total
    }

    /// Distance moyenne entre deux films sur les axes, normalisée sur 0…1.
    private static func axisDistance(_ lhs: CandidateRow, _ rhs: CandidateRow) -> Double {
        guard lhs.id != rhs.id else { return 0 }
        let sum = Axis.allCases.reduce(0.0) { acc, axis in
            acc + abs(lhs.axes[axis] - rhs.axes[axis])
        }
        // L'amplitude d'un axe vaut 2 (de −1 à +1) : on ramène la moyenne sur 0…1.
        return min(1, sum / (Double(Axis.allCases.count) * 2))
    }

    // MARK: - Les affiches

    /// L'axe qu'il serait le plus utile de trancher : celui sur lequel on doute encore,
    /// et sur lequel le vivier est effectivement partagé. Douter d'un axe où tous les
    /// films se valent n'apporterait rien.
    static func mostUncertainAxis(pool: [CandidateRow], belief: BeliefState) -> Axis? {
        let focus = topCandidates(pool, belief: belief, limit: simulationDepth)
        guard focus.count >= 4 else { return nil }
        return Axis.allCases.max { lhs, rhs in
            uncertaintyGain(lhs, focus, belief) < uncertaintyGain(rhs, focus, belief)
        }
    }

    private static func uncertaintyGain(
        _ axis: Axis, _ focus: [CandidateRow], _ belief: BeliefState
    ) -> Double {
        let values = focus.map { $0.axes[axis] }
        guard let min = values.min(), let max = values.max() else { return 0 }
        return belief.sigma(axis) * (max - min)
    }

    /// Les deux films les plus opposés sur l'axe le plus incertain — comparer deux
    /// films qui se ressemblent n'apprendrait rien.
    static func pickDuel(
        from pool: [CandidateRow], belief: BeliefState
    ) -> (CandidateRow, CandidateRow)? {
        guard let axis = mostUncertainAxis(pool: pool, belief: belief) else { return nil }
        let focus = topCandidates(pool, belief: belief, limit: simulationDepth)
        let sorted = focus.sorted { $0.axes[axis] < $1.axes[axis] }
        guard let low = sorted.first, let high = sorted.last, low.id != high.id else { return nil }
        guard high.axes[axis] - low.axes[axis] > 0.3 else { return nil }
        return (high, low)
    }

    /// Quatre films aussi dispersés que possible sur l'axe le plus incertain.
    static func pickElimination(
        from pool: [CandidateRow], belief: BeliefState
    ) -> [CandidateRow]? {
        guard let axis = mostUncertainAxis(pool: pool, belief: belief) else { return nil }
        let focus = topCandidates(pool, belief: belief, limit: simulationDepth)
        guard focus.count >= 4 else { return nil }
        let sorted = focus.sorted { $0.axes[axis] < $1.axes[axis] }
        let step = Double(sorted.count - 1) / 3
        let picked = (0..<4).map { sorted[Int((Double($0) * step).rounded())] }
        return Set(picked.map(\.id)).count == 4 ? picked : Array(focus.prefix(4))
    }

    /// Les issues possibles d'une question par affiches, pour la simulation.
    static func posterOutcomes(
        for dimension: AdaptiveDimension, pool: [CandidateRow], belief: BeliefState
    ) -> [[AxisObservation]] {
        switch dimension {
        case .mood:
            guard let (a, b) = pickDuel(from: pool, belief: belief) else { return [] }
            return [
                AnswerObservations.fromDuel(winner: a, loser: b),
                AnswerObservations.fromDuel(winner: b, loser: a),
            ]
        case .elimination:
            guard let options = pickElimination(from: pool, belief: belief) else { return [] }
            return options.map { loser in
                AnswerObservations.fromElimination(
                    loser: loser, others: options.filter { $0.id != loser.id }
                )
            }
        default:
            return []
        }
    }
}
