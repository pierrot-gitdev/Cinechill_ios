import SwiftUI

struct HomeView: View {
    @Bindable var homeModel: HomeViewModel
    @EnvironmentObject private var libraryStore: LibraryStore
    @State private var showPlatformSheet = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        homeTopBar

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
                    .padding()
                }
            }
            .navigationTitle("")
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
            .task {
                await homeModel.loadHome()
                await homeModel.refreshForYou(using: libraryStore.preferredPlatformIDs)
            }
            .task(id: libraryStore.preferredPlatformIDs) {
                await homeModel.refreshForYou(using: libraryStore.preferredPlatformIDs)
            }
        }
    }

    private var homeTopBar: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                CircleIconButton(systemImage: "chevron.left", action: {})
                Spacer()
                CircleIconButton(systemImage: "magnifyingglass", action: {})
            }

            Text("Que voulez-vous regarder ?")
                .font(.system(size: 24, weight: .black, design: .rounded))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var browseSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                sectionTitle("Parcourir")
                Spacer()
                Button {} label: {
                    Image(systemName: "arrow.right")
                        .font(.headline.weight(.bold))
                        .frame(width: 32, height: 32)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(homeModel.browseCategories) { category in
                    NavigationLink(value: category) {
                        HStack {
                            Text(category.title)
                                .font(.system(size: 16, weight: .medium, design: .rounded))
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                                .lineLimit(2)
                                .minimumScaleFactor(0.8)
                            Spacer()
                        }
                        .padding(14)
                        .frame(minHeight: 88)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var forYouSection: some View {
        let filtered = homeModel.forYouItems
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                sectionTitle("Pour vous")
                if !libraryStore.preferredPlatformIDs.isEmpty {
                    activePlatformShortcuts
                }
                Spacer()
                Button {
                    showPlatformSheet = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "hand.draw.fill")
                            .font(.footnote)
                        Text("Swipe")
                            .font(.headline.weight(.bold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(.secondarySystemBackground))
                .foregroundStyle(.primary)
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
                Text("Aucun film ne correspond a vos plateformes selectionnees.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

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

    private var activePlatformShortcuts: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(homeModel.availablePlatforms.filter { libraryStore.preferredPlatformIDs.contains($0.id) }) { platform in
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
                        .frame(width: 34, height: 20)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 5)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    } else {
                        Text(platform.shortLabel)
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }
        }
        .frame(maxWidth: 140)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 24, weight: .black, design: .rounded))
            .lineLimit(2)
            .minimumScaleFactor(0.8)
    }
}

private struct CircleIconButton: View {
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.headline.weight(.bold))
                .frame(width: 44, height: 44)
                .background(Color(.secondarySystemBackground), in: Circle())
        }
        .buttonStyle(.plain)
    }
}
