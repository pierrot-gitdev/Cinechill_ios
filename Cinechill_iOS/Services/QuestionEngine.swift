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
    case posterDuel, mindset, dealbreaker, popularity, cast, paceWish
    case horrorFlavor, comedyFlavor, dramaFlavor, cognitiveMode
    case storyOrigin, attachment, creditsMoment, lastingTrace
    case elimination, surpriseIntensity

    var questionStep: QuestionStep {
        switch self {
        case .posterDuel: .posterDuel
        case .mindset: .mindset
        case .dealbreaker: .dealbreaker
        case .popularity: .popularity
        case .cast: .cast
        case .paceWish: .paceWish
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
        case .posterDuel, .elimination: .posters
        case .surpriseIntensity: .slider
        default: .chips
        }
    }

    /// Combien de fois cette question peut être posée dans une séance.
    ///
    /// Les questions par affiches sont les seules répétables, et c'est tout
    /// l'objet du budget : elles portent le signal le plus fort du parcours
    /// (`revealed`, contre `declared` pour une puce), elles renouvellent leur
    /// matière d'elles-mêmes — un film montré ne l'est plus jamais — et une
    /// seule d'entre elles ne pouvait pas départager trente-cinq candidats.
    /// Une puce, elle, ne se repose pas : la même question rendrait la même
    /// réponse.
    var askLimit: Int { format == .posters ? QuestionEngine.posterAskLimit : 1 }
}

nonisolated enum QuestionFormat: Hashable {
    case chips, slider, posters
}

