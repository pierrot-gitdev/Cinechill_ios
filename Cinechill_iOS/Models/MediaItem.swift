//
//  MediaItem.swift
//  Cinechill_iOS
//

import Foundation

nonisolated struct MediaItem: Identifiable, Hashable, Sendable {
    var id: String { "\(mediaType.rawValue)-\(tmdbId)" }

    let tmdbId: Int
    let mediaType: MediaType
    let title: String
    let posterPath: String?
    let overview: String?
    let voteAverage: Double?
    /// Le nombre de votes TMDB, quand la source le donne.
    ///
    /// Il ne sert pas à noter mais à **jauger la notoriété** : une note de 9
    /// portée par quarante personnes ne dit pas qu'un film est aimé, elle dit
    /// qu'il est confidentiel. Seules les listes TMDB le renseignent ; la
    /// galerie, la watchlist et le deck, qui décrivent des films déjà connus de
    /// la personne, le laissent à `nil`.
    let voteCount: Int?
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

}

extension MediaItem {
    nonisolated init(tmdbListRow: TMDBListResultRow, mediaType: MediaType) {
        self.tmdbId = tmdbListRow.id
        self.mediaType = mediaType
        self.title = (mediaType == .movie ? tmdbListRow.title : nil)
            ?? tmdbListRow.name
            ?? String(localized: "Sans titre", bundle: .app)
        self.posterPath = tmdbListRow.posterPath
        self.overview = tmdbListRow.overview
        self.voteAverage = tmdbListRow.voteAverage
        self.voteCount = tmdbListRow.voteCount
        self.genreIds = tmdbListRow.genreIds ?? []
        self.releaseDate = mediaType == .movie ? tmdbListRow.releaseDate : tmdbListRow.firstAirDate
    }
}
