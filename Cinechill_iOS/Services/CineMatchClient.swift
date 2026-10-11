//
//  CineMatchClient.swift
//  Cinechill_iOS
//

import Foundation
import FirebaseAuth

/// Les erreurs propres à CinéMatch. Le reste passe par
/// `RecommendationClientError`, dont les messages valent aussi ici.
nonisolated enum CineMatchClientError: LocalizedError {
    /// 409 `no_candidates` : aucun film, même après tous les élargissements.
    /// Réessayer ne changerait rien ; seul le scénario peut le faire.
    case noCandidates
    /// La même chose, côté séries.
    case noSeriesCandidates

    var errorDescription: String? {
        switch self {
        // Le titre de l'écran dit déjà qu'il n'y a rien : le message dit
        // seulement quoi changer, et « Retour à l'accueil » y mène.
        case .noCandidates, .noSeriesCandidates:
            return String(localized: "Essaie une autre durée ou d'autres plateformes, depuis « Ce soir » sur l'accueil.", bundle: .app)
        }
    }

    static func noCandidates(for format: MediaFormat) -> CineMatchClientError {
        format == .series ? .noSeriesCandidates : .noCandidates
    }
}

/// Le moteur de CinéMatch vit sur le serveur : l'app transmet le style, le
/// film de départ et la soirée, et affiche ce qui revient.
///
/// Chaque appel porte son format. Films et séries sont deux profils que le
/// serveur tient à part (galerie, duels, exposition, historique), et leurs
/// identifiants TMDB se recoupent : un appel sans format parlerait de films.
protocol CineMatchFetching: Sendable {
    /// Les comparaisons de la Porte. `forDoor` lève la limite de `total` et
    /// fait recycler les films les moins récemment montrés.
    func comparisonRound(round: Int, shownIDs: [Int], history: [CineMatchComparison], forDoor: Bool,
                         format: MediaFormat) async throws -> CineMatchComparisonRound
    /// Les dix styles, du plus présent dans la galerie au moins présent.
    func styles(format: MediaFormat) async throws -> [CineMatchStyleTile]
    /// Six films d'un style. `page` passe aux six suivants ; `shownIDs`, les
    /// films déjà montrés, sont écartés quel que soit l'ordre du serveur.
    func starters(style: CineMatchStyle, page: Int, shownIDs: [Int],
                  format: MediaFormat) async throws -> CineMatchStarterPage
    /// Les cinq, proches de `anchorID`, ou d'après les coups de cœur sans
    /// film de départ. Avec `replacing`, le serveur ne renvoie que les
    /// remplaçants des films marqués.
    func picks(situation: CineMatchSituation, anchorID: Int?, style: CineMatchStyle?,
               format: MediaFormat, replacing: CineMatchReplacement?) async throws -> CineMatchFiveResponse
    /// `nil` quand aucun film ne correspond au scénario.
    func daily(situation: CineMatchSituation, format: MediaFormat) async throws -> CineMatchFilm?
    func recordExposure(kind: CineMatchExposureKind, tmdbIDs: [Int], format: MediaFormat) async throws
    func recordDuel(winnerID: Int, loserID: Int, format: MediaFormat) async throws
    func recordLaunch(tmdbID: Int, format: MediaFormat) async throws
    /// « Pas celui-là » : le refus d'un des cinq, noté dans sa séance.
    func recordPass(tmdbID: Int, format: MediaFormat) async throws
}

