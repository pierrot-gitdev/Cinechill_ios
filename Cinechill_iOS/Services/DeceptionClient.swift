//
//  DeceptionClient.swift
//  Cinechill_iOS
//

import FirebaseAuth
import Foundation

/// Un film de la galerie proposé dans la planche des déceptions.
nonisolated struct DeceptionFilm: Identifiable, Hashable, Sendable, Decodable {
    /// L'identifiant de bibliothèque (`movie-603`).
    let id: String
    let tmdbId: Int
    let title: String
    let posterPath: String?
    let releaseDate: String?

    var displayYear: String {
        guard let releaseDate, releaseDate.count >= 4 else { return "—" }
        return String(releaseDate.prefix(4))
    }
}

/// Les deux appels de l'étape « Tes déceptions » : la planche, choisie par le
/// serveur sur la carte des goûts, et la réponse.
nonisolated struct DeceptionClient: Sendable {
    private struct GridResponse: Decodable {
        let films: [DeceptionFilm]
    }

    func grid() async throws -> [DeceptionFilm] {
        let data = try await post(APIEndpoints.deceptionGrid(), body: [:])
        return try JSONDecoder().decode(GridResponse.self, from: data).films
    }

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
