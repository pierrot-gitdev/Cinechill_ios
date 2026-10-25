//
//  PopularRepository.swift
//  Cinechill_iOS
//

import Foundation

protocol PopularPageFetching: Sendable {
    func popularPage(
        mediaType: MediaType,
        page: Int,
        genreID: Int?,
        providerIDs: [Int]
    ) async throws -> TMDBPagedResults
}

/// Récupère les titres les mieux classés d'une catégorie, page par page, et les
/// garde en mémoire le temps de la session.
///
/// Le dépôt savait aussi charger 300 titres et les mélanger localement, pour une
/// pagination par 20 qui a disparu avec la barre de pagination. Ne restait qu'un
/// second cache, un second chemin de chargement et un mélange de Fisher–Yates
/// que plus personne n'appelait.
actor PopularRepository {
    private let maxItems = 300
    private let maxPages: Int
    private let pageDelayNanoseconds: UInt64

    /// `limit` : la taille demandée quand la liste a été chargée. Une liste
    /// filtrée par plateformes compte souvent moins de films que demandé ;
    /// jugée sur son seul nombre de films, elle n'était jamais servie du cache
    /// et repartait à chaque retour sur l'écran.
    private var topCache: [String: (items: [MediaItem], limit: Int)] = [:]

    private let client: any PopularPageFetching

    init(client: any PopularPageFetching, pageDelayMilliseconds: UInt64 = 100) {
        self.client = client
        self.maxPages = (maxItems + 19) / 20
        self.pageDelayNanoseconds = pageDelayMilliseconds * 1_000_000
    }

    func loadPopularTop(
        for type: MediaType,
        limit: Int = 50,
        genreID: Int? = nil,
        providerIDs: [Int] = []
    ) async throws -> [MediaItem] {
        let normalizedProviderIDs = providerIDs.sorted()
        let key = topCacheKey(mediaType: type, genreID: genreID, providerIDs: normalizedProviderIDs)
        if let hit = topCache[key], hit.limit >= limit || hit.items.count >= limit {
            return Array(hit.items.prefix(limit))
        }

        var combined: [MediaItem] = []
        combined.reserveCapacity(maxItems)
        // Deux pages qui se recouvrent (le classement bouge entre deux appels)
        // donnaient deux fois le même film, et deux cellules au même identifiant.
        var seen = Set<Int>()

        let requiredPages = max(1, (limit + 19) / 20)
        let targetPages = min(maxPages, requiredPages + 1)

        for page in 1 ... targetPages {
            let paged = try await client.popularPage(
                mediaType: type,
                page: page,
                genreID: genreID,
                providerIDs: normalizedProviderIDs
            )
            for row in paged.results where seen.insert(row.id).inserted {
                combined.append(MediaItem(tmdbListRow: row, mediaType: type))
                if combined.count >= limit { break }
            }
            if paged.results.isEmpty || combined.count >= limit { break }
            if page < targetPages {
                try await Task.sleep(nanoseconds: pageDelayNanoseconds)
            }
        }

        let top = Array(combined.prefix(limit))
        topCache[key] = (top, limit)
        return top
    }

    private nonisolated func topCacheKey(mediaType: MediaType, genreID: Int?, providerIDs: [Int]) -> String {
        let providers = providerIDs.map(String.init).joined(separator: ",")
        let genre = genreID.map(String.init) ?? "none"
        return "\(mediaType.rawValue)|\(genre)|\(providers)"
    }
}
