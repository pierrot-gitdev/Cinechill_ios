//
//  RecommendationClient.swift
//  Cinechill_iOS
//

import Foundation
import FirebaseAuth

enum RecommendationClientError: LocalizedError {
    case missingBaseURL
    case invalidURL
    case notAuthenticated
    case transport(message: String)
    case httpStatus(code: Int, message: String?)
    case decoding(message: String)

    var errorDescription: String? {
        switch self {
        case .missingBaseURL:
            return "URL backend absente. Définissez BACKEND_BASE_HOST dans Project.xcconfig."
        case .invalidURL:
            return "URL backend invalide."
        case .notAuthenticated:
            return "Vous devez être connecté(e) pour obtenir des recommandations."
        case .transport(let message):
            return "Erreur réseau CinéMatch : \(message)"
        case .httpStatus(let code, let message):
            if let message, !message.isEmpty {
                return "CinéMatch (HTTP \(code)) : \(message)"
            }
            return "Erreur CinéMatch (HTTP \(code))."
        case .decoding(let message):
            return "Impossible de lire la réponse CinéMatch. \(message)"
        }
    }
}

protocol RecommendationFetching: Sendable {
    func fetchRecommendations(for answers: QuestionnaireAnswers) async throws -> [RecommendationResult]
}

/// Appelle la Cloud Function `getrecommendations` : filtres durs, pool multi-tri, scoring pondéré,
/// exploration et diversité sont calculés côté serveur (voir la spec CinéMatch). Jamais mis en
/// cache disque, contrairement à `BackendPopularClient` — le but est justement d'éviter de
/// retomber toujours sur la même réponse.
nonisolated struct BackendRecommendationClient: RecommendationFetching, Sendable {
    func fetchRecommendations(for answers: QuestionnaireAnswers) async throws -> [RecommendationResult] {
        guard BackendConfiguration.baseURL != nil else {
            throw RecommendationClientError.missingBaseURL
        }
        guard let url = APIEndpoints.recommendations() else {
            throw RecommendationClientError.invalidURL
        }
        guard let user = Auth.auth().currentUser else {
            throw RecommendationClientError.notAuthenticated
        }
        let token = try await user.getIDToken()

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: Self.requestBody(for: answers))

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
            throw RecommendationClientError.httpStatus(code: http.statusCode, message: String(data: data, encoding: .utf8))
        }

        do {
            let decoded = try JSONDecoder().decode(RecommendationsResponseDTO.self, from: data)
            return decoded.results.map(\.recommendationResult)
        } catch {
            let body = String(data: data, encoding: .utf8) ?? "<body non lisible>"
            throw RecommendationClientError.decoding(message: "URL: \(url.absoluteString) · Réponse: \(body)")
        }
    }

    /// Contrat attendu par `getrecommendations` — tout le mapping vers les paramètres TMDB
    /// (with_genres, with_watch_providers, mots-clés…) est fait côté Cloud Function.
    static func requestBody(for answers: QuestionnaireAnswers) -> [String: Any] {
        [
            "contentFormat": answers.contentFormat?.rawValue as Any,
            "genres": answers.genres.map(\.rawValue).sorted(),
            "platformIds": answers.platformIDs.sorted(),
            "watchRegion": "FR",
            "audience": answers.audience?.rawValue as Any,
            "mood": answers.mood?.rawValue as Any,
            "origin": answers.origin.rawValue,
            "mindset": answers.mindset?.rawValue as Any,
            "dealbreaker": answers.dealbreaker?.rawValue as Any,
            "popularity": answers.popularity.rawValue,
            "cast": answers.cast.rawValue,
            "runtime": answers.runtime.rawValue,
            "era": answers.era.rawValue
        ]
    }
}

nonisolated private struct RecommendationsResponseDTO: Decodable, Sendable {
    let results: [RecommendationRow]
}

nonisolated private struct RecommendationRow: Decodable, Sendable {
    let id: Int
    let title: String
    let posterPath: String?
    let overview: String?
    let voteAverage: Double?
    let genreIds: [Int]?
    let releaseDate: String?
    let matchScore: Int
    let reasons: [String]
    let trailerKey: String?
    let providerIds: [Int]?

    enum CodingKeys: String, CodingKey {
        case id, title
        case posterPath = "poster_path"
        case overview
        case voteAverage = "vote_average"
        case genreIds = "genre_ids"
        case releaseDate = "release_date"
        case matchScore = "match_score"
        case reasons
        case trailerKey = "trailer_key"
        case providerIds = "provider_ids"
    }

    var recommendationResult: RecommendationResult {
        RecommendationResult(
            item: MediaItem(
                tmdbId: id,
                mediaType: .movie,
                title: title,
                posterPath: posterPath,
                overview: overview,
                voteAverage: voteAverage,
                genreIds: genreIds ?? [],
                releaseDate: releaseDate
            ),
            matchScore: matchScore,
            reasons: reasons,
            trailerKey: trailerKey,
            providerIDs: providerIds ?? []
        )
    }
}
