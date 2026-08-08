import SwiftUI

/// L'accueil — l'écran de découverte.
///
/// Cinq rangées, chacune avec une intention distincte et un titre qui dit
/// exactement ce qu'elle contient. Le contenu périssable — ce qui est en salle
/// — passe en tête ; la navigation permanente descend. Cet ordre était juste et
/// n'a pas bougé.
///
/// Ce qui a changé : les titres passent à l'échelle de titre de l'application,
/// les pastilles vert/bleu deviennent le point de lumière, le filtre des
/// plateformes cesse d'être un carré gris à curseurs pour devenir une ligne qui
/// **montre ce qu'elle filtre**, et la vignette d'affiche est désormais celle
/// que toute l'app partage.
struct HomeView: View {
    @Bindable var homeModel: HomeViewModel
    @EnvironmentObject private var libraryStore: LibraryStore
    @EnvironmentObject private var profileStore: UserProfileStore
    @EnvironmentObject private var socialStore: SocialStore
    @Environment(BadgesViewModel.self) private var badgesModel
    @Environment(MediaCatalog.self) private var catalog
    @EnvironmentObject private var authService: AuthService

    @State private var showPlatformSheet = false
    @State private var showProfile = false

    var body: some View {
        NavigationStack {
            ZStack {
                Ink.ground.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 30) {
                        if let err = homeModel.errorMessage {
                            HStack(alignment: .top, spacing: 11) {
                                PlanLight(tint: Ink.warn).padding(.top, 6)
                                Text(err)
                                    .font(.system(size: 13))
                                    .foregroundStyle(Ink.warn)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
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
                    .padding(.horizontal, Metrics.margin)
                    .padding(.top, 26)
                    .padding(.bottom, 20)
                }
                .scrollIndicators(.hidden)
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
                PlatformPickerSheet()
                    .environmentObject(libraryStore)
                    .environment(catalog)
            }
            .fullScreenCover(isPresented: $showProfile) {
                ProfileView(badgesModel: badgesModel)
                    .environmentObject(profileStore)
                    .environmentObject(libraryStore)
                    .environmentObject(authService)
                    .environmentObject(socialStore)
            }
            .task {
                await catalog.loadIfNeeded()
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
            CinechillSpinner(size: 30)
            Text("Chargement…")
                .font(.system(size: 12.5))
                .foregroundStyle(Ink.ink3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
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
                    .padding(.horizontal, 1)
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
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(Array(homeModel.rows.trending.prefix(10).enumerated()), id: \.element.id) { index, item in
                            NavigationLink(value: item) {
                                VStack(alignment: .leading, spacing: 7) {
                                    ZStack(alignment: .topTrailing) {
                                        PosterTile(
                                            posterPath: item.posterPath,
                                            title: item.title,
                                            width: 104
                                        )
                                        LibraryMark(
                                            inGallery: libraryStore.isInGallery(item),
                                            inWatchlist: libraryStore.isInWatchlist(item)
                                        )
                                        .padding(6)
                                    }

                                    // Le rang est écrit au niveau de service, en
                                    // tête du titre : le chiffre géant en filigrane
                                    // mangeait une demi-affiche de largeur pour une
                                    // information qui tient en deux caractères.
                                    HStack(alignment: .top, spacing: 6) {
                                        Text("\(index + 1)")
                                            .planLabel()
                                            .monospacedDigit()
                                            .foregroundStyle(Ink.light)
                                        Text(item.title)
                                            .font(.system(size: 11))
                                            .foregroundStyle(Ink.ink)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.leading)
                                    }
                                    .frame(width: 104, height: PosterCell.titleHeight, alignment: .topLeading)
                                }
                            }
                            .buttonStyle(PressableScaleStyle(scale: 0.95))
                        }
                    }
                    .padding(.horizontal, 1)
                }
                .scrollClipDisabled()
            }
        }
    }

    // MARK: - Populaire

    private var popularSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Populaire en ce moment")

            platformRow

            posterRail(homeModel.popularItems)

            if homeModel.popularItems.isEmpty, !homeModel.loading {
                Text(emptyPopularMessage)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Ink.ink3)
            }
        }
    }

    /// Le filtre ne se cache plus derrière un carré à curseurs : la ligne montre
    /// les plateformes retenues, et « Modifier » ouvre le sélecteur — le même
    /// que celui des réglages, désormais unique dans l'application.
    private var platformRow: some View {
        HStack(spacing: 9) {
            Text(selectedPlatforms.isEmpty ? "Toutes plateformes" : "Chez vous")
                .planLabel()
                .foregroundStyle(Ink.ink3)

            if !selectedPlatforms.isEmpty {
                HStack(spacing: 5) {
                    ForEach(selectedPlatforms.prefix(4)) { platform in
                        platformLogo(platform)
                    }
                    if selectedPlatforms.count > 4 {
                        Text("+\(selectedPlatforms.count - 4)")
                            .font(.system(size: 10))
                            .monospacedDigit()
                            .foregroundStyle(Ink.ink3)
                    }
                }
            }

            Spacer(minLength: 8)

            Button {
                showPlatformSheet = true
            } label: {
                Text("Modifier")
                    .font(.system(size: 12))
                    .foregroundStyle(Ink.ink2)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Ink.ruleSet).frame(height: 1).offset(y: 2)
                    }
                    .contentShape(Rectangle().inset(by: -10))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Choisir vos plateformes")
        }
    }

    private var selectedPlatforms: [StreamingPlatform] {
        homeModel.availablePlatforms
            .filter { libraryStore.preferredPlatformIDs.contains($0.id) }
    }

    private func platformLogo(_ platform: StreamingPlatform) -> some View {
        Group {
            if let logoURL = platform.logoURL {
                PosterImageView(url: logoURL)
            } else {
                Text(platform.shortLabel.prefix(2))
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Ink.ink2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(hex: 0x151B23))
            }
        }
        .frame(width: 20, height: 20)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                .strokeBorder(Ink.rule, lineWidth: 1)
        )
        .accessibilityLabel(platform.name)
    }

    private var emptyPopularMessage: String {
        libraryStore.preferredPlatformIDs.isEmpty
            ? "Rien à afficher pour le moment."
            : "Aucun film disponible sur vos plateformes en ce moment."
    }

    // MARK: - Parcourir

    private var browseSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                sectionTitle("Parcourir")
                Spacer()
                NavigationLink(destination: HomeGenresListView(categories: homeModel.browseCategories, homeModel: homeModel)) {
                    Text("Tout voir")
                        .font(.system(size: 12))
                        .foregroundStyle(Ink.ink2)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(Ink.ruleSet).frame(height: 1).offset(y: 2)
                        }
                        .contentShape(Rectangle().inset(by: -10))
                }
                .buttonStyle(.plain)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHGrid(
                    rows: [GridItem(.fixed(84), spacing: Metrics.gutter), GridItem(.fixed(84), spacing: Metrics.gutter)],
                    spacing: Metrics.gutter
                ) {
                    ForEach(homeModel.browseCategories) { category in
                        NavigationLink(value: category) {
                            BrowseCardView(
                                title: category.title,
                                posterURL: homeModel.browsePosterURL(for: category.id)
                            )
                            .frame(width: 168)
                        }
                        .buttonStyle(PressableScaleStyle(scale: 0.96))
                    }
                }
                .frame(height: 178)
                .padding(.horizontal, 1)
            }
            .scrollClipDisabled()
        }
    }

    // MARK: - Helpers

    private func posterRail(_ items: [MediaItem]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(items) { item in
                    NavigationLink(value: item) {
                        VStack(alignment: .leading, spacing: 7) {
                            ZStack(alignment: .topTrailing) {
                                PosterTile(
                                    posterPath: item.posterPath,
                                    title: item.title,
                                    width: 104
                                )
                                LibraryMark(
                                    inGallery: libraryStore.isInGallery(item),
                                    inWatchlist: libraryStore.isInWatchlist(item)
                                )
                                .padding(6)
                            }

                            Text(item.title)
                                .font(.system(size: 11))
                                .foregroundStyle(Ink.ink)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                // Deux lignes réservées quoi qu'il arrive : sans
                                // hauteur fixe, un titre court et un titre long ne
                                // donnent pas la même hauteur de cellule, et les
                                // affiches se désalignent.
                                .frame(width: 104, height: PosterCell.titleHeight, alignment: .topLeading)
                        }
                    }
                    .buttonStyle(PressableScaleStyle(scale: 0.95))
                }
            }
            .padding(.horizontal, 1)
        }
        .scrollClipDisabled()
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .planTitle(21)
            .foregroundStyle(Ink.ink)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
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

    private let width: CGFloat = 124

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ZStack(alignment: .topLeading) {
                PosterTile(posterPath: item.posterPath, title: item.title, width: width)

                if let freshness {
                    // Le voile de la nuit plutôt qu'un matériau translucide : la
                    // même lisibilité, dans la couleur de la marque.
                    Text(freshness)
                        .planLabel()
                        .foregroundStyle(Ink.ink)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(
                            Ink.ground.opacity(0.82),
                            in: RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                        )
                        .padding(6)
                }

                LibraryMark(inGallery: inGallery, inWatchlist: inWatchlist)
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(width: width)

            Text(item.title)
                .font(.system(size: 11))
                .foregroundStyle(Ink.ink)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(width: width, height: PosterCell.titleHeight, alignment: .topLeading)
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
        guard days >= 0 else { return "Bientôt" }
        if days <= 7 { return "Cette semaine" }
        return "Depuis \(days) j"
    }
}
