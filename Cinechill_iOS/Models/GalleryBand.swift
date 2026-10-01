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

    /// Les saisons comptent une par une : le volume d'une bande est celui de
    /// ce qu'on a regardé, et trois saisons de Dark pèsent trois fois.
    var count: Int { entries.count }

    /// Ce que la frise affiche. Les saisons d'une même série qui partagent la
    /// bande se fondent en une tuile, à la place de la première : le volume
    /// reste vrai, et l'affiche n'est jamais répétée.
    var tiles: [GalleryTile] {
        var tiles: [GalleryTile] = []
        var seriesIndex: [Int: Int] = [:]
        for entry in entries {
            guard entry.isSeason else {
                tiles.append(.film(entry))
                continue
            }
            if let index = seriesIndex[entry.tmdbId], case .series(let seasons) = tiles[index] {
                tiles[index] = .series(seasons + [entry])
            } else {
                seriesIndex[entry.tmdbId] = tiles.count
                tiles.append(.series([entry]))
            }
        }
        return tiles
    }
}

/// Une tuile de la frise : un film, ou une série et celles de ses saisons qui
/// tombent dans la bande.
enum GalleryTile: Identifiable, Hashable {
    case film(GalleryEntry)
    case series([GalleryEntry])

    var id: String {
        switch self {
        case .film(let entry): entry.id
        case .series(let seasons): "series-\(seasons.first?.tmdbId ?? 0)"
        }
    }

    var title: String {
        switch self {
        case .film(let entry): entry.title
        case .series(let seasons): seasons.first?.title ?? ""
        }
    }

    /// L'affiche de la série plutôt que celle d'une saison : la tuile est la
    /// série. Une saison seule garde la sienne.
    var posterPath: String? {
        switch self {
        case .film(let entry):
            return entry.posterPath
        case .series(let seasons):
            guard let first = seasons.first else { return nil }
            if seasons.count == 1 { return first.posterPath }
            return first.seasonFacts?.seriesPosterPath ?? first.posterPath
        }
    }

    /// La plaque d'une tuile de série : « Saison 2 » pour une saison seule,
    /// « 3 saisons » au-delà. Jamais « série » : le compte le dit.
    var plate: String? {
        guard case .series(let seasons) = self else { return nil }
        if seasons.count == 1, let number = seasons.first?.seasonFacts?.season {
            return String(localized: "Saison \(number)", bundle: .app)
        }
        return String(localized: "\(seasons.count) saisons", bundle: .app)
    }

    /// Ce qu'ouvre un tap : la fiche du film, la fiche de la saison seule, ou
    /// le dossier de la série quand plusieurs saisons se sont fondues.
    var destination: MediaItem? {
        switch self {
        case .film(let entry):
            return entry.mediaItem
        case .series(let seasons):
            guard let first = seasons.first else { return nil }
            return seasons.count == 1 ? first.mediaItem : first.mediaItem.seriesItem
        }
    }
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
    var films: Int = 0
    var seasons: Int = 0
    /// Séries distinctes : trois saisons de Dark font une série.
    var series: Int = 0

    static let empty = GallerySignature(total: 0, addedThisMonth: 0, shares: [])

    /// La signature ne change pas pour qui n'a vu que des films.
    var hasSeasons: Bool { seasons > 0 }
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
        Color(hex: 0xBCB7A4),   // étain
        Color(hex: 0xE0B24A),   // or des badges
        Color(hex: 0xA98CE8),   // améthyste des badges
    ]

    /// L'index hors palette est celui de l'agrégat « autres ».
    static func color(at index: Int) -> Color {
        guard index >= 0, index < colors.count else { return Color(hex: 0x4A4639) }
        return colors[index]
    }
}
