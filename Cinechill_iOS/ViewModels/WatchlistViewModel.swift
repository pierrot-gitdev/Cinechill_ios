//
//  WatchlistViewModel.swift
//  Cinechill_iOS
//

import Foundation

/// Ce que la watchlist a besoin du backend : le lot enrichi, rien d'autre.
protocol CandidateEnriching: Sendable {
    func enrichCandidates(_ candidates: [CandidateRow]) async throws -> [EnrichedCandidateRow]
}

extension BackendRecommendationClient: CandidateEnriching {}

@Observable
@MainActor
final class WatchlistViewModel {
    /// Au-delà, un film n'est plus une intention mais un remords.
    private static let dormantAfterDays = 90
    /// `enrichCandidates` plafonne à 60 films, mais chacun coûte plusieurs
    /// appels TMDB côté serveur : on reste bien en dessous du plafond.
    private static let enrichBatchSize = 25
    private static let enrichmentTTL: TimeInterval = 7 * 24 * 3600

    var budget: TimeBudget = .any {
        didSet { rebuild() }
    }

    var isTriaging = false

    private(set) var items: [WatchlistItem] = []
    private(set) var groups: [WatchlistGroup] = []
    private(set) var tonight: TonightPick?
    private(set) var isEnriching = false
    /// Films écartés par le budget de temps — affiché pour que le filtre ne
    /// soit jamais silencieux.
    private(set) var hiddenByBudget = 0

    private var entries: [WatchlistEntry] = []
    private var enrichment: [Int: EnrichedCandidateRow] = [:]
    private var preferredProviderIDs: Set<Int> = []
    private var platformNames: [Int: String] = [:]
    private var rejectedTonight: Set<Int> = []

    private let client: any CandidateEnriching
    private let cache = DiskCache(
        name: "watchlist_enrich",
        defaultTTL: WatchlistViewModel.enrichmentTTL
    )

    init(client: any CandidateEnriching = BackendRecommendationClient()) {
        self.client = client
    }

    // MARK: - Entrées

    func update(
        entries: [WatchlistEntry],
        preferredPlatformIDs: Set<String>,
        platforms: [StreamingPlatform]
    ) async {
        // Les identifiants de plateformes préférées sont déjà les identifiants
        // TMDB, stockés en chaînes (voir `StreamingPlatform.curated`).
        let preferred = Set(preferredPlatformIDs.compactMap(Int.init))
        let names = Dictionary(
            platforms.map { ($0.providerID, $0.name) },
            uniquingKeysWith: { first, _ in first }
        )

        let unchanged = entries == self.entries
            && preferred == preferredProviderIDs
            && names == platformNames
        guard !unchanged else { return }

        self.entries = entries
        self.preferredProviderIDs = preferred
        self.platformNames = names
        rebuild()
        await enrichMissing()
    }

    /// Écarte la proposition courante et en calcule une autre. Le film écarté
    /// n'est pas retiré de la watchlist — il repassera au prochain tour.
    func rejectTonight() {
        guard let current = tonight else { return }
        rejectedTonight.insert(current.item.id)
        rebuild()
    }

    // MARK: - Enrichissement

    private func enrichMissing() async {
        let missing = entries.filter { enrichment[$0.tmdbId] == nil }
        guard !missing.isEmpty else { return }

        // Le cache est tenu film par film, pas par liste : ajouter un titre ne
        // doit pas obliger à réinterroger les vingt-neuf autres.
        var uncached: [WatchlistEntry] = []
        for entry in missing {
            if let row = await cachedEnrichment(id: entry.tmdbId) {
                enrichment[entry.tmdbId] = row
            } else {
                uncached.append(entry)
            }
        }
        rebuild()
        guard !uncached.isEmpty else { return }

        isEnriching = true
        defer { isEnriching = false }

        for chunk in uncached.chunked(into: Self.enrichBatchSize) {
            guard let rows = try? await client.enrichCandidates(chunk.map(\.candidateRow)) else {
                continue
            }
            for row in rows {
                enrichment[row.id] = row
                await store(row)
            }
            // Affichage progressif : chaque lot enrichit l'écran déjà visible.
            rebuild()
        }
    }

    private func cachedEnrichment(id: Int) async -> EnrichedCandidateRow? {
        guard let cached = await cache.read(for: cacheKey(id)), !cached.isExpired else { return nil }
        return try? JSONDecoder().decode(EnrichedCandidateRow.self, from: cached.data)
    }

    private func store(_ row: EnrichedCandidateRow) async {
        guard let data = try? JSONEncoder().encode(row) else { return }
        await cache.store(data, for: cacheKey(row.id))
    }

    private func cacheKey(_ id: Int) -> String { "enrich-\(id)" }

    // MARK: - Composition

    private func rebuild() {
        items = entries.map { entry in
            let enriched = enrichment[entry.tmdbId]
            return WatchlistItem(
                entry: entry,
                runtimeMinutes: enriched?.runtimeMinutes,
                providerIDs: enriched?.providerIDs ?? [],
                trailerKey: enriched?.trailerKey
            )
        }

        let withinBudget = items.filter(fitsBudget)
        hiddenByBudget = items.count - withinBudget.count

        // Ce qui vient d'un ami sort du groupement par disponibilité tant que
        // le film n'a pas été vu : la provenance prime sur la plateforme, et
        // mélanger les deux axes rendrait les deux illisibles.
        let recommended = withinBudget.filter { $0.entry.isRecommended }
        let rest = withinBudget.filter { !$0.entry.isRecommended }

        let cutoff = Date().addingTimeInterval(-Double(Self.dormantAfterDays) * 86400)
        let dormant = rest.filter { $0.entry.addedAt < cutoff }
        let recent = rest.filter { $0.entry.addedAt >= cutoff }

        let available = recent.filter { $0.isAvailable(on: preferredProviderIDs) }
        let elsewhere = recent.filter { !$0.isAvailable(on: preferredProviderIDs) }

        groups = [
            WatchlistGroup(kind: .recommended, items: recommended.sorted(by: newestRecommendationFirst)),
            WatchlistGroup(kind: .available, items: available.sorted(by: newestFirst)),
            WatchlistGroup(kind: .elsewhere, items: elsewhere.sorted(by: newestFirst)),
            // Les plus anciens d'abord : ce sont eux qu'il faut trancher.
            WatchlistGroup(kind: .dormant, items: dormant.sorted { $0.entry.addedAt < $1.entry.addedAt }),
        ].filter { !$0.items.isEmpty }

        tonight = pickTonight(from: withinBudget)
    }

