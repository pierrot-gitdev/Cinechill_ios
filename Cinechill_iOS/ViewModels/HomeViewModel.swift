//
//  HomeViewModel.swift
//  Cinechill_iOS
//

import Foundation

@Observable
@MainActor
final class HomeViewModel {
    private let repository: PopularRepository

    var loading = false
    var errorMessage: String?
    var allItems: [MediaItem] = []
    var currentPage = 1

    var displayedItems: [MediaItem] {
        PopularPagination.slice(page: currentPage, from: allItems)
    }

    var totalPages: Int {
        PopularPagination.totalPages(for: allItems.count)
    }

    init(repository: PopularRepository) {
        self.repository = repository
    }

    func loadMovies() async {
        loading = true
        errorMessage = nil
        defer { loading = false }
        do {
            let items = try await repository.loadPopularShuffled(for: .movie)
            allItems = items
            currentPage = 1
        } catch {
            if error is CancellationError { return }
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            allItems = []
        }
    }

    func goToPreviousPage() {
        setPage(currentPage - 1)
    }

    func goToNextPage() {
        setPage(currentPage + 1)
    }

    func setPage(_ page: Int) {
        let tp = PopularPagination.totalPages(for: allItems.count)
        currentPage = min(max(1, page), tp)
    }
}
