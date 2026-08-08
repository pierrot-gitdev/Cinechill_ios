import SwiftUI

/// L'accueil — l'écran de découverte.
///
/// Cinq rangées, chacune avec une intention distincte et un titre qui dit
/// exactement ce qu'elle contient. Le contenu périssable — ce qui est en salle
/// — passe en tête ; la navigation permanente descend.
struct HomeView: View {
    @Bindable var homeModel: HomeViewModel
    @EnvironmentObject private var libraryStore: LibraryStore
    @EnvironmentObject private var profileStore: UserProfileStore
    @EnvironmentObject private var socialStore: SocialStore
    @Environment(BadgesViewModel.self) private var badgesModel
    @EnvironmentObject private var authService: AuthService

    @State private var showPlatformSheet = false
    @State private var showProfile = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        if let err = homeModel.errorMessage {
                            Text(err)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if !homeModel.hasLoadedOnce {
                            loadingState
                        } else {
                            inTheatersSection
                            becauseYouWatchedSection
                            trendingSection
                            popularSection
                            browseSection
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom)
                    .padding(.top, 28)
                }
            }
            .safeAreaInset(edge: .top) {
                AppHeaderView(title: "Accueil", onProfileTap: { showProfile = true })
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
                ProfileView(badgesModel: badgesModel)
                    .environmentObject(profileStore)
                    .environmentObject(libraryStore)
                    .environmentObject(authService)
                    .environmentObject(socialStore)
            }
            .task {
                await homeModel.loadAll(preferredPlatformIDs: libraryStore.preferredPlatformIDs)
            }
            .task(id: libraryStore.preferredPlatformIDs) {
                guard homeModel.hasLoadedOnce else { return }
                await homeModel.refreshPopular(using: libraryStore.preferredPlatformIDs)
            }
            .task(id: libraryStore.bannedGenreIDs) {
                homeModel.applyBannedGenres(libraryStore.bannedGenreIDs)
            }
        }
    }

    private var loadingState: some View {
        VStack(spacing: 14) {
            CinechillSpinner(size: 32)
            Text("Chargement…")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Au cinéma

    /// Le seul contenu périssable de l'écran, donc le premier. L'ancienneté de
    /// la sortie est affichée : savoir qu'un film va bientôt quitter l'affiche
    /// est ce qui déclenche une décision.
    @ViewBuilder
    private var inTheatersSection: some View {
        if !homeModel.rows.inTheaters.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                sectionTitle("Au cinéma en ce moment")

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(homeModel.rows.inTheaters) { item in
                            NavigationLink(value: item) {
                                TheaterCardView(
                                    item: item,
                                    inGallery: libraryStore.isInGallery(item),
                                    inWatchlist: libraryStore.isInWatchlist(item)
                                )
                            }
                            .buttonStyle(PressableScaleStyle(scale: 0.96))
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .scrollClipDisabled()
            }
        }
    }

    // MARK: - Parce que vous avez vu…

    /// Le titre nomme le film qui a semé la rangée : la recommandation
    /// s'explique d'elle-même au lieu de tomber du ciel.
    @ViewBuilder
    private var becauseYouWatchedSection: some View {
        if let seeded = homeModel.rows.becauseYouWatched, !seeded.items.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                sectionTitle(seeded.seedTitle.map { "Parce que vous avez vu \($0)" } ?? "Dans la même veine")
                posterRail(seeded.items)
            }
        }
    }

    // MARK: - Tendances

    /// Le rang porte une information réelle — `trending/week` mesure un
    /// mouvement hebdomadaire, là où « populaire » bouge à peine d'un jour sur
    /// l'autre — d'où le chiffre affiché.
    @ViewBuilder
    private var trendingSection: some View {
        if !homeModel.rows.trending.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                sectionTitle("Tendances de la semaine")

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .bottom, spacing: 2) {
                        ForEach(Array(homeModel.rows.trending.prefix(10).enumerated()), id: \.element.id) { index, item in
                            NavigationLink(value: item) {
                                HStack(alignment: .bottom, spacing: -10) {
                                    Text("\(index + 1)")
                                        .font(.system(size: 64, weight: .black, design: .rounded))
                                        .foregroundStyle(Color.primary.opacity(0.16))
                                        .monospacedDigit()

                                    posterCell(item, width: 88)
                                }
                            }
                            .buttonStyle(PressableScaleStyle(scale: 0.95))
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .scrollClipDisabled()
            }
        }
    }

    // MARK: - Populaire

    private var popularSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                sectionTitle(selectedPlatforms.isEmpty ? "Populaire en ce moment" : "Populaire sur")

                if !selectedPlatforms.isEmpty {
                    platformLogos(Array(selectedPlatforms.prefix(3)))
                }

                Spacer(minLength: 0)

                Button {
                    showPlatformSheet = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(PressableScaleStyle(scale: 0.92))
                .accessibilityLabel("Choisir vos plateformes")
            }

            posterRail(homeModel.popularItems)

            if homeModel.popularItems.isEmpty, !homeModel.loading {
                Text(emptyPopularMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var selectedPlatforms: [StreamingPlatform] {
        homeModel.availablePlatforms
            .filter { libraryStore.preferredPlatformIDs.contains($0.id) }
    }

    /// Les logos plutôt que les noms : ils sont reconnus plus vite qu'ils ne
    /// sont lus, et trois marques écrites en toutes lettres mangeaient la
    /// largeur du titre.
    private func platformLogos(_ platforms: [StreamingPlatform]) -> some View {
        HStack(spacing: -7) {
            ForEach(Array(platforms.enumerated()), id: \.element.id) { index, platform in
                Group {
                    if let logoURL = platform.logoURL {
                        PosterImageView(url: logoURL)
                    } else {
                        Text(platform.shortLabel)
                            .font(.system(size: 9, weight: .heavy, design: .rounded))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(.tertiarySystemFill))
                    }
                }
                .frame(width: 26, height: 26)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color(.systemBackground), lineWidth: 1.5)
                )
                .zIndex(Double(platforms.count - index))
                .accessibilityLabel(platform.name)
            }
        }
    }

    private var emptyPopularMessage: String {
        libraryStore.preferredPlatformIDs.isEmpty
            ? "Rien à afficher pour le moment."
            : "Aucun film disponible sur vos plateformes en ce moment."
    }

    // MARK: - Parcourir

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

    // MARK: - Helpers

    private func posterRail(_ items: [MediaItem]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(items) { item in
                    NavigationLink(value: item) {
                        posterCell(item, width: 108)
                    }
                    .buttonStyle(PressableScaleStyle(scale: 0.95))
                }
            }
            .padding(.horizontal, 2)
        }
        .scrollClipDisabled()
    }

    /// Les pastilles galerie et watchlist sont enfin renseignées : sur un écran
    /// de découverte, distinguer d'un coup d'œil ce qu'on a déjà vu vaut plus
    /// que n'importe quelle rangée supplémentaire.
    private func posterCell(_ item: MediaItem, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                PosterTile(
                    posterPath: item.posterPath,
                    title: item.title,
                    width: width,
                    cornerRadius: 10
                )

                LibraryBadge(
                    inGallery: libraryStore.isInGallery(item),
                    inWatchlist: libraryStore.isInWatchlist(item)
                )
                .padding(6)
            }

            Text(item.title)
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                // Deux lignes réservées quoi qu'il arrive : sans hauteur fixe,
                // un titre court et un titre long ne donnent pas la même
                // hauteur de carte, et les affiches se désalignent.
                .frame(width: width, height: Self.titleHeight, alignment: .topLeading)
        }
    }

    /// Hauteur réservée au titre sous une affiche — deux lignes.
    static let titleHeight: CGFloat = 30

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 22, weight: .black, design: .rounded))
            .lineLimit(2)
            .minimumScaleFactor(0.75)
    }
}

