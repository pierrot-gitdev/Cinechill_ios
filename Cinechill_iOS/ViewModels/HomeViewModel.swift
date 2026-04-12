//
//  HomeViewModel.swift
//  Cinechill_iOS
//

import Foundation

@Observable
@MainActor
final class HomeViewModel {
    private let repository: PopularRepository
    private let metadataClient: any HomeMetadataFetching

    var loading = false
    var errorMessage: String?
    var popularTopItems: [MediaItem] = []
    var forYouItems: [MediaItem] = []
    var browseCategories: [HomeBrowseCategory] = []
    var browsePosterByGenreID: [Int: URL] = [:]
    var availablePlatforms: [StreamingPlatform] = []

    init(repository: PopularRepository, metadataClient: any HomeMetadataFetching) {
        self.repository = repository
        self.metadataClient = metadataClient
    }

    func loadHome() async {
        loading = true
        errorMessage = nil
        defer { loading = false }
        do {
            async let topTask = repository.loadPopularTop(for: .movie, limit: 50, genreID: nil, providerIDs: [])
            async let genresTask = metadataClient.movieGenres()
            async let providersTask = metadataClient.movieProviders()

            popularTopItems = try await topTask
            forYouItems = popularTopItems

            let genres = try await genresTask
            browseCategories = genres.map { HomeBrowseCategory(id: $0.id, title: $0.name) }
            await preloadBrowsePosters()

            let providers = try await providersTask
            availablePlatforms = providers.map {
                StreamingPlatform(
                    id: String($0.providerID),
                    providerID: $0.providerID,
                    name: $0.providerName,
                    logoPath: $0.logoPath
                )
            }
        } catch {
            if error is CancellationError { return }
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            popularTopItems = []
            forYouItems = []
            browseCategories = []
            browsePosterByGenreID = [:]
            availablePlatforms = []
        }
    }

    func loadTopForCategory(_ category: HomeBrowseCategory) async throws -> [MediaItem] {
        try await repository.loadPopularTop(
            for: .movie,
            limit: 50,
            genreID: category.id,
            providerIDs: []
        )
    }

    func refreshForYou(using selectedPlatformIDs: Set<String>) async {
        do {
            let providerIDs = availablePlatforms
                .filter { selectedPlatformIDs.contains($0.id) }
                .map(\.providerID)
            forYouItems = try await repository.loadPopularTop(
                for: .movie,
                limit: 50,
                genreID: nil,
                providerIDs: providerIDs
            )
        } catch {
            if error is CancellationError { return }
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            forYouItems = []
        }
    }

    func browsePosterURL(for genreID: Int) -> URL? {
        browsePosterByGenreID[genreID]
    }

    private func preloadBrowsePosters() async {
        var collected: [Int: URL] = [:]

        for category in browseCategories {
            do {
                // Fetch genre items and pick the highest TMDB rating among those with posters.
                let items = try await repository.loadPopularTop(
                    for: .movie,
                    limit: 20,
                    genreID: category.id,
                    providerIDs: []
                )
                if let best = items
                    .filter({ $0.posterURL != nil })
                    .max(by: { ($0.voteAverage ?? 0) < ($1.voteAverage ?? 0) }),
                   let url = best.posterURL {
                    collected[category.id] = url
                }
            } catch {
                if error is CancellationError { return }
                continue
            }
        }

        browsePosterByGenreID = collected
    }
}
