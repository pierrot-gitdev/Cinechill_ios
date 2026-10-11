//
//  TitleSearchClient.swift
//  Cinechill_iOS
//

import Foundation
import FirebaseAuth

/// La recherche de films et de séries, par le serveur.
///
/// Un seul appel rend les deux formats : TMDB `/search/multi` les mêle déjà, et
/// passer de « Films » à « Séries » ne doit pas relancer de requête. La clé TMDB
/// reste côté serveur, comme pour toutes les autres listes.
protocol TitleSearching: Sendable {
    func searchTitles(_ query: String) async throws -> [MediaItem]
}

nonisolated struct BackendTitleSearchClient: TitleSearching, Sendable {
    func searchTitles(_ query: String) async throws -> [MediaItem] {
        guard BackendConfiguration.baseURL != nil, let url = APIEndpoints.searchTitles() else {
            throw SocialError.missingBaseURL
        }
        guard let user = Auth.auth().currentUser else { throw SocialError.notAuthenticated }
        let token = try await user.getIDToken()

        var request = await URLRequest(backend: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["query": query])

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            if error is CancellationError { throw error }
            if let urlError = error as? URLError, urlError.code == .cancelled {
                throw CancellationError()
            }
            throw SocialError.transport(message: String(localized: "On n'arrive pas à joindre le serveur. Vérifie ta connexion internet.", bundle: .app))
        }
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw SocialError.transport(message: String(localized: "Un souci de notre côté. Réessaie dans un instant.", bundle: .app))
        }
        return try JSONDecoder().decode(TitleSearchResponseDTO.self, from: data).results.map(\.mediaItem)
    }
}

// MARK: - DTO

/// Le format des rangées de l'accueil, que le serveur réutilise tel quel.
private nonisolated struct TitleSearchResponseDTO: Decodable {
    let results: [Row]

    nonisolated struct Row: Decodable {
        let id: Int
        let title: String?
        let overview: String?
        let posterPath: String?
        let voteAverage: Double?
        let voteCount: Int?
        let genreIds: [Int]?
        let releaseDate: String?
        let mediaType: String?
        let seasonCount: Int?

        enum CodingKeys: String, CodingKey {
            case id, title, overview
            case posterPath = "poster_path"
            case voteAverage = "vote_average"
            case voteCount = "vote_count"
            case genreIds = "genre_ids"
            case releaseDate = "release_date"
            case mediaType = "media_type"
            case seasonCount = "season_count"
        }

        var mediaItem: MediaItem {
            MediaItem(
                tmdbId: id,
                mediaType: mediaType == MediaType.tv.rawValue ? .tv : .movie,
                title: title ?? String(localized: "Sans titre", bundle: .app),
                posterPath: posterPath,
                overview: overview,
                voteAverage: voteAverage,
                voteCount: voteCount,
                genreIds: genreIds ?? [],
                releaseDate: releaseDate,
                seasonCount: seasonCount
            )
        }
    }
}