nonisolated struct BackendCineMatchClient: CineMatchFetching, Sendable {
    /// Le serveur n'accepte pas plus de vingt films par écriture d'exposition.
    private static let exposureBatchLimit = 20

    func comparisonRound(round: Int, shownIDs: [Int], history: [CineMatchComparison], forDoor: Bool,
                         format: MediaFormat) async throws -> CineMatchComparisonRound {
        var body: [String: Any] = [
            "round": round,
            "shownIds": shownIDs,
            "history": history.map(Self.payload(for:)),
            "format": format.rawValue,
        ]
        if forDoor { body["purpose"] = "door" }
        let data = try await post(to: APIEndpoints.cineMatchComparison(), body: body)
        return try decode(ComparisonResponseDTO.self, from: data).roundValue
    }

    func styles(format: MediaFormat) async throws -> [CineMatchStyleTile] {
        #if DEBUG
        if let fixture = DebugFixtures.cineMatchStyles(format: format) { return fixture }
        #endif
        let data = try await post(to: APIEndpoints.cineMatchStarters(), body: [
            "format": format.rawValue,
        ])
        return try decode(StylesResponseDTO.self, from: data).tiles
    }

    func starters(style: CineMatchStyle, page: Int, shownIDs: [Int],
                  format: MediaFormat) async throws -> CineMatchStarterPage {
        #if DEBUG
        if let fixture = DebugFixtures.cineMatchStarters(style: style, page: page, format: format) {
            return fixture
        }
        #endif
        var body: [String: Any] = [
            "format": format.rawValue,
            "style": style.rawValue,
            "page": page,
        ]
        if !shownIDs.isEmpty { body["shownIds"] = shownIDs }
        let data = try await post(to: APIEndpoints.cineMatchStarters(), body: body)
        let decoded = try decode(StartersResponseDTO.self, from: data)
        return CineMatchStarterPage(
            // Le serveur renvoie le style demandé ; on garde le nôtre s'il en
            // parle autrement.
            style: CineMatchStyle(rawValue: decoded.style ?? "") ?? style,
            page: decoded.page ?? page,
            films: decoded.films.map(\.film),
            hasMore: decoded.hasMore ?? false,
            restarted: decoded.restarted ?? false
        )
    }

    func picks(situation: CineMatchSituation, anchorID: Int?, style: CineMatchStyle?,
               format: MediaFormat, replacing: CineMatchReplacement?) async throws -> CineMatchFiveResponse {
        var body: [String: Any] = [
            "situation": Self.payload(for: situation),
            "format": format.rawValue,
        ]
        if let anchorID { body["anchorId"] = anchorID }
        if let style { body["style"] = style.rawValue }
        if let replacing {
            var replace: [String: Any] = [
                "keepIds": replacing.keepIDs,
                "seenIds": replacing.seenIDs,
                "refusedIds": replacing.refusedIDs,
            ]
            if let sessionID = replacing.sessionID { replace["sessionId"] = sessionID }
            body["replace"] = replace
        }
        let data: Data
        do {
            data = try await post(to: APIEndpoints.cineMatchPicks(), body: body)
        } catch CineMatchClientError.noCandidates {
            throw CineMatchClientError.noCandidates(for: format)
        }
        let decoded = try decode(FiveResponseDTO.self, from: data)
        return CineMatchFiveResponse(
            films: decoded.films.map(\.film),
            widening: decoded.widened.map {
                CineMatchWidening(duration: $0.duration ?? false, platforms: $0.platforms ?? false)
            },
            sessionID: decoded.sessionId
        )
    }

    func daily(situation: CineMatchSituation, format: MediaFormat) async throws -> CineMatchFilm? {
        let data = try await post(to: APIEndpoints.cineMatchDaily(), body: [
            "situation": Self.payload(for: situation),
            "format": format.rawValue,
        ])
        return try decode(DailyResponseDTO.self, from: data).film?.film
    }

    func recordExposure(kind: CineMatchExposureKind, tmdbIDs: [Int], format: MediaFormat) async throws {
        guard !tmdbIDs.isEmpty else { return }
        var start = 0
        while start < tmdbIDs.count {
            let end = min(start + Self.exposureBatchLimit, tmdbIDs.count)
            _ = try await post(to: APIEndpoints.cineMatchExposure(), body: [
                "kind": kind.rawValue,
                "tmdbIds": Array(tmdbIDs[start..<end]),
                "format": format.rawValue,
            ])
            start = end
        }
    }

    func recordDuel(winnerID: Int, loserID: Int, format: MediaFormat) async throws {
        _ = try await post(to: APIEndpoints.filmDuel(), body: [
            "winnerTmdbId": winnerID, "loserTmdbId": loserID, "format": format.rawValue,
        ])
    }

    func recordLaunch(tmdbID: Int, format: MediaFormat) async throws {
        _ = try await post(to: APIEndpoints.sessionOutcome(), body: [
            "kind": "launch", "tmdbId": tmdbID, "format": format.rawValue,
        ])
    }

    func recordPass(tmdbID: Int, format: MediaFormat) async throws {
        _ = try await post(to: APIEndpoints.sessionOutcome(), body: [
            "kind": "pass", "tmdbId": tmdbID, "format": format.rawValue,
        ])
    }

    // MARK: - Corps de requête

    static func payload(for situation: CineMatchSituation) -> [String: Any] {
        [
            "company": situation.company.rawValue,
            "duration": situation.duration.rawValue,
            "platformIds": situation.platformIDs.sorted(),
            "watchRegion": "FR",
            "engagement": situation.engagement.rawValue,
        ]
    }

    static func payload(for comparison: CineMatchComparison) -> [String: Any] {
        switch comparison {
        case .pick(let keptID, let excludedID, let latencyMs):
            return [
                "kind": "pick", "keptId": keptID, "excludedId": excludedID,
                "latencyMs": latencyMs,
            ]
        case .none(let shownIDs):
            return ["kind": "none", "shownIds": shownIDs]
        }
    }

    // MARK: - Wire helpers

    /// Même mécanique que `BackendRecommendationClient.post`, qui est privée.
    /// Seul le 409 `no_candidates` reçoit ici son propre message : celui du
    /// questionnaire parle de « critères », CinéMatch parle de la soirée.
    private func post(to url: URL?, body: [String: Any]) async throws -> Data {
        guard BackendConfiguration.baseURL != nil else {
            throw RecommendationClientError.missingBaseURL
        }
        guard let url else {
            throw RecommendationClientError.invalidURL
        }
        guard let user = Auth.auth().currentUser else {
            throw RecommendationClientError.notAuthenticated
        }
        let token = try await user.getIDToken()

        var request = await URLRequest(backend: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            if let urlError = error as? URLError, urlError.code == .cancelled {
                throw CancellationError()
            }
            if error is CancellationError { throw error }
            throw RecommendationClientError.transport(message: error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw RecommendationClientError.httpStatus(code: -1, message: nil)
        }
        guard (200...299).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8)
            if http.statusCode == 409, message?.contains("no_candidates") == true {
                throw CineMatchClientError.noCandidates
            }
            throw RecommendationClientError.httpStatus(code: http.statusCode, message: message)
        }
        return data
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            let body = String(data: data, encoding: .utf8) ?? "<body non lisible>"
            throw RecommendationClientError.decoding(message: "\(error) · Réponse: \(body)")
        }
    }
}

