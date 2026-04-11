import SwiftUI

struct GalleryView: View {
    @Binding var selectedTab: Int
    @EnvironmentObject private var libraryStore: LibraryStore

    var body: some View {
        NavigationView {
            ZStack {
                Color(.systemBackground)
                    .ignoresSafeArea()

                if libraryStore.galleryItems.isEmpty {
                    emptyState
                        .padding()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(libraryStore.galleryItems) { entry in
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
            .navigationTitle("Ma galerie")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.stack.3d.up.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Votre galerie est vide pour le moment.")
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
