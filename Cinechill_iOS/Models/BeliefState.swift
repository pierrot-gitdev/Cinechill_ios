//
//  BeliefState.swift
//  Cinechill_iOS
//

import Foundation

/// Les huit axes de l'espace commun. La personne y a une croyance, le film une
/// position estimée — et la recommandation est une affaire de proximité entre
/// les deux.
nonisolated enum Axis: String, CaseIterable, Hashable, Sendable, Codable {
    /// Léger ↔ éprouvant.
    case charge = "ch"
    /// Contemplatif ↔ haletant.
    case rythme = "ry"
    /// Terrain connu ↔ inconnu.
    case familiarite = "fa"
    /// Limpide ↔ exigeant.
    case densite = "de"
    /// Réel ↔ imaginaire.
    case ancrage = "an"
    /// Distancié ↔ chaleureux.
    case ton = "to"
    /// Intime ↔ épique.
    case echelle = "ec"
    /// Peu ↔ beaucoup.
    case investissement = "in"

    /// Le nom qu'on montre. Ce sont les mots que quelqu'un emploierait en parlant
    /// d'un film à un ami — « Charge », « Densité », « Ancrage » ou
    /// « Investissement » décrivaient bien les axes mais ne se comprenaient qu'une
    /// fois le système expliqué, ce qui est l'inverse du contrat de cet écran.
    var label: String {
        switch self {
        case .charge: String(localized: "Émotions", bundle: .app)
        case .rythme: String(localized: "Rythme", bundle: .app)
        case .familiarite: String(localized: "Découverte", bundle: .app)
        case .densite: String(localized: "Complexité", bundle: .app)
        case .ancrage: String(localized: "Réalisme", bundle: .app)
        case .ton: String(localized: "Ton", bundle: .app)
        case .echelle: String(localized: "Ampleur", bundle: .app)
        case .investissement: String(localized: "Durée", bundle: .app)
        }
    }
}

/// Une observation déposée sur un axe : ce que l'indice suggère, et sa force.
///
/// La force est ce qui distingue une déclaration d'un comportement, ou une
/// question directe d'un indice glané au passage. Elle n'a pas d'unité — seul
/// son rapport aux autres compte.
nonisolated struct AxisObservation: Equatable, Hashable, Sendable {
    let axis: Axis
    /// La valeur suggérée, −1…+1.
    let target: Double
    /// La précision de l'indice. 1 vaut « une réponse directe et nette ».
    let precision: Double

    init(_ axis: Axis, _ target: Double, precision: Double = 1) {
        self.axis = axis
        self.target = min(1, max(-1, target))
        self.precision = max(0, precision)
    }
}

/// Ce qu'on croit savoir de quelqu'un, axe par axe : une moyenne et un doute.
///
/// Départ à μ = 0, σ = 1 — aucune idée. Chaque réponse déplace la moyenne et
/// resserre le doute, exactement, par la mise à jour bayésienne d'une gaussienne
/// de précision connue. Pas une approximation : trois lignes exactes.
nonisolated struct BeliefState: Equatable, Hashable, Sendable {
    /// Précision (1/σ²) par axe. C'est elle qu'on accumule, pas l'écart-type :
    /// les précisions s'additionnent, les écarts-types non.
    private(set) var mu: [Axis: Double]
    private(set) var tau: [Axis: Double]

    /// La précision d'un axe vierge. Ancre l'échelle : une observation de force 1
    /// sur un axe neuf déplace la moyenne à mi-chemin de sa cible.
    static let priorTau = 1.0

    init() {
        mu = Dictionary(uniqueKeysWithValues: Axis.allCases.map { ($0, 0.0) })
        tau = Dictionary(uniqueKeysWithValues: Axis.allCases.map { ($0, Self.priorTau) })
    }

    func mean(_ axis: Axis) -> Double { mu[axis] ?? 0 }
    func precision(_ axis: Axis) -> Double { tau[axis] ?? Self.priorTau }
    func sigma(_ axis: Axis) -> Double { 1 / max(0.0001, precision(axis)).squareRoot() }

    /// Le poids d'un axe dans le score : la preuve accumulée dessus, et rien
    /// d'autre. Un axe sur lequel la personne ne s'est jamais exprimée pèse zéro
    /// et ne départage rien — quelqu'un qui n'a parlé que de durée sera jugé sur
    /// la durée. C'est ce qui remplace les poids figés de l'ancienne formule.
    func weight(_ axis: Axis) -> Double {
        max(0, precision(axis) - Self.priorTau)
    }

    var hasAnyEvidence: Bool {
        Axis.allCases.contains { weight($0) > 0 }
    }

    // MARK: - Mise à jour

    mutating func observe(_ observation: AxisObservation) {
        guard observation.precision > 0 else { return }
        let axis = observation.axis
        let currentTau = precision(axis)
        let updatedTau = currentTau + observation.precision
        mu[axis] = (currentTau * mean(axis) + observation.precision * observation.target) / updatedTau
        tau[axis] = updatedTau
    }

    mutating func observe(_ observations: [AxisObservation]) {
        for observation in observations { observe(observation) }
    }

    func observing(_ observations: [AxisObservation]) -> BeliefState {
        var copy = self
        copy.observe(observations)
        return copy
    }

    // MARK: - Contrat réseau

    /// Ce que `finalizeRecommendations` reçoit. Le serveur ne recalcule jamais la
    /// croyance : il l'applique à des positions de films qu'il est, lui, seul à
    /// établir. Une source de vérité par moitié du calcul.
    var jsonPayload: [String: Any] {
        var mus: [String: Double] = [:]
        var sigmas: [String: Double] = [:]
        var weights: [String: Double] = [:]
        for axis in Axis.allCases {
            mus[axis.rawValue] = mean(axis)
            sigmas[axis.rawValue] = sigma(axis)
            weights[axis.rawValue] = weight(axis)
        }
        return ["mu": mus, "sigma": sigmas, "weight": weights]
    }
}
