import SwiftUI

struct HomeView: View {
    @Bindable var homeModel: HomeViewModel
    @EnvironmentObject private var libraryStore: LibraryStore
    @EnvironmentObject private var profileStore: UserProfileStore
    @State private var showPlatformSheet = false
    @State private var showProfile = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        if let err = homeModel.errorMessage {
                            Text(err)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if homeModel.loading && homeModel.popularTopItems.isEmpty {
                            ProgressView("Chargement…")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 30)
                        } else {
                            browseSection
                            forYouSection
                            inTheatersSection
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom)
                    .padding(.top, 32)
                }
            }
            .safeAreaInset(edge: .top) {
                AppHeaderView(onProfileTap: { showProfile = true })
                    .padding(.horizontal)
                    .padding(.top, 10)
                    .padding(.bottom, 6)
                    .background(.ultraThinMaterial)
            }
            .navigationBarHidden(true)
            .navigationDestination(for: MediaItem.self) { item in
                ItemDetailView(item: item)
            }
            .navigationDestination(for: HomeBrowseCategory.self) { category in
                GenrePopularListView(category: category, homeModel: homeModel)
            }
            .sheet(isPresented: $showPlatformSheet) {
                PlatformFilterSheet(
                    platforms: homeModel.availablePlatforms,
                    selectedIDs: libraryStore.preferredPlatformIDs
                )
                .presentationDetents([.medium, .large])
            }
            .fullScreenCover(isPresented: $showProfile) {
                ProfileView()
                    .environmentObject(profileStore)
                    .environmentObject(libraryStore)
                    .environmentObject(authService)
            }
            .task {
                await homeModel.loadHome()
                await homeModel.refreshForYou(using: libraryStore.preferredPlatformIDs)
            }
            .task(id: "\(homeModel.availablePlatforms.map(\.id).joined(separator: ","))-\(libraryStore.shouldInitializePreferredPlatforms)") {
                let allPlatformIDs = Set(homeModel.availablePlatforms.map(\.id))
                libraryStore.initializePreferredPlatformsIfNeeded(with: allPlatformIDs)
            }
            .task(id: libraryStore.preferredPlatformIDs) {
                await homeModel.refreshForYou(using: libraryStore.preferredPlatformIDs)
            }
        }
    }

    @EnvironmentObject private var authService: AuthService

    // MARK: - Browse Section

    private var browseSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                sectionTitle("Parcourir")
                Spacer()
                NavigationLink(destination: HomeGenresListView(categories: homeModel.browseCategories, homeModel: homeModel)) {
                    Image(systemName: "arrow.right")
                        .font(.headline.weight(.bold))
                        .frame(width: 32, height: 32)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHGrid(
                    rows: [GridItem(.fixed(88), spacing: 10), GridItem(.fixed(88), spacing: 10)],
                    spacing: 10
                ) {
                    ForEach(homeModel.browseCategories) { category in
                        NavigationLink(value: category) {
                            BrowseCardView(
                                title: category.title,
                                posterURL: homeModel.browsePosterURL(for: category.id)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(height: 190)
                .padding(.horizontal, 2)
            }
        }
    }

    // MARK: - For You Section

    private var forYouSection: some View {
        let filtered = homeModel.forYouItems
        let selectedPlatforms = homeModel.availablePlatforms
            .filter { libraryStore.preferredPlatformIDs.contains($0.id) }
        let displayedPlatforms = Array(selectedPlatforms.prefix(3))

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                sectionTitle("Pour vous")

                if !displayedPlatforms.isEmpty {
                    selectedPlatformShortcuts(displayedPlatforms)
                }
                Spacer()

                Button {
                    showPlatformSheet = true
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.headline.weight(.bold))
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.plain)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(filtered) { item in
                        NavigationLink(value: item) {
                            ContentCardView(item: item)
                                .frame(width: 175)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
            }

            if filtered.isEmpty {
                Text("Aucun film ne correspond à vos plateformes sélectionnées.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - In Theaters Section

    private var inTheatersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Pour vous au cinéma")
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(.secondarySystemBackground), Color(.systemGray6)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 110)
                .overlay(alignment: .leading) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Bientot disponible")
                            .font(.headline)
                        Text("Les sorties cinema seront ajoutees dans une prochaine etape.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                }
        }
    }

    // MARK: - Helpers

    private func selectedPlatformShortcuts(_ platforms: [StreamingPlatform]) -> some View {
        HStack(spacing: -6) {
            ForEach(Array(platforms.enumerated()), id: \.element.id) { index, platform in
                Group {
                    if let logoURL = platform.logoURL {
                        AsyncImage(url: logoURL) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().scaledToFit()
                            default:
                                Text(platform.shortLabel)
                                    .font(.caption2.weight(.bold))
                            }
                        }
                        .frame(width: 48, height: 30)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    } else {
                        Text(platform.shortLabel)
                            .font(.caption2.weight(.bold))
                            .frame(width: 48, height: 30)
                    }
                }
                .zIndex(Double(100 - index))
            }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 24, weight: .black, design: .rounded))
            .lineLimit(2)
            .minimumScaleFactor(0.8)
    }
}
