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

// MARK: - Detail

struct TMDBDetailCastMember: Decodable, Sendable {
    let name: String
}

struct TMDBDetailCredits: Decodable, Sendable {
    let cast: [TMDBDetailCastMember]?
}

struct TMDBDetailResponse: Decodable, Sendable {
    let id: Int
    let title: String?
    let name: String?
    let overview: String?
    let posterPath: String?
    let backdropPath: String?
    let voteAverage: Double?
    let releaseDate: String?
    let firstAirDate: String?
    let credits: TMDBDetailCredits?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case name
        case overview
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case voteAverage = "vote_average"
        case releaseDate = "release_date"
        case firstAirDate = "first_air_date"
        case credits
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

    var backdropURL: URL? {
        guard let path = backdropPath, !path.isEmpty else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w780\(path)")
    }

    var posterDetailURL: URL? {
        guard let path = posterPath, !path.isEmpty else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w500\(path)")
    }

    var castLine: String {
        let names = (credits?.cast ?? []).prefix(8).map(\.name)
        return names.joined(separator: ", ")
    }
}
