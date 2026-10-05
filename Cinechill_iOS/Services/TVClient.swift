//
//  TVClient.swift
//  Cinechill_iOS
//

import Foundation

// MARK: - Les modèles

/// Une saison telle que la fiche d'une série la liste. Les spéciaux — la
/// saison 0 — n'y sont jamais : le serveur les retire.
nonisolated struct TVSeasonListing: Identifiable, Hashable, Sendable {
    let number: Int
    let name: String
    let episodeCount: Int
    let airDate: String?
    let posterPath: String?
    let voteAverage: Double?

    var id: Int { number }

    /// Sortie, ou au moins commencée. Une saison annoncée n'a qu'une issue :
    /// « À voir ».
    var isReleased: Bool {
        guard let airDate else { return false }
        return airDate <= TVDate.today
    }

    var year: String? {
        guard let airDate, airDate.count >= 4 else { return nil }
        return String(airDate.prefix(4))
    }
}

/// La fiche d'une série : le dossier de ses saisons.
nonisolated struct TVSeriesDetail: Sendable {
    let id: Int
    let name: String
    let overview: String?
    let tagline: String?
    let posterPath: String?
    let backdropPath: String?
    let voteAverage: Double?
    let voteCount: Int?
    let firstAirDate: String?
    let genreNames: [String]
    let genreIds: [Int]
    let creators: [String]
    let networks: [String]
    let episodeRunTime: Int?
    let seasons: [TVSeasonListing]
    let trailerKey: String?
    let cast: [TMDBDetailCastMember]
    let providers: [TMDBDetailWatchProviderItem]

    /// Le dossier, dans le vocabulaire de l'app.
    var item: MediaItem {
        MediaItem(
            tmdbId: id,
            mediaType: .tv,
            title: name,
            posterPath: posterPath,
            overview: overview,
            voteAverage: voteAverage,
            voteCount: voteCount,
            genreIds: genreIds,
            releaseDate: firstAirDate,
            seasonCount: seasons.filter(\.isReleased).count
        )
    }

    /// Une saison, prête à ranger. Le serveur complète tout le reste — épisodes,
    /// durée, plateformes — au moment de l'écriture.
    func item(for season: TVSeasonListing) -> MediaItem {
        MediaItem(
            tmdbId: id,
            mediaType: .tv,
            title: name,
            posterPath: season.posterPath ?? posterPath,
            overview: overview,
            voteAverage: season.voteAverage ?? voteAverage,
            voteCount: nil,
            genreIds: genreIds,
            releaseDate: season.airDate,
            season: season.number
        )
    }

    var backdropURL: URL? {
        guard let backdropPath, !backdropPath.isEmpty else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w780\(backdropPath)")
    }

    var trailerURL: URL? {
        guard let trailerKey, !trailerKey.isEmpty else { return nil }
        return URL(string: "https://www.youtube.com/watch?v=\(trailerKey)")
    }

    var trailerAppURL: URL? {
        guard let trailerKey, !trailerKey.isEmpty else { return nil }
        return URL(string: "youtube://www.youtube.com/watch?v=\(trailerKey)")
    }
}

/// Un épisode, tel que la fiche d'une saison le liste.
nonisolated struct TVEpisode: Identifiable, Hashable, Sendable {
    let number: Int
    let name: String
    let runtime: Int?
    let airDate: String?

    var id: Int { number }

    var isReleased: Bool {
        guard let airDate else { return false }
        return airDate <= TVDate.today
    }
}

/// La fiche d'une saison.
nonisolated struct TVSeasonDetail: Sendable {
    let tvId: Int
    let season: Int
    let name: String?
    let overview: String?
    let posterPath: String?
    let airDate: String?
    let voteAverage: Double?
    let episodes: [TVEpisode]
    let episodeRunTime: Int?
    let airedEpisodes: Int
    let nextAirDate: String?
}

/// Ce que la watchlist a besoin de savoir à jour d'une saison : une saison en
/// cours de diffusion change de semaine en semaine.
nonisolated struct SeasonEnrichment: Codable, Hashable, Sendable {
    let tvId: Int
    let season: Int
    let episodes: Int?
    let episodeRuntime: Int?
    let airedEpisodes: Int?
    let nextAirDate: String?
    let providerIds: [Int]
    let trailerKey: String?

    enum CodingKeys: String, CodingKey {
        case tvId = "tv_id"
        case season, episodes
        case episodeRuntime = "episode_runtime"
        case airedEpisodes = "aired_episodes"
        case nextAirDate = "next_air_date"
        case providerIds = "provider_ids"
        case trailerKey = "trailer_key"
    }
}

/// La date du jour au format de TMDB. Les dates de diffusion sont des chaînes
/// `YYYY-MM-DD`, et se comparent donc comme des chaînes.
nonisolated enum TVDate {
    static var today: String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    /// « le 3 oct. », à la manière de l'appareil.
    static func shortDay(_ iso: String) -> String? {
        let parser = DateFormatter()
        parser.calendar = Calendar(identifier: .gregorian)
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = .current
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: iso) else { return nil }
        return date.formatted(.dateTime.day().month(.abbreviated).locale(AppLanguage.current.locale))
    }
}

// MARK: - Le client

/// Ce que la watchlist attend pour tenir ses saisons à jour.
protocol SeasonEnriching: Sendable {
    func enrich(_ seasons: [(tvId: Int, season: Int)]) async throws -> [SeasonEnrichment]
}

