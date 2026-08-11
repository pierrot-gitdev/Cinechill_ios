import Foundation

/// Qui a recommandé un film, conservé sur l'entrée de watchlist.
///
/// L'identifiant d'un document de watchlist est celui du film, pas d'un
/// événement : deux amis qui recommandent le même titre alimentent donc ce
/// tableau plutôt que de créer deux entrées. Un film recommandé trois fois
/// est un signal, pas un doublon.
struct Recommender: Hashable, Codable, Sendable {
    let uid: String
    let displayName: String
    let avatarURL: URL?
    let at: Date

    var initial: String {
        guard let first = displayName.first else { return "?" }
        return String(first).uppercased()
    }
}

struct WatchlistEntry: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let tmdbId: Int
    let mediaType: MediaType
    let title: String
    let posterPath: String?
    let overview: String?
    let voteAverage: Double?
    let genreIds: [Int]
    let releaseDate: String?
    let addedAt: Date
    /// Vide pour tout film ajouté par soi-même — c'est ce qui distingue la
    /// section « Recommandés par vos amis » du reste de la liste.
    let recommendedBy: [Recommender]

    init(
        id: String,
        tmdbId: Int,
        mediaType: MediaType,
        title: String,
        posterPath: String?,
        overview: String?,
        voteAverage: Double?,
        genreIds: [Int],
        releaseDate: String?,
        addedAt: Date,
        recommendedBy: [Recommender] = []
    ) {
        self.id = id
        self.tmdbId = tmdbId
        self.mediaType = mediaType
        self.title = title
        self.posterPath = posterPath
        self.overview = overview
        self.voteAverage = voteAverage
        self.genreIds = genreIds
        self.releaseDate = releaseDate
        self.addedAt = addedAt
        self.recommendedBy = recommendedBy
    }

    init(item: MediaItem, addedAt: Date = .now) {
        self.id = item.id
        self.tmdbId = item.tmdbId
        self.mediaType = item.mediaType
        self.title = item.title
        self.posterPath = item.posterPath
        self.overview = item.overview
        self.voteAverage = item.voteAverage
        self.genreIds = item.genreIds
        self.releaseDate = item.releaseDate
        self.addedAt = addedAt
        self.recommendedBy = []
    }

    var mediaItem: MediaItem {
        MediaItem(
            tmdbId: tmdbId,
            mediaType: mediaType,
            title: title,
            posterPath: posterPath,
            overview: overview,
            voteAverage: voteAverage,
            voteCount: nil,
            genreIds: genreIds,
            releaseDate: releaseDate
        )
    }

    var isRecommended: Bool { !recommendedBy.isEmpty }

    /// « Par Léa », « Par Sofiane et 1 autre ». Le premier nom est toujours
    /// cité : un visage et un nom portent l'information mieux qu'un compte.
    var recommendedByText: String? {
        guard let first = recommendedBy.first else { return nil }
        let others = recommendedBy.count - 1
        guard others > 0 else { return String(localized: "Par \(first.displayName)", bundle: .app) }
        return others == 1
            ? String(localized: "Par \(first.displayName) et \(others) autre", bundle: .app)
            : String(localized: "Par \(first.displayName) et \(others) autres", bundle: .app)
    }
}