    /// Une durée inconnue ne fait jamais disparaître un film : on ne peut pas
    /// affirmer qu'il dépasse le budget.
    private func fitsBudget(_ item: WatchlistItem) -> Bool {
        guard let limit = budget.maxMinutes, let runtime = item.runtimeMinutes else { return true }
        return runtime <= limit
    }

    private func newestFirst(_ lhs: WatchlistItem, _ rhs: WatchlistItem) -> Bool {
        lhs.entry.addedAt > rhs.entry.addedAt
    }

    /// Dans le groupe des recommandations, c'est la date de l'envoi qui
    /// compte, pas celle de l'ajout : les deux diffèrent quand le film était
    /// déjà dans la liste avant d'être recommandé.
    private func newestRecommendationFirst(_ lhs: WatchlistItem, _ rhs: WatchlistItem) -> Bool {
        let left = lhs.entry.recommendedBy.first?.at ?? lhs.entry.addedAt
        let right = rhs.entry.recommendedBy.first?.at ?? rhs.entry.addedAt
        return left > right
    }

    // MARK: - Proposition du soir

    private func pickTonight(from pool: [WatchlistItem]) -> TonightPick? {
        guard !pool.isEmpty else { return nil }

        var candidates = pool.filter { !rejectedTonight.contains($0.id) }
        if candidates.isEmpty {
            // Tout a été écarté : on repart d'un tour neuf plutôt que de ne
            // rien proposer.
            rejectedTonight.removeAll()
            candidates = pool
        }

        let onPreferred = candidates.filter { $0.isAvailable(on: preferredProviderIDs) }
        let shortlist = onPreferred.isEmpty ? candidates : onPreferred

        guard let best = shortlist.max(by: { score($0) < score($1) }) else { return nil }
        return TonightPick(item: best, reason: reason(for: best, among: shortlist))
    }

    /// L'ancienneté pèse plus que la note : la proposition du soir sert d'abord
    /// à ressortir ce qui dort, sinon la liste ne se vide jamais par le bas.
    private func score(_ item: WatchlistItem) -> Double {
        var value = min(1, monthsWaiting(item) / 6) * 40
        value += (item.entry.voteAverage ?? 6.5) * 4
        if item.isAvailable(on: preferredProviderIDs) { value += 15 }
        if item.runtimeMinutes != nil { value += 5 }
        // Une recommandation d'ami pèse davantage qu'une disponibilité : c'est
        // le seul signal de la liste qui vienne d'un humain.
        if item.entry.isRecommended { value += 25 }
        return value
    }

    private func reason(for item: WatchlistItem, among pool: [WatchlistItem]) -> String {
        // La provenance passe avant tout le reste : « quelqu'un que vous
        // suivez vous l'a conseillé » est l'argument le plus fort dont
        // dispose cet écran, et celui qu'aucun calcul ne peut produire.
        if let recommender = item.entry.recommendedBy.first {
            let others = item.entry.recommendedBy.count - 1
            if others > 0 {
                return "Recommandé par \(recommender.displayName) et \(others) autre\(others > 1 ? "s" : "")."
            }
            return "Recommandé par \(recommender.displayName)."
        }

        let months = Int(monthsWaiting(item))
        if months >= 3 {
            return "Dans votre liste depuis \(months) mois."
        }
        if let runtime = item.runtimeMinutes,
           let shortest = pool.compactMap(\.runtimeMinutes).min(),
           runtime == shortest, pool.count > 2 {
            return "Le plus court de ce qui rentre dans votre soirée."
        }
        if let platform = preferredPlatformName(for: item) {
            return "Sur \(platform), vous pouvez le lancer tout de suite."
        }
        if let rating = item.entry.voteAverage, rating >= 8 {
            return "Le mieux noté de votre liste."
        }
        return "Il attend son tour depuis un moment."
    }

    private func preferredPlatformName(for item: WatchlistItem) -> String? {
        item.providerIDs
            .first { preferredProviderIDs.contains($0) }
            .flatMap { platformNames[$0] }
    }

    private func monthsWaiting(_ item: WatchlistItem) -> Double {
        max(0, Date().timeIntervalSince(item.entry.addedAt) / (30 * 86400))
    }
}

// MARK: - Passerelles

extension WatchlistEntry {
    /// Le schéma qu'attend `enrichCandidates`. `voteCount`, `popularity` et
    /// `originCountry` ne sont pas stockés côté watchlist et ne servent pas à
    /// l'enrichissement — seul l'identifiant compte réellement.
    var candidateRow: CandidateRow {
        CandidateRow(
            id: tmdbId,
            title: title,
            overview: overview,
            posterPath: posterPath,
            voteAverage: voteAverage,
            voteCount: nil,
            popularity: nil,
            genreIds: genreIds,
            releaseDate: releaseDate,
            originCountry: []
        )
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}
