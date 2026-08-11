//
//  SwipeFeedClient.swift
//  Cinechill_iOS
//

import Foundation
import FirebaseAuth

enum SwipeFeedClientError: LocalizedError {
    case missingBaseURL
    case invalidURL
    case notAuthenticated
    case transport(message: String)
    case httpStatus(code: Int, message: String?)
    case decoding(message: String)

    var errorDescription: String? {
        switch self {
        case .missingBaseURL:
            return String(localized: "URL backend absente. Définissez BACKEND_BASE_HOST dans Project.xcconfig.", bundle: .app)
        case .invalidURL:
            return String(localized: "URL backend invalide.", bundle: .app)
        case .notAuthenticated:
            return String(localized: "Vous devez être connecté(e) pour découvrir des films.", bundle: .app)
        case .transport(let message):
            return String(localized: "Erreur réseau : \(message)", bundle: .app)
        case .httpStatus(let code, let message):
            if let message, !message.isEmpty {
                return String(localized: "Erreur serveur (HTTP \(code)) : \(message)", bundle: .app)
            }
            return String(localized: "Erreur serveur (HTTP \(code)).", bundle: .app)
        case .decoding(let message):
            return String(localized: "Impossible de lire la réponse du serveur. \(message)", bundle: .app)
        }
    }
}

nonisolated struct SwipeFeedBatch: Sendable {
    let cards: [SwipeCard]
    /// Le backend n'a plus rien à proposer : tout est classé ou en cooldown.
    let exhausted: Bool
}

protocol SwipeFeedFetching: Sendable {
    /// - Parameter excludedIDs: ids déjà servis dans la session courante, pour
    ///   que deux lots consécutifs ne se recouvrent pas.
    func fetchFeed(excludedIDs: [Int]) async throws -> SwipeFeedBatch
    func record(_ swipes: [PendingSwipe]) async throws
}

nonisolated struct BackendSwipeFeedClient: SwipeFeedFetching, Sendable {
    func fetchFeed(excludedIDs: [Int]) async throws -> SwipeFeedBatch {
        // Le backend recharge la galerie à chaque appel : au-delà de quelques
        // centaines d'ids la requête grossit pour rien, les plus récents
        // suffisent à éviter les doublons de session.
        let recent = Array(excludedIDs.suffix(300))
        let data = try await post(to: APIEndpoints.swipeFeed(), body: ["excludeIds": recent])
        let decoded = try decode(SwipeFeedResponseDTO.self, from: data)
        return SwipeFeedBatch(
            cards: decoded.cards.map(\.swipeCard),
            exhausted: decoded.exhausted ?? false
        )
    }

    func record(_ swipes: [PendingSwipe]) async throws {
        guard !swipes.isEmpty else { return }
        _ = try await post(to: APIEndpoints.recordSwipes(), body: [
            "decisions": swipes.map(\.jsonPayload),
        ])
    }

    // MARK: - Wire helpers

    private func post(to url: URL?, body: [String: Any]) async throws -> Data {
        guard BackendConfiguration.baseURL != nil else {
            throw SwipeFeedClientError.missingBaseURL
        }
        guard let url else {
            throw SwipeFeedClientError.invalidURL
        }
        guard let user = Auth.auth().currentUser else {
            throw SwipeFeedClientError.notAuthenticated
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
            throw SwipeFeedClientError.transport(message: error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw SwipeFeedClientError.httpStatus(code: -1, message: nil)
        }
        guard (200...299).contains(http.statusCode) else {
            throw SwipeFeedClientError.httpStatus(
                code: http.statusCode,
                message: String(data: data, encoding: .utf8)
            )
        }
        return data
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            let body = String(data: data, encoding: .utf8) ?? "<body non lisible>"
            throw SwipeFeedClientError.decoding(message: "\(error) · Réponse: \(body)")
        }
    }
}

// MARK: - DTOs

private struct SwipeFeedResponseDTO: Decodable, Sendable {
    let cards: [SwipeCardDTO]
    let exhausted: Bool?
}

private struct SwipeCardDTO: Decodable, Sendable {
    let id: Int
    let title: String?
    let overview: String?
    let posterPath: String?
    let voteAverage: Double?
    let voteCount: Int?
    let genreIds: [Int]?
    let releaseDate: String?
    let source: String?

    enum CodingKeys: String, CodingKey {
        case id, title, overview, source
        case posterPath = "poster_path"
        case voteAverage = "vote_average"
        case voteCount = "vote_count"
        case genreIds = "genre_ids"
        case releaseDate = "release_date"
    }

    var swipeCard: SwipeCard {
        SwipeCard(
            tmdbId: id,
            title: title ?? String(localized: "Sans titre", bundle: .app),
            posterPath: posterPath,
            overview: overview,
            voteAverage: voteAverage,
            voteCount: voteCount,
            genreIds: genreIds ?? [],
            releaseDate: releaseDate,
            source: source
        )
    }
}
