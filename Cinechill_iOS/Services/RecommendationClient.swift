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

nonisolated struct CandidatePoolResponse: Sendable {
    let candidates: [CandidateRow]
    let notice: String?
}

/// Les trois appels du moteur de préférence actif (voir la spec "moteur de préférence actif") —
/// remplacent l'ancien `fetchRecommendations` unique. Le pool circule dans les deux sens en JSON
/// brut plutôt que d'être re-dérivé côté serveur, pour que le client puisse le réduire localement
/// entre chaque appel sans repayer un aller-retour réseau par question.
protocol RecommendationFetching: Sendable {
    func fetchCandidatePool(trunk: QuestionnaireAnswers) async throws -> CandidatePoolResponse
    func enrichCandidates(_ candidates: [CandidateRow]) async throws -> [EnrichedCandidateRow]
    func finalizeRecommendations(
        answers: QuestionnaireAnswers, candidates: [EnrichedCandidateRow]
    ) async throws -> [RecommendationResult]
}

nonisolated struct BackendRecommendationClient: RecommendationFetching, Sendable {
    func fetchCandidatePool(trunk: QuestionnaireAnswers) async throws -> CandidatePoolResponse {
        let data = try await post(to: APIEndpoints.candidatePool(), body: Self.requestBody(for: trunk))
        let decoded = try decode(CandidatePoolResponseDTO.self, from: data)
        return CandidatePoolResponse(
            candidates: decoded.candidates.map(\.candidateRow),
            notice: decoded.notice
        )
    }

    func enrichCandidates(_ candidates: [CandidateRow]) async throws -> [EnrichedCandidateRow] {
        guard !candidates.isEmpty else { return [] }
        let data = try await post(to: APIEndpoints.enrichCandidates(), body: [
            "candidates": candidates.map(\.jsonPayload),
        ])
        let decoded = try decode(EnrichCandidatesResponseDTO.self, from: data)
        return decoded.candidates
    }

    func finalizeRecommendations(
        answers: QuestionnaireAnswers, candidates: [EnrichedCandidateRow]
    ) async throws -> [RecommendationResult] {
        let data = try await post(to: APIEndpoints.finalizeRecommendations(), body: [
            "answers": Self.requestBody(for: answers),
            "candidates": candidates.map(\.jsonPayload),
        ])
        let decoded = try decode(FinalizeResponseDTO.self, from: data)
        return decoded.results.map(\.recommendationResult)
    }

    // MARK: - Wire helpers

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

        var request = URLRequest(url: url)
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
            throw RecommendationClientError.httpStatus(code: http.statusCode, message: String(data: data, encoding: .utf8))
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

    /// Contrat attendu côté backend — tout le mapping vers les paramètres TMDB
    /// (with_genres, with_watch_providers, mots-clés…) est fait côté Cloud Function.
    /// Réutilisé pour le socle (T1-T4, champs restants à leurs valeurs par défaut) comme pour
    /// l'ensemble des réponses collectées à la finalisation.
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
            "era": answers.era.rawValue,
            "surpriseIntensity": answers.surpriseIntensity,
            "preferredGenreIds": Array(answers.preferredGenreIDs),
            "avoidedGenreIds": Array(answers.avoidedGenreIDs),
        ]
    }
}

// MARK: - DTOs

private struct CandidatePoolResponseDTO: Decodable, Sendable {
    let candidates: [CandidateRowDTO]
    let notice: String?
}

private struct EnrichCandidatesResponseDTO: Decodable, Sendable {
    let candidates: [EnrichedCandidateRow]
}

private struct CandidateRowDTO: Decodable, Sendable {
    let id: Int
    let title: String?
    let overview: String?
    let posterPath: String?
    let voteAverage: Double?
    let voteCount: Int?
    let popularity: Double?
    let genreIds: [Int]?
    let releaseDate: String?
    let originCountry: [String]?

    enum CodingKeys: String, CodingKey {
        case id, title, overview
        case posterPath = "poster_path"
        case voteAverage = "vote_average"
        case voteCount = "vote_count"
        case popularity
        case genreIds = "genre_ids"
        case releaseDate = "release_date"
        case originCountry = "origin_country"
    }

    var candidateRow: CandidateRow {
        CandidateRow(
            id: id,
            title: title,
            overview: overview,
            posterPath: posterPath,
            voteAverage: voteAverage,
            voteCount: voteCount,
            popularity: popularity,
            genreIds: genreIds ?? [],
            releaseDate: releaseDate,
            originCountry: originCountry ?? []
        )
    }
}

private struct FinalizeResponseDTO: Decodable, Sendable {
    let results: [RecommendationRow]
}

private struct RecommendationRow: Decodable, Sendable {
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
