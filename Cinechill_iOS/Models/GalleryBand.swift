//
//  GalleryBand.swift
//  Cinechill_iOS
//

import SwiftUI

/// Les quatre découpes de la collection. Une seule grammaire visuelle — des
/// bandes dont la taille encode le volume — quatre lectures.
enum GalleryAxis: String, CaseIterable, Identifiable {
    case era
    case genre
    case added
    case rating

    var id: String { rawValue }

    var label: String {
        switch self {
        case .era: String(localized: "Époque", bundle: .app)
        case .genre: String(localized: "Genre", bundle: .app)
        case .added: String(localized: "Ajouts", bundle: .app)
        case .rating: String(localized: "Note", bundle: .app)
        }
    }
}

/// Une strate de la collection : tous les films qui partagent une décennie, un
/// genre, un mois d'ajout ou une tranche de note.
struct GalleryBand: Identifiable, Hashable {
    let id: String
    let title: String
    /// Annotation courte, réservée à la bande dominante.
    let subtitle: String?
    let entries: [GalleryEntry]

    var count: Int { entries.count }
}

/// Une part de la barre de genres. `id` vaut `-1` pour l'agrégat « autres ».
///
/// `nonisolated` parce que le profil public la reçoit du réseau, hors
/// MainActor (voir le réglage `SWIFT_DEFAULT_ACTOR_ISOLATION` du projet) :
/// la galerie et le Hall dessinent la même barre, ils partagent donc le même
/// type plutôt que d'en entretenir deux.
nonisolated struct GenreShare: Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let share: Double
    let colorIndex: Int

    var color: Color { GalleryPalette.color(at: colorIndex) }

    var percentText: String {
        // Le signe pour cent ne se pose pas partout pareil — « 9 % » ici,
        // « 9% » ailleurs : c'est le format système qui le sait.
        share.formatted(.percent.precision(.fractionLength(0)))
    }
}

/// La carte d'identité de la collection, en tête d'écran.
struct GallerySignature: Hashable {
    let total: Int
    let addedThisMonth: Int
    let shares: [GenreShare]

    static let empty = GallerySignature(total: 0, addedThisMonth: 0, shares: [])
}

/// Palette de la barre de genres — les couleurs sont attribuées par ordre de
/// part décroissante, pour que le genre dominant porte toujours l'accent de
/// l'app et que la barre reste lisible quelle que soit la collection.
/// Cette palette s'ouvrait sur `.indigo` — l'accent de l'ancien système, qui
/// rentrait ainsi dans toute l'application **par la porte des données** : barre
/// d'ADN du profil, signature de galerie, profil public. Une couleur de données
/// ne doit jamais réimporter une couleur de chrome.
///
/// Elle est désormais dérivée de l'identité : le genre dominant porte la lumière
/// de la marque, les suivants descendent la famille étain puis empruntent aux
/// accents de rareté des badges — le seul autre système chromatique légitime de
/// l'app. Les valeurs restent franchement distinctes deux à deux, sans quoi la
/// barre cesse d'être lisible.
nonisolated enum GalleryPalette {
    private static let colors: [Color] = [
        Color(hex: 0x7FE3FF),   // la lumière — le genre dominant
        Color(hex: 0xBEE0F5),   // liseré
        Color(hex: 0x8D9AA8),   // étain
        Color(hex: 0xE0B24A),   // or des badges
        Color(hex: 0xA98CE8),   // améthyste des badges
    ]

    /// L'index hors palette est celui de l'agrégat « autres ».
    static func color(at index: Int) -> Color {
        guard index >= 0, index < colors.count else { return Color(hex: 0x3A434E) }
        return colors[index]
    }
}
