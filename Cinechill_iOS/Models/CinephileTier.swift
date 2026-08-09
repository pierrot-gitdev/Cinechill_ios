//
//  CinephileTier.swift
//  Cinechill_iOS
//

import SwiftUI

/// Le palier de progression, lu sur la taille de la galerie.
///
/// Les seuils sont calibrés sur le fait que le deck enregistre *une vie de
/// spectateur* et non les films de l'année : quelques sessions suffisent à
/// passer 300, d'où un dernier palier volontairement lointain.
nonisolated enum CinephileTier: Int, CaseIterable, Sendable {
    case bronze
    case silver
    case gold
    case platinum
    case icon

    static func tier(for count: Int) -> CinephileTier {
        switch count {
        case ..<50: .bronze
        case ..<150: .silver
        case ..<400: .gold
        case ..<900: .platinum
        default: .icon
        }
    }

    var label: String {
        switch self {
        case .bronze: String(localized: "BRONZE", bundle: .app)
        case .silver: String(localized: "ARGENT", bundle: .app)
        case .gold: String(localized: "OR", bundle: .app)
        case .platinum: String(localized: "PLATINE", bundle: .app)
        case .icon: String(localized: "ICÔNE", bundle: .app)
        }
    }

    var lowerBound: Int {
        switch self {
        case .bronze: 0
        case .silver: 50
        case .gold: 150
        case .platinum: 400
        case .icon: 900
        }
    }

    /// Nombre de films du palier suivant, ou `nil` au sommet.
    var nextThreshold: Int? {
        switch self {
        case .bronze: 50
        case .silver: 150
        case .gold: 400
        case .platinum: 900
        case .icon: nil
        }
    }

    /// La teinte du liseré de la carte. Volontairement discrète : c'est le
    /// badge qui porte la couleur, pas le palier.
    var accent: Color {
        switch self {
        case .bronze: Color(hex: 0xA97C52)
        case .silver: Color(hex: 0xB8C2D0)
        case .gold: Color(hex: 0xE0B24A)
        case .platinum: Color(hex: 0xA98CE8)
        case .icon: Color(hex: 0x5EE0C0)
        }
    }

    func progress(count: Int) -> Double {
        guard let next = nextThreshold else { return 1 }
        let span = Double(next - lowerBound)
        guard span > 0 else { return 1 }
        return min(1, max(0, Double(count - lowerBound) / span))
    }

    func remainingText(count: Int) -> String? {
        guard let next = nextThreshold else { return nil }
        let missing = max(0, next - count)
        let nextTier = CinephileTier(rawValue: rawValue + 1)?.label.capitalized ?? ""
        return missing == 1
            ? String(localized: "\(nextTier) dans \(missing) film", bundle: .app)
            : String(localized: "\(nextTier) dans \(missing) films", bundle: .app)
    }
}

nonisolated extension Color {
    init(hex: UInt) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