/// Le moteur de sélection par valeur de décision.
///
/// Il tourne entièrement côté client, entre deux appels réseau, sur des données déjà
/// rapatriées. Sa règle tient en une phrase : **on ne cherche pas la question qui
/// divise le catalogue, on cherche celle qui change la réponse.** Une question dont
/// toutes les réponses mènent à la même tête de classement vaut zéro et ne sera
/// jamais posée, même si elle sépare magnifiquement le vivier.
nonisolated enum QuestionEngine {
    /// En deçà, plus aucune question ne vaut la peine d'être posée.
    ///
    /// Calibré sur l'échelle de `divergence` : deux films d'archétypes différents sont
    /// distants d'environ 0,4, donc échanger la troisième place contre un tout autre
    /// genre de film vaut ~0,08, et un simple remaniement entre films voisins ~0,04.
    /// Le seuil passe entre les deux — on continue tant qu'une réponse pourrait
    /// changer la *nature* d'une des trois propositions, pas seulement leur ordre.
    static let decisionThreshold = 0.06
    /// Le plancher de questions : une décision de produit, assumée comme telle.
    /// Un verdict rendu sans avoir rien demandé ne se croit pas, même juste.
    ///
    /// Il ne dépend plus de la richesse du profil. Cette modulation (2, 4 ou 6
    /// questions selon les axes déjà établis) datait d'avant la Porte : elle
    /// dosait l'effort pour quelqu'un dont on ne savait rien. Depuis que la
    /// Porte garantit trente films vus et six genres avant le premier écran,
    /// plus personne n'arrive ici sans profil — tout le monde retombait au
    /// plancher le plus bas, et un paramètre qui vaut toujours la même chose
    /// n'est plus un paramètre. Ce qui dose l'effort désormais, c'est la
    /// soirée : `eligibilityFloor` tient la boucle ouverte tant qu'aucun film
    /// n'est assez bon.
    static let minimumQuestions = 2
    /// Au-delà, la fatigue coûte plus cher que la précision ne rapporte. Relevé
    /// de 10 à 12 pour laisser de la place au départage, qui n'intervient qu'à
    /// la toute fin du parcours.
    static let maximumQuestions = 12
    /// Combien de questions par affiches au maximum dans une séance.
    static let posterAskLimit = 4
    /// La note minimale pour qu'un film soit proposable, sur l'échelle du score
    /// (0…1 ici, 0…100 côté serveur : c'est la même formule).
    ///
    /// Un film dont les axes pesés sont à 0,4 d'écart moyen de la croyance — la
    /// distance entre deux archétypes, celle qui a calibré `decisionThreshold` —
    /// note entre 0,75 et 0,86 selon la précision du profil ; à 0,2 d'écart il
    /// passe 0,93 ; à 0,6 il tombe sous 0,71. La barre passe donc là où un film
    /// cesse d'être *le bon* genre de film pour n'être plus que du même genre.
    ///
    /// Un effet à connaître avant de la déplacer : à écart égal, un profil plus
    /// précis donne un score plus **bas** — σ entre au dénominateur, et une
    /// croyance sûre d'elle pardonne moins. La barre est donc plus exigeante
    /// pour un habitué que pour quelqu'un qu'on connaît mal, ce qui est le bon
    /// sens mais rend la réouverture du vivier plus probable chez lui.
    ///
    /// C'est une constante de départ, pas une vérité : elle se recalibrera sur
    /// le score des films réellement lancés, refusés ou passés, que le serveur
    /// journalise désormais dans l'historique des séances.
    static let eligibilityFloor = 0.75
    /// L'écart de score en deçà duquel les deux têtes sont à égalité, et où le
    /// départage a quelque chose à trancher.
    static let separationGap = 0.02
    /// L'écart minimal entre deux affiches opposées. En deçà, le choix ne dit
    /// rien : on aura demandé de trancher entre deux films identiques.
    static let duelContrast = 0.3
    /// Le sous-ensemble sur lequel on simule. Un film classé 200ᵉ ne remonte pas dans
    /// la tête du classement sur une seule observation : simuler au-delà coûterait
    /// sans rien changer.
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

    /// La note du meilleur film du vivier. C'est elle que la barre interroge :
    /// tant qu'elle reste basse, la séance n'a rien trouvé qui vaille la peine
    /// d'être proposé, et il est trop tôt pour conclure.
    static func bestScore(pool: [CandidateRow], belief: BeliefState) -> Double {
        pool.map { score($0, belief: belief) }.max() ?? 0
    }

    /// Les deux têtes du classement et ce qui les sépare.
    static func leaders(
        _ pool: [CandidateRow], belief: BeliefState
    ) -> (first: CandidateRow, second: CandidateRow, gap: Double)? {
        let scored = pool
            .map { (row: $0, value: score($0, belief: belief)) }
            .sorted { $0.value > $1.value }
        guard scored.count >= 2 else { return nil }
        return (scored[0].row, scored[1].row, scored[0].value - scored[1].value)
    }

    // MARK: - La valeur de décision

    /// De combien la tête du classement bougerait, en moyenne, si l'on posait
    /// cette question.
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
        asked: [AdaptiveDimension: Int],
        retired: Set<AdaptiveDimension>,
        recentFormats: [QuestionFormat],
        posterOptionsProvider: (AdaptiveDimension) -> [[AxisObservation]]
    ) -> (dimension: AdaptiveDimension, value: Double)? {
        let eligible = AdaptiveDimension.allCases.filter {
            asked[$0, default: 0] < $0.askLimit
                && !retired.contains($0)
                && $0.isEligible(pool: pool)
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

    /// Faut-il cesser de poser des questions ?
    ///
    /// Deux conditions désormais, et non plus une : il ne suffit plus que le
    /// classement ait cessé de bouger, il faut aussi qu'il ait quelque chose à
    /// proposer. Un vivier où le meilleur film reste sous la barre est un
    /// vivier stable et mauvais — l'ancien critère y voyait la fin de la
    /// séance, alors que c'est exactement là qu'il faut continuer de chercher.
    ///
    /// Le plafond reste au-dessus de tout : passé douze questions, on conclut
    /// avec ce qu'on a, barre franchie ou non. À ce stade ce n'est plus la
    /// croyance qui manque, c'est le vivier — et c'est à la réouverture, pas
    /// aux questions, de le dire.
    static func shouldStop(
        bestValue: Double?, questionsAsked: Int, bestScore: Double
    ) -> Bool {
        if questionsAsked >= maximumQuestions { return true }
        guard questionsAsked >= minimumQuestions else { return false }
        guard bestScore >= eligibilityFloor else { return false }
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

    /// De combien la tête du classement changerait *réellement*, rang par rang.
    ///
    /// On mesure la distance dans l'espace des axes entre le film qui occupait un rang
    /// et celui qui l'occuperait — et non la simple identité des films. La différence
    /// est décisive : remplacer une comédie chaude par une autre comédie chaude ne
    /// change rien pour la personne qui regarde, alors qu'un décompte d'identifiants
    /// y verrait un bouleversement et continuerait de poser des questions bien après
    /// que la décision est prise.
    ///
    /// Pondéré par le rang, et de loin dominé par le premier : c'est lui qu'on
    /// proposera. Les deux suivants comptent quand même, parce qu'ils sont ce
    /// qu'on montrera si le verdict est refusé.
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
        guard high.axes[axis] - low.axes[axis] > duelContrast else { return nil }
        return (high, low)
    }

    // MARK: - Le départage

    /// L'axe sur lequel deux films s'opposent le plus, pondéré par ce que cet
    /// axe pèse dans le score. Un axe où ils diffèrent franchement mais dont on
    /// ne sait rien ne les départage pas : il ne compte pas dans leur note.
    static func separatingAxis(
        _ lhs: CandidateRow, _ rhs: CandidateRow, belief: BeliefState
    ) -> Axis? {
        Axis.allCases
            .map { ($0, belief.weight($0) * abs(lhs.axes[$0] - rhs.axes[$0])) }
            .filter { $0.1 > 0 }
            .max { $0.1 < $1.1 }?.0
    }

    /// Le duel de départage : deux films **vus** qui incarnent les deux têtes
    /// du classement sur l'axe qui les sépare.
    ///
    /// C'est le seul moyen d'interroger directement la frontière entre le n°1
    /// et son dauphin sans jamais montrer un film inconnu. Opposer les deux
    /// prétendants eux-mêmes serait plus direct, mais demanderait de choisir
    /// entre deux films qu'on n'a pas vus — un choix d'affiche, pas de goût.
    /// Leurs représentants dans la galerie posent la même question avec des
    /// souvenirs à la place des paris.
    static func pickAnchorDuel(
        between first: CandidateRow,
        and second: CandidateRow,
        gallery: [CandidateRow],
        belief: BeliefState
    ) -> (CandidateRow, CandidateRow)? {
        guard gallery.count >= 2 else { return nil }
        guard let axis = separatingAxis(first, second, belief: belief) else { return nil }

        let high = first.axes[axis] >= second.axes[axis] ? first : second
        let low = high.id == first.id ? second : first

        let closest = { (target: CandidateRow, excluding: Int?) -> CandidateRow? in
            gallery
                .filter { $0.id != excluding }
                .min { abs($0.axes[axis] - target.axes[axis]) < abs($1.axes[axis] - target.axes[axis]) }
        }
        guard let anchorHigh = closest(high, nil),
              let anchorLow = closest(low, anchorHigh.id) else { return nil }

        // Les ancres doivent trancher dans le même sens que les prétendants, et
        // assez franchement : deux souvenirs voisins ne diraient rien de l'axe
        // sur lequel la soirée hésite.
        guard anchorHigh.axes[axis] - anchorLow.axes[axis] > duelContrast else { return nil }
        return (anchorHigh, anchorLow)
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
        case .posterDuel:
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
