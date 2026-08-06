//
//  HomeRowsClient.swift
//  Cinechill_iOS
//

import Foundation
import FirebaseAuth

/// Les trois rangées personnalisées de l'accueil, telles que renvoyées par
/// `getHomeRows`. Un seul appel : le serveur a la galerie et le profil déclaré
/// en main, les découper en trois requêtes paierait trois fois la même lecture.
nonisolated struct HomeRows: Sendable, Equatable {
    /// Films sortis en salle en France sur les huit dernières semaines,
    /// ordonnés par correspondance avec vos goûts.
    let inTheaters: [MediaItem]
    /// Films en mouvement cette semaine, dans l'ordre du classement.
    let trending: [MediaItem]
    let becauseYouWatched: SeededRow?

    static let empty = HomeRows(inTheaters: [], trending: [], becauseYouWatched: nil)
}

/// Une rangée semée par un film de la galerie. Le titre de la graine est
/// affiché : la recommandation s'explique ainsi d'elle-même.
nonisolated struct SeededRow: Sendable, Equatable {
    let seedID: Int
    let seedTitle: String?
    let items: [MediaItem]
}

protocol HomeRowsFetching: Sendable {
    func fetchHomeRows() async throws -> HomeRows
}

nonisolated struct BackendHomeRowsClient: HomeRowsFetching, Sendable {
    func fetchHomeRows() async throws -> HomeRows {
        guard BackendConfiguration.baseURL != nil else {
            throw HomeRowsClientError.missingBaseURL
        }
        guard let url = APIEndpoints.homeRows() else {
            throw HomeRowsClientError.invalidURL
        }
        guard let user = Auth.auth().currentUser else {
            throw HomeRowsClientError.notAuthenticated
        }
        let token = try await user.getIDToken()

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = Data("{}".utf8)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            if let urlError = error as? URLError, urlError.code == .cancelled {
                throw CancellationError()
            }
            if error is CancellationError { throw error }
            throw HomeRowsClientError.transport(message: error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw HomeRowsClientError.httpStatus(code: code)
        }

        let decoded = try JSONDecoder().decode(HomeRowsResponseDTO.self, from: data)
        return HomeRows(
            inTheaters: decoded.inTheaters.map(\.mediaItem),
            trending: decoded.trending.map(\.mediaItem),
            becauseYouWatched: decoded.becauseYouWatched.map { seeded in
                SeededRow(
                    seedID: seeded.seedID,
                    seedTitle: seeded.seedTitle,
                    items: seeded.items.map(\.mediaItem)
                )
            }
        )
    }
}

enum HomeRowsClientError: LocalizedError {
    case missingBaseURL
    case invalidURL
    case notAuthenticated
    case transport(message: String)
    case httpStatus(code: Int)

    var errorDescription: String? {
        switch self {
        case .missingBaseURL:
            return "URL backend absente. Définissez BACKEND_BASE_HOST dans Project.xcconfig."
        case .invalidURL:
            return "URL backend invalide."
        case .notAuthenticated:
            return "Vous devez être connecté(e) pour voir vos suggestions."
        case .transport(let message):
            return "Erreur réseau : \(message)"
        case .httpStatus(let code):
            return "Erreur serveur (HTTP \(code))."
        }
    }
}

// MARK: - DTOs

private struct HomeRowsResponseDTO: Decodable, Sendable {
    let inTheaters: [HomeRowItemDTO]
    let trending: [HomeRowItemDTO]
    let becauseYouWatched: SeededRowDTO?

    enum CodingKeys: String, CodingKey {
        case inTheaters = "in_theaters"
        case trending
        case becauseYouWatched = "because_you_watched"
    }
}

private struct SeededRowDTO: Decodable, Sendable {
    let seedID: Int
    let seedTitle: String?
    let items: [HomeRowItemDTO]

    enum CodingKeys: String, CodingKey {
        case seedID = "seed_id"
        case seedTitle = "seed_title"
        case items
    }
}

private struct HomeRowItemDTO: Decodable, Sendable {
    let id: Int
    let title: String?
    let overview: String?
    let posterPath: String?
    let voteAverage: Double?
    let genreIds: [Int]?
    let releaseDate: String?

    enum CodingKeys: String, CodingKey {
        case id, title, overview
        case posterPath = "poster_path"
        case voteAverage = "vote_average"
        case genreIds = "genre_ids"
        case releaseDate = "release_date"
    }

    var mediaItem: MediaItem {
        MediaItem(
            tmdbId: id,
            mediaType: .movie,
            title: title ?? "Sans titre",
            posterPath: posterPath,
            overview: overview,
            voteAverage: voteAverage,
            genreIds: genreIds ?? [],
            releaseDate: releaseDate
        )
    }
}
