//
//  BadgesViewModel.swift
//  Cinechill_iOS
//

import Foundation

@Observable
@MainActor
final class BadgesViewModel {
    enum Filter: String, CaseIterable, Identifiable {
        case all, unlocked, locked, secret
        var id: String { rawValue }

        var label: String {
            switch self {
            case .all: "Tous"
            case .unlocked: "Obtenus"
            case .locked: "À débloquer"
            case .secret: "Secrets"
            }
        }
    }

    var filter: Filter = .all

    private(set) var progressByID: [String: BadgeProgress] = [:]
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private let client: any BadgesFetching

    init(client: any BadgesFetching = BackendBadgesClient()) {
        self.client = client
    }

    var unlockedCount: Int {
        BadgeCatalog.all.filter { progress(for: $0).unlocked }.count
    }

    var totalCount: Int { BadgeCatalog.all.count }

    /// Les badges obtenus, les plus récents d'abord — c'est ce qu'on montre en
    /// vitrine sur le profil.
    var showcase: [Badge] {
        BadgeCatalog.all
            .filter { progress(for: $0).unlocked }
            .sorted { left, right in
                let l = progress(for: left).unlockedAt ?? .distantPast
                let r = progress(for: right).unlockedAt ?? .distantPast
                return l > r
            }
    }

    var filteredBadges: [Badge] {
        BadgeCatalog.all.filter { badge in
            let state = progress(for: badge)
            switch filter {
            case .all: return true
            case .unlocked: return state.unlocked
            case .locked: return !state.unlocked
            case .secret: return badge.isSecret
            }
        }
    }

    func progress(for badge: Badge) -> BadgeProgress {
        progressByID[badge.id] ?? .locked(id: badge.id)
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let states = try await client.evaluate()
            progressByID = Dictionary(
                states.map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            errorMessage = nil
        } catch {
            errorMessage = "Impossible de mettre à jour vos badges."
        }
    }
}
