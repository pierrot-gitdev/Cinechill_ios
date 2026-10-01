//
//  WatchlistPlan.swift
//  Cinechill_iOS
//

import Foundation

/// Le temps qu'on a devant soi — la première question qu'on se pose vraiment
/// devant sa watchlist, et celle qui élimine le plus de candidats.
enum TimeBudget: String, CaseIterable, Identifiable {
    case short
    case medium
    case any

    var id: String { rawValue }

    /// Cinq minutes de tolérance : un film d'1 h 34 rentre dans « 1 h 30 »,
    /// l'exclure serait absurde.
    var maxMinutes: Int? {
        switch self {
        case .short: 95
        case .medium: 125
        case .any: nil
        }
    }

    var label: String {
        switch self {
        case .short: String(localized: "1 h 30", bundle: .app)
        case .medium: String(localized: "2 h", bundle: .app)
        case .any: String(localized: "Peu importe", bundle: .app)
        }
    }
}

/// Une entrée de watchlist, complétée par ce que seul `enrichCandidates` sait :
/// durée, plateformes, bande-annonce.
struct WatchlistItem: Identifiable, Hashable {
    let entry: WatchlistEntry
    /// La durée d'un film, ou celle d'un épisode pour une saison : c'est le
    /// temps d'une soirée, et c'est lui que le budget compare.
    let runtimeMinutes: Int?
    let providerIDs: [Int]
    let trailerKey: String?
    /// Épisodes sortis, à jour — une saison en cours de diffusion change de
    /// semaine en semaine. `nil` pour un film.
    var airedEpisodes: Int? = nil
    /// Date du prochain épisode à sortir, pour une saison qui l'attend.
    var nextAirDate: String? = nil

    /// L'identité de bibliothèque, et non `tmdbId` : deux saisons d'une même
    /// série partagent leur `tmdbId`, et une série peut porter celui d'un film.
    var id: String { entry.id }

    /// L'épisode à lancer n'est pas encore sorti : la ligne ne se lance pas ce
    /// soir, quoi que dise sa plateforme.
    var isAwaitingEpisode: Bool {
        guard entry.isSeason, let airedEpisodes else { return false }
        return entry.episodeToPlay > airedEpisodes
    }

    func isAvailable(on preferred: Set<Int>) -> Bool {
        guard !preferred.isEmpty else { return false }
        return providerIDs.contains { preferred.contains($0) }
    }

    var runtimeText: String? {
        guard let runtimeMinutes, runtimeMinutes > 0 else { return nil }
        let hours = runtimeMinutes / 60
        let minutes = runtimeMinutes % 60
        return hours > 0
            ? String(localized: "\(hours) h \(String(format: "%02d", minutes))", bundle: .app)
            : String(localized: "\(minutes) min", bundle: .app)
    }

    var trailerURL: URL? {
        guard let trailerKey, !trailerKey.isEmpty else { return nil }
        return URL(string: "https://www.youtube.com/watch?v=\(trailerKey)")
    }
}

/// Les groupes de la file. L'ordre n'est pas chronologique mais actionnable :
/// ce qui vient d'un ami d'abord, ce qu'on peut lancer maintenant ensuite, ce
/// qui pourrit en dernier.
///
/// `recommended` est un **statut temporaire, pas une catégorie** : la
/// provenance et la disponibilité sont deux axes différents, et les mélanger
/// durablement casserait le groupement. Un film recommandé quitte ce groupe
/// dès qu'il est vu — la provenance, elle, reste attachée à l'entrée.
struct WatchlistGroup: Identifiable, Hashable {
    enum Kind: String {
        case recommended
        case available
        case elsewhere
        /// Une saison dont l'épisode à lancer n'est pas sorti. Ce n'est pas un
        /// état de la saison mais une disponibilité, au même titre que « sur
        /// d'autres plateformes » : on ne peut pas la lancer ce soir.
        case awaiting
        case dormant
    }

    let kind: Kind
    let items: [WatchlistItem]

    var id: String { kind.rawValue }

    var title: String {
        switch kind {
        case .recommended: String(localized: "RECOMMANDÉS PAR TES AMIS", bundle: .app)
        case .available: String(localized: "SUR TES PLATEFORMES", bundle: .app)
        case .elsewhere: String(localized: "SUR D'AUTRES PLATEFORMES", bundle: .app)
        case .awaiting: String(localized: "L'ÉPISODE N'EST PAS SORTI", bundle: .app)
        case .dormant: String(localized: "AJOUTÉS IL Y A PLUS DE 3 MOIS", bundle: .app)
        }
    }
}

/// La proposition du soir, et la raison de ce choix — écrite noir sur blanc,
/// parce qu'une suggestion sans justification ne se distingue pas d'un tirage
/// au sort.
struct TonightPick: Hashable {
    let item: WatchlistItem
    let reason: String
}
