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
            case .all: String(localized: "Tous", bundle: .app)
            case .unlocked: String(localized: "Obtenus", bundle: .app)
            case .locked: String(localized: "À débloquer", bundle: .app)
            case .secret: String(localized: "Secrets", bundle: .app)
            }
        }
    }

    /// Ce qu'il y a à célébrer : un badge tout juste décroché, ou une
    /// distinction tout juste décernée. Deux causes distinctes, un seul
    /// mécanisme d'affichage, mais deux échelles de carte : c'est cette
    /// différence qui fait qu'un rang ne se confond pas avec une citation.
    enum Celebration: Identifiable, Equatable {
        case badge(Badge)
        case distinction(Distinction)

        var id: String {
            switch self {
            case .badge(let badge): "badge-\(badge.id)"
            case .distinction(let distinction): "distinction-\(distinction.rawValue)"
            }
        }
    }

    var filter: Filter = .all

    private(set) var progressByID: [String: BadgeProgress] = [:]
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    /// Célébrations en attente d'affichage, une à la fois — le sommet de la
    /// file est ce que l'écran doit montrer maintenant.
    private(set) var pendingCelebrations: [Celebration] = []

    private let client: any BadgesFetching

    /// Dernière taille de galerie connue, pour détecter le passage d'une
    /// distinction à la suivante. `nil` tant qu'aucune référence n'a été posée.
    private var lastKnownGalleryCount: Int?
    /// `true` après la toute première évaluation de la session — avant ça, on
    /// pose une référence, on ne célèbre rien : sans quoi le premier
    /// chargement ferait passer chaque badge déjà obtenu pour un déblocage
    /// à l'instant, et la distinction de départ pour une promotion.
    private var hasEstablishedBaseline = false

    init(client: any BadgesFetching = BackendBadgesClient()) {
        self.client = client
    }

    var unlockedCount: Int {
        BadgeCatalog.all.filter { progress(for: $0).unlocked }.count
    }

    var totalCount: Int { BadgeCatalog.all.count }

    var currentCelebration: Celebration? { pendingCelebrations.first }

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
            errorMessage = String(localized: "Impossible de mettre à jour tes badges.", bundle: .app)
        }
    }

    /// À appeler chaque fois que la taille de la galerie change, quelle que
    /// soit la cause (swipe, fiche film, CinéMatch…) — la galerie est le seul
    /// signal commun à tous les chemins qui peuvent décrocher un badge ou
    /// faire monter d'une distinction.
    func checkForNewAchievements(galleryCount: Int) async {
        let isFirstCheck = !hasEstablishedBaseline
        let previousDistinction = lastKnownGalleryCount.map(Distinction.distinction(for:))
        let previousProgress = progressByID

        await refresh()
        hasEstablishedBaseline = true
        lastKnownGalleryCount = galleryCount

        guard !isFirstCheck else { return }

        for badge in BadgeCatalog.all {
            let wasUnlocked = previousProgress[badge.id]?.unlocked ?? false
            let isUnlocked = progressByID[badge.id]?.unlocked ?? false
            if !wasUnlocked, isUnlocked {
                pendingCelebrations.append(.badge(badge))
            }
        }

        let newDistinction = Distinction.distinction(for: galleryCount)
        if let previousDistinction, newDistinction.rawValue > previousDistinction.rawValue {
            pendingCelebrations.append(.distinction(newDistinction))
        }
    }

    /// Referme la célébration en tête de file et laisse passer la suivante.
    func dismissCurrentCelebration() {
        guard !pendingCelebrations.isEmpty else { return }
        pendingCelebrations.removeFirst()
    }

    /// À appeler à la déconnexion : sans ça, la référence d'un compte reste
    /// active pour le suivant qui se connecterait dans la même session.
    func resetAchievementTracking() {
        lastKnownGalleryCount = nil
        hasEstablishedBaseline = false
        pendingCelebrations = []
        progressByID = [:]
    }
}
