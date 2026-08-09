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
        case dormant
    }

    let kind: Kind
    let items: [WatchlistItem]

    var id: String { kind.rawValue }

    var title: String {
        switch kind {
        case .recommended: String(localized: "RECOMMANDÉS PAR VOS AMIS", bundle: .app)
        case .available: String(localized: "DISPONIBLE CHEZ VOUS", bundle: .app)
        case .elsewhere: String(localized: "AILLEURS", bundle: .app)
        case .dormant: String(localized: "EN SOMMEIL · PLUS DE 3 MOIS", bundle: .app)
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
