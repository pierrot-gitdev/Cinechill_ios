//
//  TasteProfile.swift
//  Cinechill_iOS
//

import Foundation

/// Le trait : ce que la bibliothèque raconte, indépendamment de ce soir.
///
/// Deux objets de natures différentes cohabitent dans le système. L'**état** — où
/// vous en êtes ce soir — se remet à zéro à chaque séance. Le **trait** s'accumule
/// d'une séance à l'autre et sert de point de départ. L'articulation n'est pas une
/// moyenne : l'état module le trait, il ne s'y ajoute pas.
///
/// Il n'est jamais requis. À zéro film, tous les axes sont plats et la séance
/// fonctionne intégralement au questionnaire — c'est un accélérateur, pas une
/// condition.
/// Ce qu'un film a laissé, une fois regardé.
///
/// Trois réponses, pas dix étoiles : une échelle fine ne se remplit pas, et ce
/// qu'on veut savoir tient de toute façon en trois cas. C'est le seul signal du
/// système qui porte sur l'expérience vécue, et c'est lui qui calibrera un jour
/// tous les coefficients posés à la main jusqu'ici.
nonisolated enum FilmVerdict: String, CaseIterable, Sendable {
    case stayed, passed, unfinished

    var label: String {
        switch self {
        case .stayed: String(localized: "Je l'ai adoré", bundle: .app)
        case .passed: String(localized: "C'était bien, sans plus", bundle: .app)
        case .unfinished: String(localized: "Je ne l'ai pas fini", bundle: .app)
        }
    }
}

nonisolated struct PendingVerdict: Equatable, Sendable {
    let tmdbID: Int
    let title: String?
}

nonisolated struct TasteProfile: Equatable, Sendable {
    var mu: [Axis: Double]
    var tau: [Axis: Double]
    var galleryCount: Int
    var watchlistCount: Int
    /// Les axes que la personne a corrigés elle-même sur la Fiche.
    var correctedAxes: Set<Axis>
    /// Combien de films ont déjà rendu leur verdict.
    var verdictCount: Int = 0
    /// Un film lancé dont on ne sait pas encore ce qu'il a donné.
    var pendingVerdict: PendingVerdict?

    static let empty = TasteProfile(
        mu: [:], tau: [:], galleryCount: 0, watchlistCount: 0, correctedAxes: []
    )

    func mean(_ axis: Axis) -> Double { mu[axis] ?? 0 }
    func precision(_ axis: Axis) -> Double { max(BeliefState.priorTau, tau[axis] ?? BeliefState.priorTau) }
    func sigma(_ axis: Axis) -> Double { 1 / precision(axis).squareRoot() }

    /// La preuve accumulée sur un axe, au-delà du prior. Zéro = on ne sait rien.
    func evidence(_ axis: Axis) -> Double { precision(axis) - BeliefState.priorTau }

    var isEmpty: Bool { galleryCount == 0 && watchlistCount == 0 && correctedAxes.isEmpty }

    /// Combien d'axes le trait éclaire déjà. C'est ce nombre, et non le compte de
    /// films, qui détermine la longueur d'une séance — d'où les « régimes » qui
    /// émergent sans être codés nulle part.
    var establishedAxisCount: Int {
        Axis.allCases.filter { evidence($0) > 0.5 }.count
    }
}

nonisolated extension BeliefState {
    /// Ouvre une croyance de séance sur ce que l'on savait déjà.
    ///
    /// La moyenne est reprise telle quelle, mais l'incertitude est **élargie** d'un
    /// facteur : le trait dit l'habitude, et ce soir a le droit de la contredire.
    /// Sans cet élargissement, quelques dizaines de films vus rendraient la croyance
    /// si rigide qu'aucune réponse ne pourrait plus la déplacer — le questionnaire
    /// deviendrait décoratif.
    /// Le facteur d'élargissement. Attention à ne pas le lire comme une petite
    /// concession : l'écart-type entre au carré dans la précision, donc 1,25 rend
    /// déjà plus de la moitié de la preuve accumulée. Au-delà (1,4 était la valeur
    /// d'origine), le trait ne pesait plus rien face aux réponses de la soirée et
    /// une galerie fournie ne raccourcissait aucune séance.
    static let priorWidening = 1.25

    init(prior: TasteProfile) {
        self.init()
        for axis in Axis.allCases {
            let widened = min(1, prior.sigma(axis) * Self.priorWidening)
            // σ = 1 est le prior vierge : inutile d'observer quoi que ce soit.
            guard widened < 1 else { continue }
            let targetTau = 1 / (widened * widened)
            observe(AxisObservation(
                axis, prior.mean(axis), precision: targetTau - Self.priorTau
            ))
        }
    }
}
