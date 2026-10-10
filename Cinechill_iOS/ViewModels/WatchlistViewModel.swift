//
//  WatchlistViewModel.swift
//  Cinechill_iOS
//

import Foundation

/// Ce que la watchlist a besoin du backend : le lot enrichi, rien d'autre.
protocol CandidateEnriching: Sendable {
    func enrichCandidates(_ candidates: [CandidateRow], audience: Audience?) async throws -> [EnrichedCandidateRow]
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
    /// Une saison en cours de diffusion change de semaine en semaine : ce
    /// qu'on sait d'elle vieillit bien plus vite que la durée d'un film.
    private static let seasonEnrichmentTTL: TimeInterval = 12 * 3600
    /// Le plafond de `enrichSeasons`.
    private static let seasonBatchSize = 30

    var budget: TimeBudget = .any {
        didSet { rebuild() }
    }

    var isTriaging = false

    private(set) var items: [WatchlistItem] = []
    private(set) var groups: [WatchlistGroup] = []
    private(set) var tonight: TonightPick?
    /// Faux quand un seul film peut se lancer ce soir : « Autre chose » ne
    /// ferait que reproposer le même.
    private(set) var tonightHasAlternative = false
    private(set) var isEnriching = false
    /// Films écartés par le budget de temps — affiché pour que le filtre ne
    /// soit jamais silencieux.
    private(set) var hiddenByBudget = 0

    private var entries: [WatchlistEntry] = []
    /// Films seulement, par `tmdbId` : `enrichCandidates` lit des fiches de
    /// films, et une série qui y passerait rendrait la durée du film qui porte
    /// le même identifiant.
    private var enrichment: [Int: EnrichedCandidateRow] = [:]
    /// Saisons seulement, par identifiant de bibliothèque.
    private var seasonEnrichment: [String: SeasonEnrichment] = [:]
    private var preferredProviderIDs: Set<Int> = []
    private var platformNames: [Int: String] = [:]
    private var rejectedTonight: Set<String> = []

    private let client: any CandidateEnriching
    private let seasonClient: any SeasonEnriching
    private let cache = DiskCache(
        name: "watchlist_enrich",
        defaultTTL: WatchlistViewModel.enrichmentTTL
    )
    private let seasonCache = DiskCache(
        name: "watchlist_seasons",
        defaultTTL: WatchlistViewModel.seasonEnrichmentTTL
    )

    init(
        client: any CandidateEnriching = BackendRecommendationClient(),
        seasonClient: any SeasonEnriching = SeasonEnrichClient()
    ) {
        self.client = client
        self.seasonClient = seasonClient
    }

    // MARK: - Entrées

    func update(
        entries: [WatchlistEntry],
        preferredPlatformIDs: Set<String>,
        platforms: [StreamingPlatform]
    ) async {
        guard prepare(entries: entries, preferredPlatformIDs: preferredPlatformIDs, platforms: platforms) else { return }
        await enrichMissing()
    }

