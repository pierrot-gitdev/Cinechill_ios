import SwiftUI

struct HomeView: View {
    @Bindable var homeModel: HomeViewModel

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 16)]

    var body: some View {
        NavigationView {
            ZStack {
                Color(.systemBackground)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        headerBlock

                        if let err = homeModel.errorMessage {
                            Text(err)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if homeModel.loading && homeModel.allItems.isEmpty {
                            ProgressView("Chargement…")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 40)
                        } else {
                            LazyVGrid(columns: columns, spacing: 16) {
                                ForEach(homeModel.displayedItems) { item in
                                    NavigationLink(value: item) {
                                        ContentCardView(item: item)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }

                            PaginationBar(
                                currentPage: homeModel.currentPage,
                                totalPages: homeModel.totalPages,
                                onPrevious: { homeModel.goToPreviousPage() },
                                onNext: { homeModel.goToNextPage() }
                            )
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Accueil")
            .navigationDestination(for: MediaItem.self) { item in
                ItemDetailView(item: item)
            }
            .task {
                await homeModel.loadMovies()
            }
        }
    }

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Découvrez des Films", systemImage: "film.stack")
                .font(.title2.weight(.bold))
            Text("Explorez les titres populaires du moment")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
