//
//  PopularRepository.swift
//  Cinechill_iOS
//

import Foundation

protocol PopularPageFetching: Sendable {
    func popularPage(mediaType: MediaType, page: Int) async throws -> TMDBPagedResults
}

/// Récupère jusqu’à 300 titres (15 × 20), mélange, pagination locale par 20.
actor PopularRepository {
    private let maxItems = 300
    private let maxPages: Int
    private let pageDelayNanoseconds: UInt64

    private var memoryCache: [MediaType: [MediaItem]] = [:]

    private let client: any PopularPageFetching

    init(client: any PopularPageFetching, pageDelayMilliseconds: UInt64 = 100) {
        self.client = client
        self.maxPages = (maxItems + 19) / 20
        self.pageDelayNanoseconds = pageDelayMilliseconds * 1_000_000
    }

    func cachedItems(for type: MediaType) -> [MediaItem]? {
        memoryCache[type]
    }

    func invalidateCache(for type: MediaType) {
        memoryCache[type] = nil
    }

    func loadPopularShuffled(for type: MediaType) async throws -> [MediaItem] {
        if let hit = memoryCache[type] { return hit }

        var combined: [MediaItem] = []
        combined.reserveCapacity(maxItems)

        for page in 1 ... maxPages {
            let paged = try await client.popularPage(mediaType: type, page: page)
            for row in paged.results {
                combined.append(MediaItem(tmdbListRow: row, mediaType: type))
                if combined.count >= maxItems { break }
            }
            if paged.results.isEmpty || combined.count >= maxItems { break }
            if page < maxPages {
                try await Task.sleep(nanoseconds: pageDelayNanoseconds)
            }
        }

        if combined.count > maxItems {
            combined = Array(combined.prefix(maxItems))
        }

        let shuffled = CollectionShuffle.shuffledCopy(combined)
        memoryCache[type] = shuffled
        return shuffled
    }
}

enum PopularPagination {
    static let pageSize = 20

    static func totalPages(for itemCount: Int) -> Int {
        max(1, Int(ceil(Double(itemCount) / Double(pageSize))))
    }

    static func slice(page: Int, from items: [MediaItem]) -> [MediaItem] {
        slicePage(page: page, items: items)
    }

    /// Pagination locale générique (galerie, watchlist, etc.).
    static func slicePage<T>(page: Int, items: [T]) -> [T] {
        let p = min(max(1, page), totalPages(for: items.count))
        let start = (p - 1) * pageSize
        let end = min(start + pageSize, items.count)
        guard start < items.count else { return [] }
        return Array(items[start ..< end])
    }
}
