//
//  CineMatchClient.swift
//  Cinechill_iOS
//

import Foundation
import FirebaseAuth

/// Les erreurs propres à CinéMatch v2. Le reste passe par
/// `RecommendationClientError`, dont les messages valent aussi ici.
nonisolated enum CineMatchClientError: LocalizedError {
    /// 409 `no_candidates` : aucun film, même après tous les élargissements.
    /// Réessayer ne changerait rien ; seul le scénario peut le faire.
    case noCandidates

    var errorDescription: String? {
        switch self {
        case .noCandidates:
            return String(localized: "Aucun film ne correspond pour l'instant. Change tes réglages pour ce soir.", bundle: .app)
        }
    }
}

/// Le moteur de CinéMatch v2 vit sur le serveur : l'app pose les questions,
/// transmet les réponses, et affiche ce qui revient.
protocol CineMatchFetching: Sendable {
    /// `forDoor` : les douze comparaisons de la Porte. Le serveur lève alors la
    /// limite de `total` et recycle les films les moins récemment montrés.
    func comparisonRound(round: Int, shownIDs: [Int], history: [CineMatchComparison], forDoor: Bool) async throws -> CineMatchComparisonRound
    func five(situation: CineMatchSituation, want: CineMatchWant, energy: CineMatchEnergy,
              comparisons: [CineMatchComparison], hesitations: Int) async throws -> CineMatchFiveResponse
    /// `nil` quand aucun film ne correspond au scénario.
    func daily(situation: CineMatchSituation) async throws -> CineMatchFilm?
    func recordExposure(kind: CineMatchExposureKind, tmdbIDs: [Int]) async throws
    func recordDuel(winnerID: Int, loserID: Int) async throws
    func recordLaunch(tmdbID: Int) async throws
}

nonisolated struct BackendCineMatchClient: CineMatchFetching, Sendable {
    /// Le serveur n'accepte pas plus de vingt films par écriture d'exposition.
    private static let exposureBatchLimit = 20

    func comparisonRound(round: Int, shownIDs: [Int], history: [CineMatchComparison], forDoor: Bool) async throws -> CineMatchComparisonRound {
        var body: [String: Any] = [
            "round": round,
            "shownIds": shownIDs,
            "history": history.map(Self.payload(for:)),
        ]
        if forDoor { body["purpose"] = "door" }
        let data = try await post(to: APIEndpoints.cineMatchComparison(), body: body)
        return try decode(ComparisonResponseDTO.self, from: data).roundValue
    }

    func five(situation: CineMatchSituation, want: CineMatchWant, energy: CineMatchEnergy,
              comparisons: [CineMatchComparison], hesitations: Int) async throws -> CineMatchFiveResponse {
        let data = try await post(to: APIEndpoints.cineMatchFive(), body: [
            "situation": Self.payload(for: situation),
            "want": want.rawValue,
            "energy": energy.rawValue,
            "comparisons": comparisons.map(Self.payload(for:)),
            "hesitations": hesitations,
        ])
        let decoded = try decode(FiveResponseDTO.self, from: data)
        return CineMatchFiveResponse(
            films: decoded.films.map(\.film),
            widening: decoded.widened.map {
                CineMatchWidening(duration: $0.duration ?? false, platforms: $0.platforms ?? false)
            }
        )
    }

    func daily(situation: CineMatchSituation) async throws -> CineMatchFilm? {
        let data = try await post(to: APIEndpoints.cineMatchDaily(), body: [
            "situation": Self.payload(for: situation),
        ])
        return try decode(DailyResponseDTO.self, from: data).film?.film
    }

    func recordExposure(kind: CineMatchExposureKind, tmdbIDs: [Int]) async throws {
        guard !tmdbIDs.isEmpty else { return }
        var start = 0
        while start < tmdbIDs.count {
            let end = min(start + Self.exposureBatchLimit, tmdbIDs.count)
            _ = try await post(to: APIEndpoints.cineMatchExposure(), body: [
                "kind": kind.rawValue,
                "tmdbIds": Array(tmdbIDs[start..<end]),
            ])
            start = end
        }
    }

    func recordDuel(winnerID: Int, loserID: Int) async throws {
        _ = try await post(to: APIEndpoints.filmDuel(), body: [
            "winnerTmdbId": winnerID, "loserTmdbId": loserID,
        ])
    }

    func recordLaunch(tmdbID: Int) async throws {
        _ = try await post(to: APIEndpoints.sessionOutcome(), body: [
            "kind": "launch", "tmdbId": tmdbID,
        ])
    }

    // MARK: - Corps de requête

    static func payload(for situation: CineMatchSituation) -> [String: Any] {
        [
            "company": situation.company.rawValue,
            "duration": situation.duration.rawValue,
            "platformIds": situation.platformIDs.sorted(),
            "watchRegion": "FR",
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
    /// questionnaire parle de « critères », CinéMatch v2 parle de scénario.
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

private nonisolated struct ComparisonResponseDTO: Decodable, Sendable {
    let total: Int
    let round: Int
    let films: [GalleryFilmDTO]
    /// Les clés JSON sont des chaînes : un objet JSON n'en connaît pas d'autres.
    let replacements: [String: GalleryFilmDTO]?

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
            )
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

    enum CodingKeys: String, CodingKey {
        case id, title, overview
        case posterPath = "poster_path"
        case releaseDate = "release_date"
        case genreIds = "genre_ids"
        case runtimeMinutes = "runtime_minutes"
        case providerIds = "provider_ids"
        case trailerKey = "trailer_key"
    }

    var film: CineMatchFilm {
        CineMatchFilm(
            item: MediaItem(
                tmdbId: id,
                mediaType: .movie,
                title: title ?? String(localized: "Sans titre", bundle: .app),
                posterPath: posterPath,
                overview: overview,
                // Le contrat ne transporte ni note ni nombre de votes : la
                // carte n'affiche pas de note.
                voteAverage: nil,
                voteCount: nil,
                genreIds: genreIds ?? [],
                releaseDate: releaseDate
            ),
            runtimeMinutes: runtimeMinutes,
            providerIDs: providerIds ?? [],
            trailerKey: trailerKey
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