// MARK: - DTOs

private nonisolated struct GalleryFilmDTO: Decodable, Sendable {
    let id: Int
    let title: String?
    let posterPath: String?
    let releaseDate: String?
    let genreIds: [Int]?

    enum CodingKeys: String, CodingKey {
        case id, title
        case posterPath = "poster_path"
        case releaseDate = "release_date"
        case genreIds = "genre_ids"
    }

    var film: CineMatchGalleryFilm {
        CineMatchGalleryFilm(
            id: id,
            title: title ?? String(localized: "Sans titre", bundle: .app),
            posterPath: posterPath,
            releaseDate: releaseDate,
            genreIDs: genreIds ?? []
        )
    }
}

private nonisolated struct StyleTileDTO: Decodable, Sendable {
    let key: String
    let count: Int?
    let films: [GalleryFilmDTO]?
}

private nonisolated struct StylesResponseDTO: Decodable, Sendable {
    let styles: [StyleTileDTO]

    /// Un style que l'app ne connaît pas (ajouté au serveur après elle) est
    /// laissé de côté plutôt que de faire échouer l'écran.
    var tiles: [CineMatchStyleTile] {
        styles.compactMap { tile in
            CineMatchStyle(rawValue: tile.key).map {
                CineMatchStyleTile(style: $0, count: max(0, tile.count ?? 0), films: (tile.films ?? []).map(\.film))
            }
        }
    }
}

