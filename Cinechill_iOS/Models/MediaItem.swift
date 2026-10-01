//
//  MediaItem.swift
//  Cinechill_iOS
//

import Foundation

nonisolated struct MediaItem: Identifiable, Hashable, Sendable {
    /// L'identifiant de bibliothèque, qui est aussi celui du document Firestore.
    ///
    /// Une saison porte le sien : `tv-1399-s2`. **On range des saisons, jamais
    /// des séries** — une saison est un film, la série n'est qu'un dossier de
    /// saisons, comme une saga est un dossier de films. `tv-1399` seul désigne
    /// donc le dossier, et n'existe jamais en galerie ni en watchlist.
    var id: String {
        if let season { return "tv-\(tmdbId)-s\(season)" }
        return "\(mediaType.rawValue)-\(tmdbId)"
    }

    /// Pour une série, l'identifiant TMDB de la série — y compris quand l'objet
    /// désigne une de ses saisons.
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
    /// La saison désignée, pour une série. `nil` pour un film et pour le
    /// dossier d'une série.
    let season: Int?
    /// Le nombre de saisons sorties, quand la source le donne. Il remplace le
    /// mot « série » sur une affiche : l'information se lit, l'étiquette non.
    let seasonCount: Int?

    /// Explicite, et non synthétisé : les deux champs de série sont arrivés
    /// après les autres, et leur valeur par défaut garde intacts les endroits
    /// qui fabriquent un film.
    init(
        tmdbId: Int,
        mediaType: MediaType,
        title: String,
        posterPath: String?,
        overview: String?,
        voteAverage: Double?,
        voteCount: Int?,
        genreIds: [Int],
        releaseDate: String?,
        season: Int? = nil,
        seasonCount: Int? = nil
    ) {
        self.tmdbId = tmdbId
        self.mediaType = mediaType
        self.title = title
        self.posterPath = posterPath
        self.overview = overview
        self.voteAverage = voteAverage
        self.voteCount = voteCount
        self.genreIds = genreIds
        self.releaseDate = releaseDate
        self.season = season
        self.seasonCount = seasonCount
    }

    /// Le dossier d'une série : ni film, ni saison.
    var isSeries: Bool { mediaType == .tv && season == nil }

    /// Le dossier de la série à laquelle appartient cette saison.
    var seriesItem: MediaItem {
        MediaItem(
            tmdbId: tmdbId,
            mediaType: mediaType,
            title: title,
            posterPath: posterPath,
            overview: overview,
            voteAverage: voteAverage,
            voteCount: voteCount,
            genreIds: genreIds,
            releaseDate: releaseDate,
            seasonCount: seasonCount
        )
    }

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
        self.init(
            tmdbId: tmdbListRow.id,
            mediaType: mediaType,
            title: (mediaType == .movie ? tmdbListRow.title : nil)
                ?? tmdbListRow.name
                ?? String(localized: "Sans titre", bundle: .app),
            posterPath: tmdbListRow.posterPath,
            overview: tmdbListRow.overview,
            voteAverage: tmdbListRow.voteAverage,
            voteCount: tmdbListRow.voteCount,
            genreIds: tmdbListRow.genreIds ?? [],
            releaseDate: mediaType == .movie ? tmdbListRow.releaseDate : tmdbListRow.firstAirDate
        )
    }
}
