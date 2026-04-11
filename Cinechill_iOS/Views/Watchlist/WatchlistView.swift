import SwiftUI

struct WatchlistView: View {
    @Binding var selectedTab: Int
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var libraryStore: LibraryStore

    var body: some View {
        NavigationView {
            ZStack {
                Color(.systemBackground)
                    .ignoresSafeArea()

                if libraryStore.watchlistItems.isEmpty {
                    emptyState
                        .padding()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(libraryStore.watchlistItems) { entry in
                                NavigationLink(destination: ItemDetailView(item: entry.mediaItem)) {
                                    row(for: entry.mediaItem)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Ma watchlist")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Déconnexion") {
                        do {
                            try authService.signOut()
                        } catch {
                            // Error already exposed via auth service.
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bookmark.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Votre watchlist est vide pour le moment.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Explorer l’accueil") {
                selectedTab = 0
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    private func row(for item: MediaItem) -> some View {
        HStack(spacing: 12) {
            AsyncImage(url: item.posterURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    Color.secondary.opacity(0.25)
                }
            }
            .frame(width: 54, height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.headline)
                    .lineLimit(2)
                Text("\(item.mediaType.singularLabel) · \(item.displayYear)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
