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
    private let rowsClient: any HomeRowsFetching

    var loading = false
    /// Tout est arrivé au moins une fois — c'est ce qui lève le spinner, pour
    /// qu'un rafraîchissement ultérieur ne rejette pas l'écran en chargement.
    private(set) var hasLoadedOnce = false
    var errorMessage: String?
    var popularItems: [MediaItem] = []
    var browseCategories: [HomeBrowseCategory] = []
    var browsePosterByGenreID: [Int: URL] = [:]
    var availablePlatforms: [StreamingPlatform] = []
    private(set) var bannedGenreIDs: Set<Int> = []

    /// Les trois rangées personnalisées, chargées en un appel.
    private(set) var rows = HomeRows.empty

    /// Listes telles que renvoyées par le backend, avant exclusion des genres
    /// bannis — pour que changer ce réglage ne coûte pas un aller-retour réseau.
    private var rawPopularItems: [MediaItem] = []
    private var rawBrowseCategories: [HomeBrowseCategory] = []

    /// Les plateformes du dernier chargement de « populaire ».
    ///
    /// L'écran est préchargé pendant l'ouverture de l'app, puis la vue redemande la même liste
    /// en apparaissant : sans cette mémoire, chaque lancement payait un aller-retour pour un
    /// résultat déjà en main. Elle sert aussi quand on coche puis décoche une plateforme.
    private var loadedPopularProviderIDs: [Int]?

    init(
        repository: PopularRepository,
        metadataClient: any HomeMetadataFetching,
        rowsClient: any HomeRowsFetching = BackendHomeRowsClient()
    ) {
        self.repository = repository
        self.metadataClient = metadataClient
        self.rowsClient = rowsClient
    }

    /// Le préchargement de l'ouverture et l'apparition de l'écran demandent tous deux le
    /// chargement ; il ne doit avoir lieu qu'une fois. `loading` couvre le cas où le
    /// préchargement est encore en vol, `hasLoadedOnce` celui où il a déjà abouti.
    func loadAllIfNeeded(preferredPlatformIDs: Set<String>) async {
        guard !hasLoadedOnce else { return }
        await loadAll(preferredPlatformIDs: preferredPlatformIDs)
    }

    /// Charge tout l'écran d'un bloc.
    ///
    /// Les rangées personnalisées et le socle partent ensemble mais
    /// n'arrivent pas à la même vitesse ; les afficher au fil de l'eau donnait
    /// un écran qui se remplissait par morceaux pendant une à deux secondes.
    /// `hasLoadedOnce` ne bascule qu'une fois tout arrivé.
    func loadAll(preferredPlatformIDs: Set<String>) async {
        guard !loading else { return }
        loading = true
        errorMessage = nil

        // Les rangées sont indépendantes du socle et partent en parallèle ;
        // « populaire » attend les plateformes, que seul le socle connaît.
        async let rowsTask: Void = loadRows()
        await loadHome()
        await refreshPopular(using: preferredPlatformIDs)
        await rowsTask

        loading = false
        hasLoadedOnce = true
    }

    /// Charge le socle de l'écran. La liste « populaire » n'est volontairement
    /// pas chargée ici : elle dépend des plateformes déclarées et appartient à
    /// `refreshPopular`, qui est appelé juste après — la charger deux fois était
    /// un aller-retour réseau gaspillé dès qu'une plateforme était déclarée.
    private func loadHome() async {
        errorMessage = nil
        do {
            async let genresTask = metadataClient.movieGenres()
            async let providersTask = metadataClient.movieProviders()

            let genres = try await genresTask
            rawBrowseCategories = genres.map { HomeBrowseCategory(id: $0.id, title: $0.name) }
            browseCategories = rawBrowseCategories.filter { !bannedGenreIDs.contains($0.id) }
            await preloadBrowsePosters()

            let providers = try await providersTask
            availablePlatforms = StreamingPlatform.curated(from: providers)
        } catch {
            if error is CancellationError { return }
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            browseCategories = []
            browsePosterByGenreID = [:]
            availablePlatforms = []
        }
    }

    /// Les rangées personnalisées échouent sans faire échouer l'écran : le
    /// reste de l'accueil reste utilisable si le backend ne répond pas.
    private func loadRows() async {
        guard let fetched = try? await rowsClient.fetchHomeRows() else { return }
        rows = fetched
    }

    func loadTopForCategory(_ category: HomeBrowseCategory) async throws -> [MediaItem] {
        let items = try await repository.loadPopularTop(
            for: .movie,
            limit: 50,
            genreID: category.id,
            providerIDs: []
        )
        return filteringBannedGenres(items)
    }

    func refreshPopular(using selectedPlatformIDs: Set<String>) async {
        // Aucune plateforme déclarée ne veut pas dire « aucun résultat » :
        // la liste vide se traduit naturellement en « pas de filtre ».
        let providerIDs = availablePlatforms
            .filter { selectedPlatformIDs.contains($0.id) }
            .map(\.providerID)
            .sorted()
        guard providerIDs != loadedPopularProviderIDs else { return }

        do {
            rawPopularItems = try await repository.loadPopularTop(
                for: .movie,
                limit: 50,
                genreID: nil,
                providerIDs: providerIDs
            )
            popularItems = filteringBannedGenres(rawPopularItems)
            loadedPopularProviderIDs = providerIDs
        } catch {
            if error is CancellationError { return }
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            rawPopularItems = []
            popularItems = []
            loadedPopularProviderIDs = nil
        }
    }

    /// Applique les genres bannis déclarés dans les réglages. Les listes brutes
    /// sont conservées pour pouvoir défaire l'exclusion sans rappeler le réseau.
    func applyBannedGenres(_ ids: Set<Int>) {
        guard ids != bannedGenreIDs else { return }
        bannedGenreIDs = ids
        popularItems = filteringBannedGenres(rawPopularItems)
        browseCategories = rawBrowseCategories.filter { !ids.contains($0.id) }
    }

    func filteringBannedGenres(_ items: [MediaItem]) -> [MediaItem] {
        guard !bannedGenreIDs.isEmpty else { return items }
        return items.filter { item in
            !item.genreIds.contains(where: { bannedGenreIDs.contains($0) })
        }
    }

    func browsePosterURL(for genreID: Int) -> URL? {
        browsePosterByGenreID[genreID]
    }

    /// Choisit l'affiche qui illustre chaque genre dans « Parcourir ».
    ///
    /// Les genres sont interrogés en parallèle : en série, dix-neuf
    /// allers-retours retardaient à eux seuls l'affichage de tout l'écran.
    private func preloadBrowsePosters() async {
        let categories = browseCategories
        guard !categories.isEmpty else { return }

        var itemsByGenre: [Int: [MediaItem]] = [:]
        await withTaskGroup(of: (Int, [MediaItem]).self) { group in
            for category in categories {
                group.addTask { [repository] in
                    let items = (try? await repository.loadPopularTop(
                        for: .movie,
                        limit: 20,
                        genreID: category.id,
                        providerIDs: []
                    )) ?? []
                    return (category.id, items)
                }
            }
            for await (genreID, items) in group {
                itemsByGenre[genreID] = items
            }
        }

        // Un même film appartient souvent à trois ou quatre genres : sans
        // mémoire des affiches déjà retenues, le même visuel illustrait
        // plusieurs cartes d'affilée.
        var usedMovieIDs: Set<Int> = []
        var collected: [Int: URL] = [:]

        for category in categories {
            let candidate = (itemsByGenre[category.id] ?? [])
                .filter { $0.posterURL != nil && !usedMovieIDs.contains($0.tmdbId) }
                .max { ($0.voteAverage ?? 0) < ($1.voteAverage ?? 0) }

            guard let candidate, let url = candidate.posterURL else { continue }
            usedMovieIDs.insert(candidate.tmdbId)
            collected[category.id] = url
        }

        browsePosterByGenreID = collected
    }
}
