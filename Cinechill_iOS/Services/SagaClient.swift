//
//  SagaClient.swift
//  Cinechill_iOS
//

import Foundation

/// Une seule erreur, et un seul message.
///
/// La feuille de saga n'est pas un écran dont on dépend : si la saga ne vient
/// pas, on ferme et le film balayé reste rangé. Distinguer un 404 d'une panne
/// réseau ne changerait rien à ce qu'il y a à faire.
enum SagaClientError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        String(localized: "On n'a pas réussi à charger la saga.", bundle: .app)
    }
}

protocol SagaFetching: Sendable {
    func saga(id: Int) async throws -> Saga
}

nonisolated struct BackendSagaClient: SagaFetching, Sendable {
    func saga(id: Int) async throws -> Saga {
        guard BackendConfiguration.baseURL != nil,
              let url = APIEndpoints.collection(id: id) else {
            throw SagaClientError.unavailable
        }

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
            throw SagaClientError.unavailable
        }
        guard let http = response as? HTTPURLResponse,
              (200 ... 299).contains(http.statusCode),
              let decoded = try? JSONDecoder().decode(SagaDTO.self, from: data) else {
            throw SagaClientError.unavailable
        }

        return Saga(
            id: decoded.id,
            name: decoded.name ?? "",
            parts: decoded.parts.map(\.sagaPart)
        )
    }
}

// MARK: - DTOs

private struct SagaDTO: Decodable, Sendable {
    let id: Int
    let name: String?
    let parts: [SagaPartDTO]
}

private struct SagaPartDTO: Decodable, Sendable {
    let id: Int
    let title: String?
    let overview: String?
    let posterPath: String?
    let voteAverage: Double?
    let voteCount: Int?
    let genreIds: [Int]?
    let releaseDate: String?

    enum CodingKeys: String, CodingKey {
        case id, title, overview
        case posterPath = "poster_path"
        case voteAverage = "vote_average"
        case voteCount = "vote_count"
        case genreIds = "genre_ids"
        case releaseDate = "release_date"
    }

    var sagaPart: SagaPart {
        SagaPart(
            tmdbId: id,
            title: title ?? String(localized: "Sans titre", bundle: .app),
            posterPath: posterPath,
            overview: overview,
            voteAverage: voteAverage,
            voteCount: voteCount,
            genreIds: genreIds ?? [],
            releaseDate: releaseDate
        )
    }
}
