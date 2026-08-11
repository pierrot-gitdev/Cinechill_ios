//
//  SwipeCard.swift
//  Cinechill_iOS
//

import Foundation

/// Une carte du deck de swipe.
///
/// Superset de `MediaItem` sur un point : `source`, qui dit quelle stratégie de
/// recommandation a ramené le film.
///
/// `voteCount` était le second, du temps où `MediaItem` ne le portait pas. Il y
/// vit maintenant — le mur de l'entrée de CinéMatch s'en sert pour ne retenir
/// que des films que beaucoup de gens ont vus — et reste ici parce que c'est le
/// meilleur proxy de « combien de gens ont vraiment vu ce film », donc ce qui
/// permet au backend d'apprendre le niveau de « niche » de l'utilisateur au fil
/// des swipes.
nonisolated struct SwipeCard: Identifiable, Hashable, Sendable {
    let tmdbId: Int
    let title: String
    let posterPath: String?
    let overview: String?
    let voteAverage: Double?
    let voteCount: Int?
    let genreIds: [Int]
    let releaseDate: String?
    let source: String?

    var id: Int { tmdbId }

    var mediaItem: MediaItem {
        MediaItem(
            tmdbId: tmdbId,
            mediaType: .movie,
            title: title,
            posterPath: posterPath,
            overview: overview,
            voteAverage: voteAverage,
            voteCount: voteCount,
            genreIds: genreIds,
            releaseDate: releaseDate
        )
    }

    var posterURL: URL? {
        guard let posterPath, !posterPath.isEmpty else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w500\(posterPath)")
    }

    var displayYear: String {
        guard let releaseDate, releaseDate.count >= 4 else { return "—" }
        return String(releaseDate.prefix(4))
    }

    var voteAverageText: String {
        guard let voteAverage else { return "—" }
        return String(format: "%.1f", voteAverage)
    }

    /// Payload envoyé à `recordSwipes` — mêmes clés que `setMediaStatus`, plus
    /// `voteCount` que seul le swipe sait renseigner.
    var jsonPayload: [String: Any] {
        [
            "id": mediaItem.id,
            "tmdbId": tmdbId,
            "mediaType": MediaType.movie.rawValue,
            "title": title,
            "posterPath": posterPath as Any,
            "overview": overview as Any,
            "voteAverage": voteAverage as Any,
            "voteCount": voteCount as Any,
            "genreIds": genreIds,
            "releaseDate": releaseDate as Any,
        ]
    }
}

/// Le verdict porté sur une carte. `skipped` n'est pas un rejet de goût : il dit
/// « je ne l'ai pas vu », ce qui met le film en cooldown et apprend au backend
/// où l'utilisateur n'a pas de vécu.
nonisolated enum SwipeDecision: String, Sendable, Hashable {
    case seen
    case skipped
    case watchlist
}

/// Une décision en attente d'envoi, gardée telle quelle pour pouvoir être
/// rejouée si le réseau échoue.
nonisolated struct PendingSwipe: Sendable, Hashable {
    let card: SwipeCard
    let decision: SwipeDecision

    var jsonPayload: [String: Any] {
        ["decision": decision.rawValue, "item": card.jsonPayload]
    }
}
