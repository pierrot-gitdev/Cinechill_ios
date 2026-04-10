//
//  MediaItem.swift
//  Cinechill_iOS
//

import Foundation

struct MediaItem: Identifiable, Hashable, Sendable {
    var id: String { "\(mediaType.rawValue)-\(tmdbId)" }

    let tmdbId: Int
    let mediaType: MediaType
    let title: String
    let posterPath: String?
    let overview: String?
    let voteAverage: Double?
    let genreIds: [Int]
    let releaseDate: String?

    var displayYear: String {
        guard let releaseDate, releaseDate.count >= 4 else { return "—" }
        return String(releaseDate.prefix(4))
    }

    var posterURL: URL? {
        guard let path = posterPath, !path.isEmpty else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w500\(path)")
    }

    var voteAverageText: String {
        guard let v = voteAverage else { return "N/A" }
        return String(format: "%.1f", v)
    }
}

extension MediaItem {
    init(tmdbListRow: TMDBListResultRow, mediaType: MediaType) {
        self.tmdbId = tmdbListRow.id
        self.mediaType = mediaType
        self.title = (mediaType == .movie ? tmdbListRow.title : nil)
            ?? tmdbListRow.name
            ?? "Sans titre"
        self.posterPath = tmdbListRow.posterPath
        self.overview = tmdbListRow.overview
        self.voteAverage = tmdbListRow.voteAverage
        self.genreIds = tmdbListRow.genreIds ?? []
        self.releaseDate = mediaType == .movie ? tmdbListRow.releaseDate : tmdbListRow.firstAirDate
    }
}
