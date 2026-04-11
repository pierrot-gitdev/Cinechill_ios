import Foundation

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
        addedAt: Date
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
    }

    var mediaItem: MediaItem {
        MediaItem(
            tmdbId: tmdbId,
            mediaType: mediaType,
            title: title,
            posterPath: posterPath,
            overview: overview,
            voteAverage: voteAverage,
            genreIds: genreIds,
            releaseDate: releaseDate
        )
    }
}