private nonisolated struct StartersResponseDTO: Decodable, Sendable {
    let style: String?
    let page: Int?
    let films: [GalleryFilmDTO]
    let hasMore: Bool?
    let restarted: Bool?
}

private nonisolated struct ComparisonResponseDTO: Decodable, Sendable {
    let total: Int
    let round: Int
    let films: [GalleryFilmDTO]
    /// Les clés JSON sont des chaînes : un objet JSON n'en connaît pas d'autres.
    let replacements: [String: GalleryFilmDTO]?
    let excludeFilms: [GalleryFilmDTO]?

    var roundValue: CineMatchComparisonRound {
        CineMatchComparisonRound(
            total: total,
            round: round,
            films: films.map(\.film),
            replacements: Dictionary(
                (replacements ?? [:]).compactMap { key, value in
                    Int(key).map { ($0, value.film) }
                },
                uniquingKeysWith: { first, _ in first }
            ),
            excludeFilms: (excludeFilms ?? []).map(\.film)
        )
    }
}

private nonisolated struct FiveFilmDTO: Decodable, Sendable {
    let id: Int
    let title: String?
    let posterPath: String?
    let overview: String?
    let releaseDate: String?
    let genreIds: [Int]?
    let runtimeMinutes: Int?
    let providerIds: [Int]?
    let trailerKey: String?
    /// `tv` pour une série ; absent pour un film.
    let mediaType: String?
    let seasonCount: Int?
    let episodeCount: Int?
    let status: String?

    enum CodingKeys: String, CodingKey {
        case id, title, overview, status
        case posterPath = "poster_path"
        case releaseDate = "release_date"
        case genreIds = "genre_ids"
        case runtimeMinutes = "runtime_minutes"
        case providerIds = "provider_ids"
        case trailerKey = "trailer_key"
        case mediaType = "media_type"
        case seasonCount = "season_count"
        case episodeCount = "episode_count"
    }

    var film: CineMatchFilm {
        let isSeries = mediaType == "tv"
        return CineMatchFilm(
            item: MediaItem(
                tmdbId: id,
                mediaType: isSeries ? .tv : .movie,
                title: title ?? String(localized: "Sans titre", bundle: .app),
                posterPath: posterPath,
                overview: overview,
                // Le contrat ne transporte ni note ni nombre de votes : la
                // carte n'affiche pas de note.
                voteAverage: nil,
                voteCount: nil,
                genreIds: genreIds ?? [],
                releaseDate: releaseDate,
                seasonCount: isSeries ? seasonCount : nil
            ),
            runtimeMinutes: runtimeMinutes,
            providerIDs: providerIds ?? [],
            trailerKey: trailerKey,
            episodeCount: isSeries ? episodeCount : nil,
            status: isSeries ? status.flatMap(CineMatchSeriesStatus.init(rawValue:)) : nil
        )
    }
}

private nonisolated struct WidenedDTO: Decodable, Sendable {
    let duration: Bool?
    let platforms: Bool?
}

private nonisolated struct FiveResponseDTO: Decodable, Sendable {
    let films: [FiveFilmDTO]
    let widened: WidenedDTO?
    let sessionId: String?
}

private nonisolated struct DailyResponseDTO: Decodable, Sendable {
    let film: FiveFilmDTO?
    let date: String?
}
