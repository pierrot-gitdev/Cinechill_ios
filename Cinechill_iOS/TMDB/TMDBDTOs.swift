//
//  TMDBDTOs.swift
//  Cinechill_iOS
//

import Foundation

struct TMDBListResultRow: Decodable, Sendable {
    let id: Int
    let posterPath: String?
    let overview: String?
    let voteAverage: Double?
    let genreIds: [Int]?
    let title: String?
    let name: String?
    let releaseDate: String?
    let firstAirDate: String?

    enum CodingKeys: String, CodingKey {
        case id
        case posterPath = "poster_path"
        case overview
        case voteAverage = "vote_average"
        case genreIds = "genre_ids"
        case title
        case name
        case releaseDate = "release_date"
        case firstAirDate = "first_air_date"
    }
}

struct TMDBPagedResults: Decodable, Sendable {
    let page: Int
    let results: [TMDBListResultRow]
    let totalPages: Int?
    let totalResults: Int?

    enum CodingKeys: String, CodingKey {
        case page
        case results
        case totalPages = "total_pages"
        case totalResults = "total_results"
    }
}

struct TMDBGenre: Decodable, Sendable {
    let id: Int
    let name: String
}

struct TMDBGenresResponse: Decodable, Sendable {
    let genres: [TMDBGenre]
}

struct TMDBWatchProvider: Decodable, Sendable {
    let providerID: Int
    let providerName: String
    let logoPath: String?
    let displayPriority: Int?

    enum CodingKeys: String, CodingKey {
        case providerID = "provider_id"
        case providerName = "provider_name"
        case logoPath = "logo_path"
        case displayPriority = "display_priority"
    }
}

struct TMDBWatchProvidersResponse: Decodable, Sendable {
    let results: [TMDBWatchProvider]
}

// MARK: - Detail

struct TMDBDetailCastMember: Decodable, Sendable {
    let name: String
    let character: String?
    let profilePath: String?

    enum CodingKeys: String, CodingKey {
        case name
        case character
        case profilePath = "profile_path"
    }

    var profileURL: URL? {
        guard let path = profilePath, !path.isEmpty else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w185\(path)")
    }
}

struct TMDBDetailCredits: Decodable, Sendable {
    let cast: [TMDBDetailCastMember]?
}

struct TMDBDetailWatchProviderItem: Decodable, Sendable {
    let providerID: Int
    let providerName: String
    let logoPath: String?

    enum CodingKeys: String, CodingKey {
        case providerID = "provider_id"
        case providerName = "provider_name"
        case logoPath = "logo_path"
    }

    var logoURL: URL? {
        guard let path = logoPath, !path.isEmpty else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w92\(path)")
    }

    var webURL: URL? {
        Self.webURL(forProviderID: providerID)
    }

    /// Page web du service pour un `provider_id` TMDB donné. Extrait en fonction statique pour
    /// être réutilisable sans instance (ex. `RecommendationResult`, qui ne connaît que des IDs).
    nonisolated static func webURL(forProviderID providerID: Int) -> URL? {
        let map: [Int: String] = [
            8: "https://www.netflix.com",
            119: "https://www.primevideo.com",
            9: "https://www.primevideo.com",
            337: "https://www.disneyplus.com",
            350: "https://tv.apple.com",
            381: "https://www.canalplus.com",
            1932: "https://www.canalplus.com",
            1899: "https://www.max.com",
            384: "https://www.max.com",
            531: "https://www.paramountplus.com/fr",
            234: "https://www.arte.tv/fr",
            1100: "https://www.tf1plus.fr",
            444: "https://www.molotov.tv"
        ]
        guard let urlString = map[providerID] else { return nil }
        return URL(string: urlString)
    }
}

struct TMDBDetailResponse: Decodable, Sendable {
    let id: Int
    let title: String?
    let name: String?
    let overview: String?
    let tagline: String?
    let posterPath: String?
    let backdropPath: String?
    let voteAverage: Double?
    let voteCount: Int?
    let runtime: Int?
    let releaseDate: String?
    let firstAirDate: String?
    let director: String?
    let trailerKey: String?
    let genreNames: [String]?
    /// La saga et son nombre d'épisodes — alimentent le badge « L'Intégrale ».
    let collectionID: Int?
    let collectionCount: Int?
    let credits: TMDBDetailCredits?
    let watchProvidersFR: [TMDBDetailWatchProviderItem]?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case name
        case overview
        case tagline
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case voteAverage = "vote_average"
        case voteCount = "vote_count"
        case runtime
        case releaseDate = "release_date"
        case firstAirDate = "first_air_date"
        case director
        case trailerKey = "trailer_key"
        case genreNames = "genre_names"
        case collectionID = "collection_id"
        case collectionCount = "collection_count"
        case credits
        case watchProvidersFR = "watch_providers_fr"
    }

    func asMediaItem(mediaType: MediaType) -> MediaItem {
        let t = (mediaType == .movie ? title : nil) ?? name ?? "Sans titre"
        let date = mediaType == .movie ? releaseDate : firstAirDate
        return MediaItem(
            tmdbId: id,
            mediaType: mediaType,
            title: t,
            posterPath: posterPath,
            overview: overview,
            voteAverage: voteAverage,
            genreIds: [],
            releaseDate: date
        )
    }

    var displayTitle: String {
        (title ?? name) ?? "Sans titre"
    }

    var posterDetailURL: URL? {
        guard let path = posterPath, !path.isEmpty else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w500\(path)")
    }

    var trailerURL: URL? {
        guard let key = trailerKey, !key.isEmpty else { return nil }
        return URL(string: "https://www.youtube.com/watch?v=\(key)")
    }

    var trailerAppURL: URL? {
        guard let key = trailerKey, !key.isEmpty else { return nil }
        return URL(string: "youtube://www.youtube.com/watch?v=\(key)")
    }

    var displayYear: String {
        let date = releaseDate ?? firstAirDate ?? ""
        return String(date.prefix(4))
    }

    var firstGenre: String? {
        genreNames?.first
    }

    var backdropURL: URL? {
        guard let path = backdropPath, !path.isEmpty else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w780\(path)")
    }

    var runtimeText: String? {
        guard let runtime, runtime > 0 else { return nil }
        let hours = runtime / 60
        let minutes = runtime % 60
        return hours > 0 ? "\(hours) h \(String(format: "%02d", minutes))" : "\(minutes) min"
    }
}