    /// La partie immédiate de `update` : ranger ce qu'on sait déjà. Appelée
    /// aussi à l'apparition de la vue, pour que la première image soit déjà la
    /// liste rangée et non une liste vide qui se remplit.
    ///
    /// - Returns: `false` si rien n'a changé.
    @discardableResult
    func prepare(
        entries: [WatchlistEntry],
        preferredPlatformIDs: Set<String>,
        platforms: [StreamingPlatform]
    ) -> Bool {
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
        guard !unchanged else { return false }

        self.entries = entries
        self.preferredProviderIDs = preferred
        self.platformNames = names
        rebuild()
        return true
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
        await enrichMissingSeasons()

        let missing = entries.filter { !$0.isSeason && enrichment[$0.tmdbId] == nil }
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
            guard let rows = try? await client.enrichCandidates(chunk.map(\.candidateRow), audience: nil) else {
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

    /// Les saisons, par leur propre point d'accès et leur propre cache. Même
    /// affichage progressif que les films : chaque lot enrichit l'écran visible.
    private func enrichMissingSeasons() async {
        let missing = entries.filter { $0.isSeason && seasonEnrichment[$0.id] == nil }
        guard !missing.isEmpty else { return }

        var uncached: [WatchlistEntry] = []
        for entry in missing {
            if let cached = await seasonCache.read(for: entry.id), !cached.isExpired,
               let row = try? JSONDecoder().decode(SeasonEnrichment.self, from: cached.data) {
                seasonEnrichment[entry.id] = row
            } else {
                uncached.append(entry)
            }
        }
        rebuild()
        guard !uncached.isEmpty else { return }

        isEnriching = true
        defer { isEnriching = false }

        for chunk in uncached.chunked(into: Self.seasonBatchSize) {
            let wanted = chunk.compactMap { entry in
                entry.seasonFacts.map { (tvId: entry.tmdbId, season: $0.season) }
            }
            guard let rows = try? await seasonClient.enrich(wanted) else { continue }
            for row in rows {
                let key = "tv-\(row.tvId)-s\(row.season)"
                seasonEnrichment[key] = row
                if let data = try? JSONEncoder().encode(row) {
                    await seasonCache.store(data, for: key)
                }
            }
            rebuild()
        }
    }

    // MARK: - Composition

    private func rebuild() {
        items = entries.map { entry in
            if let facts = entry.seasonFacts {
                // Ce qu'on a rafraîchi passe devant ce qui a été rangé : la
                // saison a pu sortir un épisode depuis.
                let fresh = seasonEnrichment[entry.id]
                return WatchlistItem(
                    entry: entry,
                    runtimeMinutes: fresh?.episodeRuntime ?? facts.episodeRuntime,
                    providerIDs: fresh?.providerIds ?? facts.providerIds,
                    trailerKey: fresh?.trailerKey,
                    airedEpisodes: fresh?.airedEpisodes ?? facts.airedEpisodes,
                    nextAirDate: fresh?.nextAirDate ?? facts.nextAirDate
                )
            }
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

        // La carte du soir est la ligne promue de son film : elle ne se
        // répète pas plus bas dans les groupes.
        tonight = pickTonight(from: withinBudget)
        let listed = withinBudget.filter { $0.id != tonight?.item.id }

        // Ce qui vient d'un ami sort du groupement par disponibilité tant que
        // le film n'a pas été vu : la provenance prime sur la plateforme, et
        // mélanger les deux axes rendrait les deux illisibles.
        let recommended = listed.filter { $0.entry.isRecommended }
        // Une saison qui attend son épisode passe avant tout le reste du
        // rangement par disponibilité, y compris l'ancienneté : la saison 3
        // annoncée pour janvier n'a rien d'un remords, elle attend sa date.
        let awaiting = listed.filter { !$0.entry.isRecommended && $0.isAwaitingEpisode }
        let rest = listed.filter { !$0.entry.isRecommended && !$0.isAwaitingEpisode }

        let cutoff = Date().addingTimeInterval(-Double(Self.dormantAfterDays) * 86400)
        let dormant = rest.filter { $0.entry.addedAt < cutoff }
        let recent = rest.filter { $0.entry.addedAt >= cutoff }

        let hasPlatforms = !preferredProviderIDs.isEmpty
        let undeclared = hasPlatforms ? [] : recent
        let available = hasPlatforms ? recent.filter { $0.isAvailable(on: preferredProviderIDs) } : []
        let elsewhere = hasPlatforms ? recent.filter { !$0.isAvailable(on: preferredProviderIDs) } : []

        groups = [
            WatchlistGroup(kind: .recommended, items: recommended.sorted(by: newestRecommendationFirst)),
            WatchlistGroup(kind: .undeclared, items: undeclared.sorted(by: newestFirst)),
            WatchlistGroup(kind: .available, items: available.sorted(by: newestFirst)),
            WatchlistGroup(kind: .elsewhere, items: elsewhere.sorted(by: newestFirst)),
            // La date la plus proche d'abord : c'est ce qui sortira en premier.
            WatchlistGroup(kind: .awaiting, items: awaiting.sorted {
                ($0.nextAirDate ?? "9999") < ($1.nextAirDate ?? "9999")
            }),
            // Les plus anciens d'abord : ce sont eux qu'il faut trancher.
            WatchlistGroup(kind: .dormant, items: dormant.sorted { $0.entry.addedAt < $1.entry.addedAt }),
        ].filter { !$0.items.isEmpty }
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

        // On ne propose pas ce soir un épisode qui sort vendredi.
        let launchable = pool.filter { !$0.isAwaitingEpisode }
        tonightHasAlternative = launchable.count > 1
        guard !launchable.isEmpty else { return nil }

        var candidates = launchable.filter { !rejectedTonight.contains($0.id) }
        if candidates.isEmpty {
            // Tout a été écarté : on repart d'un tour neuf plutôt que de ne
            // rien proposer.
            rejectedTonight.removeAll()
            candidates = launchable
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
                return others == 1
                    ? String(localized: "Recommandé par \(recommender.displayName) et \(others) autre.", bundle: .app)
                    : String(localized: "Recommandé par \(recommender.displayName) et \(others) autres.", bundle: .app)
            }
            return String(localized: "Recommandé par \(recommender.displayName).", bundle: .app)
        }

        // Une saison qu'on a commencée se reprend là où on l'a laissée : c'est
        // la raison la plus simple qu'un écran puisse donner.
        if item.entry.isSeason, let next = item.entry.nextEpisode, next > 1 {
            return String(localized: "Tu en es à l'épisode \(next).", bundle: .app)
        }

        let months = Int(monthsWaiting(item))
        if months >= 3 {
            return String(localized: "Dans ta liste depuis \(months) mois.", bundle: .app)
        }
        if let runtime = item.runtimeMinutes,
           let shortest = pool.compactMap(\.runtimeMinutes).min(),
           runtime == shortest, pool.count > 2 {
            return String(localized: "Le plus court de ta liste qui rentre dans ton temps.", bundle: .app)
        }
        if let platform = preferredPlatformName(for: item) {
            return String(localized: "Sur \(platform), tu peux le lancer tout de suite.", bundle: .app)
        }
        if let rating = item.entry.voteAverage, rating >= 8 {
            return String(localized: "Le mieux noté de ta liste.", bundle: .app)
        }
        return String(localized: "Il est dans ta liste depuis un moment.", bundle: .app)
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
