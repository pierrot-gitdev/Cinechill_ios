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
        case .short: "1 h 30"
        case .medium: "2 h"
        case .any: "Peu importe"
        }
    }
}

/// Une entrée de watchlist, complétée par ce que seul `enrichCandidates` sait :
/// durée, plateformes, bande-annonce.
struct WatchlistItem: Identifiable, Hashable {
    let entry: WatchlistEntry
    let runtimeMinutes: Int?
    let providerIDs: [Int]
    let trailerKey: String?

    var id: Int { entry.tmdbId }

    func isAvailable(on preferred: Set<Int>) -> Bool {
        guard !preferred.isEmpty else { return false }
        return providerIDs.contains { preferred.contains($0) }
    }

    var runtimeText: String? {
        guard let runtimeMinutes, runtimeMinutes > 0 else { return nil }
        let hours = runtimeMinutes / 60
        let minutes = runtimeMinutes % 60
        return hours > 0 ? "\(hours) h \(String(format: "%02d", minutes))" : "\(minutes) min"
    }

    var trailerURL: URL? {
        guard let trailerKey, !trailerKey.isEmpty else { return nil }
        return URL(string: "https://www.youtube.com/watch?v=\(trailerKey)")
    }
}

/// Les trois groupes de la file. L'ordre n'est pas chronologique mais
/// actionnable : ce qu'on peut lancer maintenant d'abord, ce qui pourrit
/// en dernier.
struct WatchlistGroup: Identifiable, Hashable {
    enum Kind: String {
        case available
        case elsewhere
        case dormant
    }

    let kind: Kind
    let items: [WatchlistItem]

    var id: String { kind.rawValue }

    var title: String {
        switch kind {
        case .available: "DISPONIBLE CHEZ VOUS"
        case .elsewhere: "AILLEURS"
        case .dormant: "EN SOMMEIL · PLUS DE 3 MOIS"
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
