//
//  TasteGridClient.swift
//  Cinechill_iOS
//

import FirebaseAuth
import Foundation

/// Un film (ou une saison) de la galerie proposé dans une planche de goût.
nonisolated struct TasteFilm: Identifiable, Hashable, Sendable, Decodable {
    /// L'identifiant de bibliothèque (`movie-603`, `tv-1399-s2`).
    let id: String
    let tmdbId: Int
    let title: String
    let posterPath: String?
    let releaseDate: String?
    let season: Int?

    var displayYear: String {
        guard let releaseDate, releaseDate.count >= 4 else { return "—" }
        return String(releaseDate.prefix(4))
    }
}

/// Les appels des planches de goût. Le serveur compose chaque page (voir
/// `getTasteGrid`) : une saga par page, plus aucune saga déjà répondue, un
/// genre par case. La réponse aux déceptions passe par `record`, celle aux
/// coups de cœur par `LibraryStore.saveLoves`.
nonisolated struct TasteGridClient: Sendable {
    private struct GridResponse: Decodable {
        let films: [TasteFilm]
    }

    /// - Parameters:
    ///   - excluding: films déjà montrés dans une planche des coups de cœur.
    func grid(kind: TasteGridKind, format: MediaFormat, excluding: [String]) async throws -> [TasteFilm] {
        let data = try await post(APIEndpoints.tasteGrid(), body: [
            "kind": kind == .loved ? "loved" : "disliked",
            "format": format == .series ? "series" : "film",
            "excludeIds": excluding,
        ])
        return try JSONDecoder().decode(GridResponse.self, from: data).films
    }

    /// La réponse à une planche des déceptions.
    ///
    /// - Parameters:
    ///   - shown: les films montrés, qui passent en revue.
    ///   - disliked: ceux qui ont été touchés, qui deviennent « Pas aimé ».
    func record(shown: [Int], disliked: [Int]) async throws {
        _ = try await post(APIEndpoints.recordDeceptionGrid(), body: [
            "shown": shown,
            "disliked": disliked,
        ])
    }

    private func post(_ url: URL?, body: [String: Any]) async throws -> Data {
        guard let url else { throw URLError(.badURL) }
        guard let user = Auth.auth().currentUser else { throw URLError(.userAuthenticationRequired) }
        let token = try await user.getIDToken()

        var request = await URLRequest(backend: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}
