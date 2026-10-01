//
//  SeasonEnrichClient.swift
//  Cinechill_iOS
//

import Foundation
import FirebaseAuth

/// Le pendant de `enrichCandidates` pour les saisons de la watchlist.
///
/// À part du client des séries parce qu'il demande un compte : ce qu'il rend
/// dépend de ce que la personne a rangé, pas seulement de TMDB.
struct SeasonEnrichClient: SeasonEnriching, Sendable {
    /// Les saisons de la watchlist, à jour. Plafonné à trente par le serveur.
    func enrich(_ seasons: [(tvId: Int, season: Int)]) async throws -> [SeasonEnrichment] {
        guard !seasons.isEmpty else { return [] }
        guard let url = APIEndpoints.enrichSeasons(),
              let user = Auth.auth().currentUser else { throw TVClientError.unavailable }
        let token = try await user.getIDToken()

        var request = await URLRequest(backend: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "seasons": seasons.map { ["tvId": $0.tvId, "season": $0.season] },
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode),
              let decoded = try? JSONDecoder().decode(EnrichSeasonsDTO.self, from: data) else {
            throw TVClientError.unavailable
        }
        return decoded.seasons
    }
}

private struct EnrichSeasonsDTO: Decodable {
    let seasons: [SeasonEnrichment]
}
