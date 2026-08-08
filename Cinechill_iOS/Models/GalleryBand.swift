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
        case .era: "Époque"
        case .genre: "Genre"
        case .added: "Ajouts"
        case .rating: "Note"
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
        "\(Int((share * 100).rounded())) %"
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
nonisolated enum GalleryPalette {
    private static let colors: [Color] = [
        .indigo,
        Color(red: 0.93, green: 0.28, blue: 0.60),
        Color(red: 0.06, green: 0.61, blue: 0.56),
        Color(red: 0.76, green: 0.51, blue: 0.23),
        Color(red: 0.49, green: 0.36, blue: 0.84),
    ]

    /// L'index hors palette est celui de l'agrégat « autres ».
    static func color(at index: Int) -> Color {
        guard index >= 0, index < colors.count else { return Color(.systemGray3) }
        return colors[index]
    }
}
