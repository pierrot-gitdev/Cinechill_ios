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
            availablePlatforms = curatedPlatforms(from: providers)
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

    private func curatedPlatforms(from providers: [TMDBWatchProvider]) -> [StreamingPlatform] {
        struct PlatformRule {
            let displayName: String
            let aliases: [String]
        }

        let rules: [PlatformRule] = [
            PlatformRule(displayName: "Netflix", aliases: ["netflix"]),
            PlatformRule(displayName: "Prime Video", aliases: ["primevideo", "amazonprimevideo"]),
            PlatformRule(displayName: "Disney +", aliases: ["disneyplus", "disney+"]),
            PlatformRule(displayName: "Pathé Home", aliases: ["pathehome", "pathéhome"]),
            PlatformRule(displayName: "Canal +", aliases: ["canal+", "canalplus"]),
            PlatformRule(displayName: "Apple TV", aliases: ["appletv", "appletvplus"]),
            PlatformRule(displayName: "HBO Max", aliases: ["hbomax", "max"]),
            PlatformRule(displayName: "Paramount +", aliases: ["paramount+", "paramountplus"]),
            PlatformRule(displayName: "Arte", aliases: ["arte"]),
            PlatformRule(displayName: "TF1", aliases: ["tf1plus"]),
            PlatformRule(displayName: "Molotov TV", aliases: ["molotovtv", "molotov"])
        ]

        let normalizedProviders = providers.map { provider in
            (provider, normalize(provider.providerName))
        }

        var curated: [StreamingPlatform] = []
        for rule in rules {
            let ruleAliases = Set(rule.aliases.map(normalize))
            if let matched = normalizedProviders.first(where: { _, normalizedName in
                ruleAliases.contains(normalizedName)
            })?.0 {
                curated.append(
                    StreamingPlatform(
                        id: String(matched.providerID),
                        providerID: matched.providerID,
                        name: rule.displayName,
                        logoPath: matched.logoPath
                    )
                )
            }
        }

        return curated
    }

    private func normalize(_ raw: String) -> String {
        raw
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "[^a-z0-9+]", with: "", options: .regularExpression)
    }
}