/// Pastille d'état, commune à toutes les affiches de l'accueil.
struct LibraryBadge: View {
    let inGallery: Bool
    let inWatchlist: Bool

    var body: some View {
        if inGallery {
            badge(icon: "checkmark", color: .green, label: "Déjà vu")
        } else if inWatchlist {
            badge(icon: "bookmark.fill", color: .blue, label: "Dans votre watchlist")
        }
    }

    private func badge(icon: String, color: Color, label: String) -> some View {
        Image(systemName: icon)
            .font(.system(size: 8, weight: .heavy))
            .foregroundStyle(.white)
            .frame(width: 18, height: 18)
            .background(color, in: Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1))
            .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
            .accessibilityLabel(label)
    }
}

/// Carte des sorties en salle.
///
/// Reste au format portrait — TMDB ne fournit qu'une affiche ici, et la rogner
/// en paysage ne donnerait qu'une bande horizontale souvent illisible. C'est le
/// bandeau d'ancienneté, pas le format, qui distingue cette rangée.
struct TheaterCardView: View {
    let item: MediaItem
    let inGallery: Bool
    let inWatchlist: Bool

    private let width: CGFloat = 128

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ZStack(alignment: .topLeading) {
                PosterTile(
                    posterPath: item.posterPath,
                    title: item.title,
                    width: width,
                    cornerRadius: 11
                )

                if let freshness {
                    Text(freshness)
                        .font(.system(size: 8, weight: .heavy, design: .rounded))
                        .kerning(0.6)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial, in: Capsule())
                        .environment(\.colorScheme, .dark)
                        .padding(7)
                }

                LibraryBadge(inGallery: inGallery, inWatchlist: inWatchlist)
                    .padding(7)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(width: width)

            Text(item.title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(width: width, height: HomeView.titleHeight, alignment: .topLeading)
        }
    }

    /// « Cette semaine » puis « depuis N jours » — l'ancienneté est ce qui dit
    /// combien de temps il reste pour le voir, pas la date de sortie.
    private var freshness: String? {
        guard let releaseDate = item.releaseDate else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        guard let date = formatter.date(from: releaseDate) else { return nil }

        let days = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
        guard days >= 0 else { return "BIENTÔT" }
        if days <= 7 { return "CETTE SEMAINE" }
        return "DEPUIS \(days) J"
    }
}
