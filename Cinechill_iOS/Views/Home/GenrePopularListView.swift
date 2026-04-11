import SwiftUI

struct GenrePopularListView: View {
    let category: HomeBrowseCategory
    let homeModel: HomeViewModel
    @State private var items: [MediaItem] = []
    @State private var loading = false
    @State private var errorMessage: String?

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        Group {
            if loading {
                ProgressView("Chargement…")
            } else if let errorMessage {
                ContentUnavailableView(
                    "Erreur",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else if items.isEmpty {
                ContentUnavailableView(
                    "Aucun film pour cette categorie",
                    systemImage: "film",
                    description: Text("Essayez une autre categorie.")
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(items) { item in
                            NavigationLink(value: item) {
                                ContentCardView(item: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.large)
        .task(id: category.id) {
            loading = true
            errorMessage = nil
            defer { loading = false }
            do {
                items = try await homeModel.loadTopForCategory(category)
            } catch {
                if error is CancellationError { return }
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                items = []
            }
        }
    }
}

