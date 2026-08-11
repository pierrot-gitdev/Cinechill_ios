//
//  BadgesClient.swift
//  Cinechill_iOS
//

import Foundation
import FirebaseAuth

protocol BadgesFetching: Sendable {
    func evaluate() async throws -> [BadgeProgress]
}

nonisolated struct BackendBadgesClient: BadgesFetching, Sendable {
    func evaluate() async throws -> [BadgeProgress] {
        guard let url = APIEndpoints.evaluateBadges() else { throw URLError(.badURL) }
        guard let user = Auth.auth().currentUser else { throw URLError(.userAuthenticationRequired) }
        let token = try await user.getIDToken()

        var request = await URLRequest(backend: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = Data("{}".utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(BadgesResponseDTO.self, from: data)
        return decoded.badges.map(\.progress)
    }
}

private struct BadgesResponseDTO: Decodable, Sendable {
    let badges: [BadgeProgressDTO]
}

private struct BadgeProgressDTO: Decodable, Sendable {
    let id: String
    let unlocked: Bool
    let unlockedAt: String?
    let current: Int
    let target: Int
    let detail: String?

    var progress: BadgeProgress {
        BadgeProgress(
            id: id,
            unlocked: unlocked,
            unlockedAt: unlockedAt.flatMap { ISO8601DateFormatter().date(from: $0) },
            current: current,
            target: target,
            detail: detail
        )
    }
}
