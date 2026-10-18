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

    /// Les erreurs que le serveur identifie par un code, dites en français.
    private static func knownServerMessage(in body: String?) -> String? {
        guard let body else { return nil }
        if body.contains("no_candidates") {
            return String(localized: "Aucun film ne correspond à ces critères pour le moment.", bundle: .app)
        }
        return nil
    }

    var errorDescription: String? {
        switch self {
        case .missingBaseURL:
            return String(localized: "URL backend absente. Définis BACKEND_BASE_HOST dans Project.xcconfig.", bundle: .app)
        case .invalidURL:
            return String(localized: "URL backend invalide.", bundle: .app)
        case .notAuthenticated:
            return String(localized: "Connecte-toi pour continuer.", bundle: .app)
        case .transport(let message):
            return String(localized: "Erreur réseau CinéMatch : \(message)", bundle: .app)
        case .httpStatus(let code, let message):
            // Les cas que le serveur sait nommer sont traduits ici. Le reste
            // garde le corps brut : il ne s'adresse plus à l'utilisateur mais à
            // qui lira le rapport de bug, et le tronquer nous priverait du seul
            // indice disponible.
            if let known = Self.knownServerMessage(in: message) {
                return known
            }
            if let message, !message.isEmpty {
                return String(localized: "CinéMatch (HTTP \(code)) : \(message)", bundle: .app)
            }
            return String(localized: "Erreur CinéMatch (HTTP \(code)).", bundle: .app)
        case .decoding(let message):
            return String(localized: "Impossible de lire la réponse CinéMatch. \(message)", bundle: .app)
        }
    }
}

/// Ce que la Porte demande au serveur : l'état des deux Portes, et la passe
/// de rattrapage de la galerie.
protocol RecommendationFetching: Sendable {
    /// L'état des deux Portes, mesuré sur la galerie et la watchlist.
    func fetchDoors() async throws -> DoorReading
    /// La passe de rattrapage : elle positionne les films déjà en galerie et
    /// transforme les « Je l'ai adoré » passés en coups de cœur. Rend `true`
    /// quand il ne reste plus rien à traiter.
    func backfillGallery() async throws -> Bool
}

/// Le client des appels du serveur hors CinéMatch : les Portes, la passe de
/// rattrapage de la galerie, et l'enrichissement des films de la watchlist
/// (voir `CandidateEnriching`).
nonisolated struct BackendRecommendationClient: RecommendationFetching, Sendable {
    func enrichCandidates(_ candidates: [CandidateRow]) async throws -> [EnrichedCandidateRow] {
        guard !candidates.isEmpty else { return [] }
        let data = try await post(to: APIEndpoints.enrichCandidates(), body: [
            "candidates": candidates.map(\.jsonPayload),
        ])
        let decoded = try decode(EnrichCandidatesResponseDTO.self, from: data)
        return decoded.candidates
    }

    func fetchDoors() async throws -> DoorReading {
        let data = try await post(to: APIEndpoints.doors(), body: [:])
        return try decode(DoorReadingDTO.self, from: data).reading
    }

    func backfillGallery() async throws -> Bool {
        let data = try await post(to: APIEndpoints.backfillGallery(), body: [:])
        return (try? decode(BackfillResponseDTO.self, from: data))?.done ?? true
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
}

// MARK: - DTOs

private struct EnrichCandidatesResponseDTO: Decodable, Sendable {
    let candidates: [EnrichedCandidateRow]
}

private struct BackfillResponseDTO: Decodable, Sendable {
    let done: Bool
}

private struct DoorReadingDTO: Decodable, Sendable {
    let door: DoorState?
    let seriesDoor: DoorState?

    enum CodingKeys: String, CodingKey {
        case door
        case seriesDoor = "series_door"
    }

    var reading: DoorReading {
        DoorReading(door: door, seriesDoor: seriesDoor?.markedAsSeries())
    }
}