/// Une seule erreur, comme pour la saga : une fiche qui ne vient pas se dit en
/// une phrase, et ce qu'il y a à faire ne dépend pas de la cause.
nonisolated enum TVClientError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        String(localized: "On n'a pas réussi à charger cette série.", bundle: .app)
    }
}

struct TVClient: Sendable {
    func series(id: Int) async throws -> TVSeriesDetail {
        let dto: TVSeriesDTO = try await get(APIEndpoints.tvDetails(id: id))
        return dto.model
    }

    func season(tvId: Int, season: Int) async throws -> TVSeasonDetail {
        let dto: TVSeasonDTO = try await get(APIEndpoints.tvSeason(id: tvId, season: season))
        return dto.model
    }

    private func get<T: Decodable>(_ url: URL?) async throws -> T {
        guard BackendConfiguration.baseURL != nil, let url else { throw TVClientError.unavailable }
        var request = await URLRequest(backend: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            if error is CancellationError { throw error }
            if let urlError = error as? URLError, urlError.code == .cancelled {
                throw CancellationError()
            }
            throw TVClientError.unavailable
        }
        guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode),
              let decoded = try? JSONDecoder().decode(T.self, from: data) else {
            throw TVClientError.unavailable
        }
        return decoded
    }
}

// MARK: - DTOs

private struct TVSeasonListingDTO: Decodable {
    let seasonNumber: Int
    let name: String?
    let episodeCount: Int?
    let airDate: String?
    let posterPath: String?
    let voteAverage: Double?

    enum CodingKeys: String, CodingKey {
        case name
        case seasonNumber = "season_number"
        case episodeCount = "episode_count"
        case airDate = "air_date"
        case posterPath = "poster_path"
        case voteAverage = "vote_average"
    }

    var model: TVSeasonListing {
        TVSeasonListing(
            number: seasonNumber,
            name: name ?? "",
            episodeCount: episodeCount ?? 0,
            airDate: airDate,
            posterPath: posterPath,
            voteAverage: voteAverage
        )
    }
}

private struct TVSeriesDTO: Decodable {
    let id: Int
    let name: String?
    let overview: String?
    let tagline: String?
    let posterPath: String?
    let backdropPath: String?
    let voteAverage: Double?
    let voteCount: Int?
    let firstAirDate: String?
    let genreNames: [String]?
    let genreIds: [Int]?
    let creators: [String]?
    let networks: [String]?
    let episodeRunTime: Int?
    let seasons: [TVSeasonListingDTO]?
    let trailerKey: String?
    let credits: TMDBDetailCredits?
    let watchProvidersFR: [TMDBDetailWatchProviderItem]?

    enum CodingKeys: String, CodingKey {
        case id, name, overview, tagline, creators, networks, seasons, credits
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case voteAverage = "vote_average"
        case voteCount = "vote_count"
        case firstAirDate = "first_air_date"
        case genreNames = "genre_names"
        case genreIds = "genre_ids"
        case episodeRunTime = "episode_run_time"
        case trailerKey = "trailer_key"
        case watchProvidersFR = "watch_providers_fr"
    }

    var model: TVSeriesDetail {
        TVSeriesDetail(
            id: id,
            name: name ?? String(localized: "Sans titre", bundle: .app),
            overview: overview,
            tagline: tagline,
            posterPath: posterPath,
            backdropPath: backdropPath,
            voteAverage: voteAverage,
            voteCount: voteCount,
            firstAirDate: firstAirDate,
            genreNames: genreNames ?? [],
            genreIds: genreIds ?? [],
            creators: creators ?? [],
            networks: networks ?? [],
            episodeRunTime: episodeRunTime,
            seasons: (seasons ?? []).map(\.model),
            trailerKey: trailerKey,
            cast: credits?.cast ?? [],
            providers: watchProvidersFR ?? []
        )
    }
}

private struct TVEpisodeDTO: Decodable {
    let episodeNumber: Int?
    let name: String?
    let runtime: Int?
    let airDate: String?

    enum CodingKeys: String, CodingKey {
        case name, runtime
        case episodeNumber = "episode_number"
        case airDate = "air_date"
    }
}

private struct TVSeasonDTO: Decodable {
    let tvId: Int
    let seasonNumber: Int
    let name: String?
    let overview: String?
    let posterPath: String?
    let airDate: String?
    let voteAverage: Double?
    let episodes: [TVEpisodeDTO]?
    let episodeRunTime: Int?
    let airedEpisodes: Int?
    let nextAirDate: String?

    enum CodingKeys: String, CodingKey {
        case name, overview, episodes
        case tvId = "tv_id"
        case seasonNumber = "season_number"
        case posterPath = "poster_path"
        case airDate = "air_date"
        case voteAverage = "vote_average"
        case episodeRunTime = "episode_run_time"
        case airedEpisodes = "aired_episodes"
        case nextAirDate = "next_air_date"
    }

    var model: TVSeasonDetail {
        TVSeasonDetail(
            tvId: tvId,
            season: seasonNumber,
            name: name,
            overview: overview,
            posterPath: posterPath,
            airDate: airDate,
            voteAverage: voteAverage,
            episodes: (episodes ?? []).enumerated().map { index, episode in
                TVEpisode(
                    number: episode.episodeNumber ?? index + 1,
                    name: episode.name ?? "",
                    runtime: episode.runtime,
                    airDate: episode.airDate
                )
            },
            episodeRunTime: episodeRunTime,
            airedEpisodes: airedEpisodes ?? 0,
            nextAirDate: nextAirDate
        )
    }
}
