import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var profileStore: UserProfileStore
    @EnvironmentObject private var libraryStore: LibraryStore
    @EnvironmentObject private var authService: AuthService
    @Environment(\.dismiss) private var dismiss
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Color.clear.frame(height: 52)

                    profileHeader
                        .frame(maxWidth: .infinity)

                    if !libraryStore.galleryItems.isEmpty {
                        mediaSection(
                            title: "Ma Galerie",
                            items: libraryStore.galleryItems.map(\.mediaItem)
                        )
                    }

                    if !libraryStore.watchlistItems.isEmpty {
                        mediaSection(
                            title: "Ma Watchlist",
                            items: libraryStore.watchlistItems.map(\.mediaItem)
                        )
                    }

                    if libraryStore.galleryItems.isEmpty && libraryStore.watchlistItems.isEmpty {
                        emptyLibrary
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
            .navigationDestination(for: MediaItem.self) { item in
                ItemDetailView(item: item)
            }
            .navigationBarHidden(true)
            .overlay(alignment: .top) { topBar }
        }
        .sheet(isPresented: $showSettings, onDismiss: { profileStore.refresh() }) {
            SettingsView()
                .environmentObject(profileStore)
                .environmentObject(authService)
        }
        .onAppear { profileStore.refresh() }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image("close")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
            }

            Spacer()

            Text("Cinéchill")
                .font(.headline)

            Spacer()

            Button { showSettings = true } label: {
                Image("settings")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(.ultraThinMaterial)
    }

    // MARK: - Profile Header

    private var profileHeader: some View {
        VStack(spacing: 14) {
            avatarView
                .frame(width: 84, height: 84)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Color(.systemGray4), lineWidth: 2))

            Text(profileStore.displayName)
                .font(.title2.weight(.bold))

            statsRow
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var avatarView: some View {
        if let data = profileStore.avatarData, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage).resizable().scaledToFill()
        } else if let url = profileStore.avatarURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFill()
                default: avatarPlaceholder
                }
            }
        } else {
            avatarPlaceholder
        }
    }

    private var avatarPlaceholder: some View {
        Image(systemName: "person.circle.fill")
            .resizable()
            .foregroundStyle(Color(.systemGray3))
    }

    private var statsRow: some View {
        HStack(spacing: 0) {
            statItem(value: "0", label: "Following")
            Divider().frame(height: 28)
            statItem(value: "0", label: "Followers")
            Divider().frame(height: 28)
            statItem(value: "0", label: "Cinechill")
        }
    }

    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.headline.weight(.bold))
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Media Sections

    private func mediaSection(title: String, items: [MediaItem]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 24, weight: .black, design: .rounded))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(items) { item in
                        NavigationLink(value: item) {
                            ContentCardView(item: item)
                                .frame(width: 175)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    // MARK: - Empty

    private var emptyLibrary: some View {
        VStack(spacing: 12) {
            Image(systemName: "film.stack")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Votre bibliothèque est vide.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}
