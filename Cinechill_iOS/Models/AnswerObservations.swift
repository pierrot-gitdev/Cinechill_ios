//
//  AnswerObservations.swift
//  Cinechill_iOS
//

import Foundation

/// La table de correspondance entre ce qu'on demande et ce qu'on mesure.
///
/// C'est la pièce qui rend le corpus extensible : une question peut être aussi
/// indirecte qu'on veut tant qu'on sait dire *ce qu'elle révèle*. Rien ici ne
/// calcule de score — on ne fait que déposer des indices, et c'est la croyance
/// (`BeliefState`) qui les accumule.
nonisolated enum AnswerObservations {

    // MARK: - Les forces

    /// Une puce, c'est-à-dire une déclaration. Les gens se décrivent mal : on les
    /// écoute, mais moins fort qu'on ne les regarde.
    static let declared = 0.6
    /// Un curseur : une déclaration, mais continue — donc un peu plus riche.
    static let slider = 0.8
    /// Un choix d'affiche, c'est-à-dire un comportement. Pondéré 1,5× le déclaré :
    /// jugement assumé, aligné sur la littérature de préférence révélée, et qui
    /// reste à calibrer le jour où l'on saura quel film a réellement été lancé.
    static let revealed = 0.9
    /// Une contrainte annoncée au cadre — pas une envie, un cadre. Plus forte que
    /// tout le reste, et rien ne doit pouvoir la récrire.
    static let constraint = 1.5

    // MARK: - L'ambiance

    /// L'ambiance demandée, convertie en indices.
    ///
    /// C'est la réponse la plus structurante du parcours, donc la plus forte —
    /// mais seulement là où elle sait quelque chose. Elle ne dit rien de la
    /// découverte, de la complexité ni de la durée : une comédie peut être
    /// limpide ou retorse, connue ou confidentielle. Rester muet sur ces axes
    /// laisse la place à ce qu'on sait déjà de la personne, et aux questions
    /// suivantes — c'est ce qui fait qu'une bibliothèque fournie raccourcit
    /// réellement le parcours au lieu d'être écrasée dès la première réponse.
    static func fromAmbiance(_ mood: Mood) -> [AxisObservation] {
        let anchor = mood.axisAnchor
        return [
            AxisObservation(.charge, anchor.charge, precision: 1.2),
            AxisObservation(.ton, anchor.ton, precision: 1.0),
            AxisObservation(.rythme, anchor.rythme, precision: 1.0),
            AxisObservation(.ancrage, anchor.ancrage, precision: 0.5),
            AxisObservation(.echelle, anchor.echelle, precision: 0.5),
        ]
    }

    // MARK: - Le cadre

    /// Le budget de la soirée. Une contrainte, donc l'indice le plus fort du
    /// parcours — et la raison pour laquelle la question de la durée ne sera
    /// jamais reposée ensuite.
    static func fromBudget(_ budget: RuntimePreference) -> [AxisObservation] {
        switch budget {
        case .short: [AxisObservation(.investissement, -0.85, precision: constraint)]
        case .medium: [AxisObservation(.investissement, 0, precision: constraint)]
        case .long: [AxisObservation(.investissement, 0.8, precision: constraint)]
        case .any: []
        }
    }

    /// Avec qui l'on regarde. Seule la présence d'enfants dit vraiment quelque
    /// chose des axes ; le reste est un filtre dur côté serveur, pas un goût.
    static func fromAudience(_ audience: Audience?) -> [AxisObservation] {
        guard audience == .family else { return [] }
        return [
            AxisObservation(.charge, -0.7, precision: constraint),
            AxisObservation(.densite, -0.5, precision: declared),
        ]
    }

    // MARK: - Les questions à puces

    /// Ce que chaque réponse possible d'une question déposerait, indexé par
    /// l'identifiant de l'option.
    ///
    /// Une seule table pour deux usages : traduire la réponse qui a été donnée, et
    /// simuler celles qui pourraient l'être — c'est cette seconde lecture qui permet
    /// au moteur d'estimer, avant de poser une question, de combien elle bougerait
    /// le trio. Les tenir séparées les ferait dériver l'une de l'autre.
    static func table(for dimension: AdaptiveDimension) -> [(id: String, observations: [AxisObservation])] {
        switch dimension {
        case .mindset:
            [
                (Mindset.noThinking.rawValue, [.init(.densite, -0.8, precision: declared),
                                               .init(.charge, -0.4, precision: declared)]),
                (Mindset.beSurprised.rawValue, [.init(.familiarite, 0.8, precision: declared)]),
                (Mindset.seeMyself.rawValue, [.init(.ancrage, -0.8, precision: declared),
                                              .init(.echelle, -0.5, precision: declared)]),
                (Mindset.learnSomething.rawValue, [.init(.densite, 0.8, precision: declared),
                                                   .init(.ancrage, -0.6, precision: declared)]),
            ]

        case .dealbreaker:
            // Un décrocheur dit ce qu'on ne veut pas : l'indice pointe donc à
            // l'opposé de ce qui est cité.
            [
                (Dealbreaker.slowPace.rawValue, [.init(.rythme, 0.7, precision: declared)]),
                (Dealbreaker.heavyMood.rawValue, [.init(.charge, -0.8, precision: declared)]),
                (Dealbreaker.tooLong.rawValue, [.init(.investissement, -0.8, precision: declared)]),
                (Dealbreaker.predictablePlot.rawValue, [.init(.familiarite, 0.6, precision: declared)]),
            ]

        case .popularity:
            [
                (PopularityPreference.mainstream.rawValue, [.init(.familiarite, -0.8, precision: declared)]),
                (PopularityPreference.wellRatedKnown.rawValue, [.init(.familiarite, -0.4, precision: declared)]),
                (PopularityPreference.hiddenGem.rawValue, [.init(.familiarite, 0.8, precision: declared)]),
                (PopularityPreference.any.rawValue, []),
            ]

        case .cast:
            [
                (CastPreference.familiarFaces.rawValue, [.init(.familiarite, -0.6, precision: declared)]),
                (CastPreference.discovery.rawValue, [.init(.familiarite, 0.6, precision: declared)]),
                (CastPreference.any.rawValue, []),
            ]

        case .cognitiveMode:
            [
                (CognitiveMode.understand.rawValue, [.init(.densite, 0.8, precision: declared),
                                                     .init(.ton, -0.3, precision: declared)]),
                (CognitiveMode.feel.rawValue, [.init(.densite, -0.4, precision: declared),
                                               .init(.ton, 0.6, precision: declared)]),
            ]

        case .horrorFlavor:
            [
                (HorrorFlavor.suspense.rawValue, [.init(.rythme, -0.3, precision: declared),
                                                  .init(.charge, 0.3, precision: declared)]),
                (HorrorFlavor.visceral.rawValue, [.init(.rythme, 0.6, precision: declared),
                                                  .init(.charge, 0.6, precision: declared)]),
            ]

        case .comedyFlavor:
            [
                (ComedyFlavor.family.rawValue, [.init(.ton, 0.8, precision: declared)]),
                (ComedyFlavor.edgy.rawValue, [.init(.ton, -0.6, precision: declared)]),
            ]

        case .dramaFlavor:
            [
                (DramaFlavor.social.rawValue, [.init(.echelle, 0.7, precision: declared)]),
                (DramaFlavor.intimate.rawValue, [.init(.echelle, -0.8, precision: declared)]),
            ]

        case .storyOrigin:
            // Le meilleur accès direct à l'ancrage — l'axe que le cadran laisse le
            // plus ouvert, faute de pouvoir le déduire d'un trajet d'humeur.
            [
                (StoryOrigin.trueStory.rawValue, [.init(.ancrage, -0.9, precision: declared),
                                                  .init(.charge, 0.3, precision: declared)]),
                (StoryOrigin.onlyInCinema.rawValue, [.init(.ancrage, 0.9, precision: declared)]),
            ]

        case .attachment:
            [
                (AttachmentMode.character.rawValue, [.init(.echelle, -0.8, precision: declared),
                                                     .init(.ancrage, -0.4, precision: declared)]),
                (AttachmentMode.world.rawValue, [.init(.echelle, 0.8, precision: declared),
                                                 .init(.ancrage, 0.6, precision: declared)]),
            ]

        case .creditsMoment:
            [
                (CreditsMoment.silence.rawValue, [.init(.charge, 0.8, precision: declared),
                                                  .init(.densite, 0.6, precision: declared)]),
                (CreditsMoment.discuss.rawValue, [.init(.densite, 0.7, precision: declared),
                                                  .init(.familiarite, 0.3, precision: declared)]),
                (CreditsMoment.contentment.rawValue, [.init(.charge, -0.6, precision: declared),
                                                      .init(.ton, 0.7, precision: declared)]),
                (CreditsMoment.keepGoing.rawValue, [.init(.familiarite, -0.8, precision: declared),
                                                    .init(.echelle, 0.6, precision: declared)]),
            ]

        case .lastingTrace:
            [
                (LastingTrace.weight.rawValue, [.init(.charge, 0.9, precision: declared),
                                                .init(.ton, -0.2, precision: declared)]),
                (LastingTrace.smile.rawValue, [.init(.ton, 0.9, precision: declared),
                                               .init(.charge, -0.4, precision: declared)]),
                (LastingTrace.questions.rawValue, [.init(.densite, 0.9, precision: declared),
                                                   .init(.familiarite, 0.4, precision: declared)]),
                (LastingTrace.wantMore.rawValue, [.init(.familiarite, -0.6, precision: declared),
                                                  .init(.echelle, 0.5, precision: declared)]),
            ]

        case .surpriseIntensity:
            // Un curseur n'a pas d'options : on échantillonne trois positions
            // représentatives pour pouvoir en simuler l'effet.
            [
                ("low", [.init(.familiarite, -0.7, precision: slider)]),
                ("mid", [.init(.familiarite, 0, precision: slider)]),
                ("high", [.init(.familiarite, 0.7, precision: slider)]),
            ]

        case .posterDuel, .elimination:
            // Portées par des affiches, pas par des puces : ce qu'elles déposent
            // dépend des films montrés — voir `fromDuel` et `fromElimination`.
            []
        }
    }

    /// Ce que dépose la réponse effectivement donnée.
    static func from(_ dimension: AdaptiveDimension, answers: QuestionnaireAnswers) -> [AxisObservation] {
        if dimension == .surpriseIntensity {
            return [.init(.familiarite, answers.surpriseIntensity * 2 - 1, precision: slider)]
        }
        guard let selected = selectedOptionID(dimension, answers) else { return [] }
        return table(for: dimension).first { $0.id == selected }?.observations ?? []
    }

    private static func selectedOptionID(
        _ dimension: AdaptiveDimension, _ answers: QuestionnaireAnswers
    ) -> String? {
        switch dimension {
        case .mindset: answers.mindset?.rawValue
        case .dealbreaker: answers.dealbreaker?.rawValue
        case .popularity: answers.popularity.rawValue
        case .cast: answers.cast.rawValue
        case .cognitiveMode: answers.cognitiveMode?.rawValue
        case .horrorFlavor: answers.horrorFlavor?.rawValue
        case .comedyFlavor: answers.comedyFlavor?.rawValue
        case .dramaFlavor: answers.dramaFlavor?.rawValue
        case .storyOrigin: answers.storyOrigin?.rawValue
        case .attachment: answers.attachment?.rawValue
        case .creditsMoment: answers.creditsMoment?.rawValue
        case .lastingTrace: answers.lastingTrace?.rawValue
        case .posterDuel, .elimination, .surpriseIntensity: nil
        }
    }

    // MARK: - Les affiches

    /// Ce qu'apprend un duel. L'information n'est pas dans le film choisi, elle est
    /// dans **l'écart** entre les deux : là où ils se ressemblent, le choix ne dit
    /// rien ; là où ils s'opposent, il tranche. C'est pour ça que le moteur
    /// construit la paire la plus contrastée qu'il trouve.
    static func fromDuel(winner: CandidateRow, loser: CandidateRow) -> [AxisObservation] {
        Axis.allCases.compactMap { axis in
            let gap = winner.axes[axis] - loser.axes[axis]
            guard abs(gap) > 0.25 else { return nil }
            return AxisObservation(axis, winner.axes[axis], precision: min(1, abs(gap)) * revealed)
        }
    }

    /// Ce qu'apprend un trio refusé en bloc (« Aucun des trois ne me tente »).
    ///
    /// Le refus est le signal d'erreur du système — celui qui manquait. Il n'a
    /// pas de rival contre qui mesurer un écart : on prend la position moyenne
    /// du trio, et on s'en éloigne sur les axes où il se situait franchement.
    /// La cible est atténuée (−0,4×), jamais une simple inversion : un trio
    /// neutre sur un axe ne doit produire aucun signal.
    static func fromRejectedTrio(_ rows: [CandidateRow]) -> [AxisObservation] {
        guard !rows.isEmpty else { return [] }
        return Axis.allCases.compactMap { axis in
            let mean = rows.reduce(0) { $0 + $1.axes[axis] } / Double(rows.count)
            guard abs(mean) > 0.25 else { return nil }
            return AxisObservation(axis, -0.4 * mean, precision: revealed)
        }
    }

    /// Ce qu'apprend une élimination : un rejet, donc un indice qui pointe à
    /// l'opposé du film écarté — et seulement sur ses axes saillants, là où il se
    /// distinguait vraiment des autres.
    static func fromElimination(loser: CandidateRow, others: [CandidateRow]) -> [AxisObservation] {
        guard !others.isEmpty else { return [] }
        return Axis.allCases.compactMap { axis in
            let rivalsMean = others.reduce(0) { $0 + $1.axes[axis] } / Double(others.count)
            let gap = loser.axes[axis] - rivalsMean
            guard abs(gap) > 0.25 else { return nil }
            // On s'éloigne du film écarté, sans aller au-delà du bord de l'axe.
            let target = max(-1, min(1, loser.axes[axis] - gap * 1.5))
            return AxisObservation(axis, target, precision: min(1, abs(gap)) * revealed)
        }
    }
}
