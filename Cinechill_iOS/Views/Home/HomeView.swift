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
    /// Les deux lignes de titre réservées sous l'affiche, qui grandissent
    /// avec le texte (Dynamic Type) pour que les rangées restent alignées.
    @ScaledMetric(relativeTo: .caption2) private var posterTitleHeight = PosterCell.titleHeight
    /// La hauteur d'une carte « Parcourir », qui suit celle de son titre.
    @ScaledMetric(relativeTo: .footnote) private var browseRow: CGFloat = 84
    @Bindable var homeModel: HomeViewModel
    @EnvironmentObject private var libraryStore: LibraryStore
    @EnvironmentObject private var profileStore: UserProfileStore
    @EnvironmentObject private var socialStore: SocialStore
    @Environment(BadgesViewModel.self) private var badgesModel
    @Environment(MediaCatalog.self) private var catalog
    @EnvironmentObject private var authService: AuthService

    @State private var showPlatformSheet = false
    @State private var showProfile = false

    private func reload() async {
        await homeModel.loadAll(preferredPlatformIDs: libraryStore.preferredPlatformIDs)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Ink.ground.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 30) {
                        // La conséquence, pas le mécanisme : le code HTTP du serveur
                        // ne dit rien à personne. Et une issue, sans quoi il
                        // fallait tuer l'app pour réessayer.
                        if homeModel.errorMessage != nil {
                            HStack(alignment: .firstTextBaseline, spacing: 11) {
                                PlanLight(tint: Ink.warn)
                                Text("Impossible de charger l'accueil. Vérifie ta connexion.", bundle: .app)
                                    .planFont(13)
                                    .foregroundStyle(Ink.warn)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 8)
                                Button {
                                    Task { await reload() }
                                } label: {
                                    Text("Réessayer", bundle: .app)
                                        .planLabel()
                                        .foregroundStyle(Ink.ink)
                                        .frame(minHeight: 44)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(PressableScaleStyle())
                            }
                        }

                        if !homeModel.hasLoadedOnce {
                            loadingState
                        } else {
                            inTheatersSection
                            becauseYouWatchedSection
                            trendingSection
                            popularSection
                            if !homeModel.browseCategories.isEmpty {
                                browseSection
                            }
                        }
                    }
                    .padding(.horizontal, Metrics.margin)
                    .padding(.top, 26)
                    .padding(.bottom, 20)
                }
                .scrollIndicators(.hidden)
                .refreshable { await reload() }
            }
            .safeAreaInset(edge: .top) {
                AppHeaderView(title: String(localized: "Accueil", bundle: .app), onProfileTap: { showProfile = true })
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
                // `RootView` a normalement déjà tout demandé pendant l'ouverture ; cet appel
                // ne sert qu'aux cas où le préchargement n'a pas eu lieu ou n'a pas abouti.
                await homeModel.loadAllIfNeeded(preferredPlatformIDs: libraryStore.preferredPlatformIDs)
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
            Text("Chargement…", bundle: .app)
                .planFont(12.5)
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
                sectionTitle(String(localized: "Au cinéma en ce moment", bundle: .app))

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
                sectionTitle(
                    seeded.seedTitle.map { String(localized: "Parce que tu as vu \($0)", bundle: .app) }
                        ?? String(localized: "Dans le même style", bundle: .app)
                )
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
                sectionTitle(String(localized: "Tendances de la semaine", bundle: .app))

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
                                        .overlay(alignment: .bottomLeading) { seasonPlate(item) }
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
                                        Text(verbatim: "\(index + 1)")
                                            .planLabel()
                                            .monospacedDigit()
                                            .foregroundStyle(Ink.light)
                                        Text(item.title)
                                            .planFont(11)
                                            .foregroundStyle(Ink.ink)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.leading)
                                    }
                                    .frame(width: 104, height: posterTitleHeight, alignment: .topLeading)
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
            sectionTitle(String(localized: "Populaire en ce moment", bundle: .app))

            platformRow

            posterRail(homeModel.popularItems)

            if homeModel.popularItems.isEmpty, !homeModel.loading {
                Text(emptyPopularMessage)
                    .planFont(12.5)
                    .foregroundStyle(Ink.ink2)
            }
        }
    }

    /// Le filtre ne se cache plus derrière un carré à curseurs : la ligne montre
    /// les plateformes retenues, et « Modifier » ouvre le sélecteur — le même
    /// que celui des réglages, désormais unique dans l'application.
    private var platformRow: some View {
        HStack(spacing: 9) {
            Text(selectedPlatforms.isEmpty
                 ? String(localized: "Toutes plateformes", bundle: .app)
                 : String(localized: "Mes plateformes", bundle: .app))
                .planLabel()
                .foregroundStyle(Ink.ink2)

            if !selectedPlatforms.isEmpty {
                HStack(spacing: 5) {
                    ForEach(selectedPlatforms.prefix(4)) { platform in
                        platformLogo(platform)
                    }
                    if selectedPlatforms.count > 4 {
                        Text(verbatim: "+\(selectedPlatforms.count - 4)")
                            .planFont(10)
                            .monospacedDigit()
                            .foregroundStyle(Ink.ink2)
                    }
                }
            }

            Spacer(minLength: 8)

            Button {
                showPlatformSheet = true
            } label: {
                Text("Modifier", bundle: .app)
                    .planFont(12)
                    .foregroundStyle(Ink.ink2)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Ink.ruleSet).frame(height: 1).offset(y: 2)
                    }
                    .contentShape(Rectangle().inset(by: -10))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Choisir tes plateformes", bundle: .app))
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
                    .planFont(8, weight: .semibold)
                    .foregroundStyle(Ink.ink2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Ink.ground3)
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
            ? String(localized: "Rien à afficher pour le moment.", bundle: .app)
            : String(localized: "Aucun film disponible sur tes plateformes en ce moment.", bundle: .app)
    }

    // MARK: - Parcourir

    private var browseSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                sectionTitle(String(localized: "Parcourir", bundle: .app))
                Spacer()
                NavigationLink(destination: HomeGenresListView(categories: homeModel.browseCategories, homeModel: homeModel)) {
                    Text("Tout voir", bundle: .app)
                        .planFont(12)
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
                    rows: [GridItem(.fixed(browseRow), spacing: Metrics.gutter), GridItem(.fixed(browseRow), spacing: Metrics.gutter)],
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
                .frame(height: browseRow * 2 + Metrics.gutter)
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
                                .overlay(alignment: .bottomLeading) { seasonPlate(item) }
                                LibraryMark(
                                    inGallery: libraryStore.isInGallery(item),
                                    inWatchlist: libraryStore.isInWatchlist(item)
                                )
                                .padding(6)
                            }

                            Text(item.title)
                                .planFont(11)
                                .foregroundStyle(Ink.ink)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                // Deux lignes réservées quoi qu'il arrive : sans
                                // hauteur fixe, un titre court et un titre long ne
                                // donnent pas la même hauteur de cellule, et les
                                // affiches se désalignent.
                                .frame(width: 104, height: posterTitleHeight, alignment: .topLeading)
                        }
                    }
                    .buttonStyle(PressableScaleStyle(scale: 0.95))
                }
            }
            .padding(.horizontal, 1)
        }
        .scrollClipDisabled()
    }

    /// Une série porte son nombre de saisons, en bas de l'affiche. Le point de
    /// la bibliothèque, en haut, garde son sens : il s'allume dès qu'une de
    /// ses saisons est rangée.
    @ViewBuilder
    private func seasonPlate(_ item: MediaItem) -> some View {
        if item.isSeries, let count = item.seasonCount, count > 0 {
            PosterPlate(text: count == 1
                        ? String(localized: "1 saison", bundle: .app)
                        : String(localized: "\(count) saisons", bundle: .app))
        }
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
    /// Les deux lignes de titre réservées sous l'affiche, qui grandissent
    /// avec le texte (Dynamic Type) pour que les rangées restent alignées.
    @ScaledMetric(relativeTo: .caption2) private var posterTitleHeight = PosterCell.titleHeight
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
                .planFont(11)
                .foregroundStyle(Ink.ink)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(width: width, height: posterTitleHeight, alignment: .topLeading)
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
        guard days >= 0 else { return String(localized: "Bientôt", bundle: .app) }
        if days <= 7 { return String(localized: "Cette semaine", bundle: .app) }
        return String(localized: "Depuis \(days) j", bundle: .app)
    }
}
