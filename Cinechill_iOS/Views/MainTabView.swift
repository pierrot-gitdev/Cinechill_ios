//
//  MainTabView.swift
//  Cinechill_iOS
//

import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    @Environment(OnboardingTour.self) private var tour

    /// Prêtés par `RootView`, qui les a créés bien avant cette vue pour que l'accueil se
    /// charge pendant l'ouverture. Les autres onglets n'étant pas montés au lancement, ils
    /// n'ont rien à gagner à remonter d'un cran.
    private let catalog: MediaCatalog
    private let homeModel: HomeViewModel

    @State private var cineMatchModel = CineMatchViewModel()
    @State private var swipeModel = SwipeDeckViewModel()
    @State private var galleryModel = GalleryViewModel()
    @State private var watchlistModel = WatchlistViewModel()
    @State private var badgesModel = BadgesViewModel()
    /// L'état de la porte pour toute l'application : un artéfact se gagne
    /// ailleurs que dans l'onglet CinéMatch, et doit s'annoncer là où l'on est.
    @State private var doorStore = DoorStore()
    @State private var selectedTab = 0
    /// Onglets déjà ouverts au moins une fois. Ils restent montés pour garder
    /// leur état — position de scroll, pile de navigation, réponses en cours —
    /// mais ne sont construits qu'à la première visite, pour qu'ouvrir l'app ne
    /// déclenche pas les chargements des quatre autres onglets.
    @State private var mountedTabs: Set<Int> = [0]

    private static let tabCount = 5

    init(catalog: MediaCatalog, homeModel: HomeViewModel) {
        self.catalog = catalog
        self.homeModel = homeModel
    }

    var body: some View {
        // Pas de `TabView` : elle impose sa barre native, dont `AppTabBar` a
        // pris toute la charge. Le conteneur reproduit la seule chose qu'elle
        // apportait encore, la persistance de l'état onglet par onglet.
        //
        // Chaque onglet est contraint à la taille exacte du conteneur. Sans ça
        // le `ZStack` prendrait la taille de son plus grand enfant, et un seul
        // onglet au contenu plus large que l'écran suffirait à faire déborder
        // la mise en page de tous les autres.
        // La barre est un frère du contenu dans un `VStack`, et non un
        // `safeAreaInset` : celui-ci ne réduit pas le cadre de mise en page mais
        // seulement la zone sûre, que tout `ignoresSafeArea` en descendant
        // annule — d'où le bas des écrans systématiquement rogné. En frère, la
        // place prise par la barre est retirée de la hauteur disponible, et
        // l'occultation devient structurellement impossible.
        VStack(spacing: 0) {
            GeometryReader { proxy in
                ZStack {
                    ForEach(0 ..< Self.tabCount, id: \.self) { tab in
                        if visibleTabs.contains(tab) {
                            content(for: tab)
                                .frame(width: proxy.size.width, height: proxy.size.height)
                                .opacity(selectedTab == tab ? 1 : 0)
                                .allowsHitTesting(selectedTab == tab)
                                .accessibilityHidden(selectedTab != tab)
                                .zIndex(selectedTab == tab ? 1 : 0)
                        }
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .background(Ink.ground)

            AppTabBar(selectedTab: $selectedTab)
        }
        // Pendant l'onboarding, l'application est là, dessous, mais ni le doigt
        // ni VoiceOver ne l'atteignent.
        .accessibilityHidden(tour.isRunning)
        .environment(catalog)
        .environment(badgesModel)
        .environment(doorStore)
        .overlay { celebrationOverlay }
        .overlay { doorOverlay }
        .overlay { onboarding }
        .onChange(of: selectedTab) { _, tab in
            mountedTabs.insert(tab)
        }
        // Le seul signal commun à tout ce qui peut débloquer un badge ou
        // faire monter d'une distinction — swipe, fiche film, CinéMatch — c'est la
        // galerie qui grossit. `hasLoadedGalleryOnce` sert à distinguer
        // l'arrivée du tout premier chargement d'un vrai ajout : sans lui, le
        // 0 → N initial se ferait passer pour une avalanche de déblocages.
        .onChange(of: libraryStore.hasLoadedGalleryOnce) { _, loaded in
            if loaded {
                Task { await badgesModel.checkForNewAchievements(galleryCount: libraryStore.galleryFilms.count) }
                Task { await startTourIfNeeded() }
            } else {
                badgesModel.resetAchievementTracking()
            }
        }
        // Les badges comptent des films : une saison rangée ne doit pas faire
        // croire à un palier franchi.
        .onChange(of: libraryStore.galleryFilms.count) { _, newCount in
            guard libraryStore.hasLoadedGalleryOnce else { return }
            Task { await badgesModel.checkForNewAchievements(galleryCount: newCount) }
        }
        .task {
            // Filet de sécurité : si la galerie était déjà chargée avant que
            // cette vue n'existe, l'`onChange` ci-dessus ne se déclenchera
            // jamais et personne ne serait jamais pris en main.
            if libraryStore.hasLoadedGalleryOnce { await startTourIfNeeded() }
        }
        // La mise à niveau de l'existant, dès que la bibliothèque est là et
        // avant toute annonce : ce que le rattrapage remonte est un dû.
        .task(id: libraryStore.hasLoadedGalleryOnce) {
            guard libraryStore.hasLoadedGalleryOnce else { return }
            await doorStore.bootstrap()
        }
        // La porte se remesure dès que la bibliothèque bouge — un film vu, un
        // cœur posé, une envie rangée. Le `task(id:)` annule la mesure
        // précédente à chaque changement : balayer vingt cartes d'affilée ne
        // déclenche qu'un seul appel, celui qui suit la dernière.
        .task(id: doorSignature) {
            guard libraryStore.hasLoadedGalleryOnce else { return }
            try? await Task.sleep(for: .milliseconds(1200))
            guard !Task.isCancelled else { return }
            await doorStore.refresh()
        }
    }

    /// Ce qui, dans la bibliothèque, peut faire bouger un artéfact.
    private var doorSignature: String {
        // Les deux Portes se mesurent du même appel : une saison qui entre fait
        // avancer celle des séries, un film celle des films.
        let gallery = libraryStore.galleryFilms.count
        let watchlist = libraryStore.watchlistFilms.count
        let seasons = libraryStore.galleryItems.count - gallery
        let queued = libraryStore.watchlistItems.count - watchlist
        let lovedSeasons = libraryStore.galleryItems.filter { $0.isSeason && $0.isLoved }.count
        return "\(gallery)-\(libraryStore.lovedCount)-\(watchlist)-\(seasons)-\(lovedSeasons)-\(queued)"
    }

    // MARK: - L'onboarding

    private func startTourIfNeeded() async {
        await tour.startIfNeeded(
            galleryCount: libraryStore.galleryFilms.count,
            watchlistCount: libraryStore.watchlistFilms.count
        )
    }

    /// L'onboarding, par-dessus tout, barre d'onglets comprise. À la fin, il
    /// descend et découvre Découvrir, déjà sélectionné dessous : on arrive là
    /// où la galerie se remplit, sans transition de plus.
    @ViewBuilder
    private var onboarding: some View {
        if tour.isRunning {
            OnboardingFlowView(tour: tour) {
                selectedTab = 2
                mountedTabs.insert(2)
                withAnimation(.timingCurve(0.32, 0.72, 0, 1, duration: 0.5)) { tour.finish() }
            }
            .environmentObject(libraryStore)
            .environment(catalog)
            .transition(.move(edge: .bottom))
            .zIndex(20)
        }
    }

    // MARK: - Chrome

    @ViewBuilder
    private var celebrationOverlay: some View {
        if let celebration = badgesModel.currentCelebration {
            AchievementCelebrationOverlay(
                celebration: celebration,
                onEquip: {
                    if case .badge(let badge, _) = celebration {
                        libraryStore.setDisplayedBadge(badge.id)
                    }
                    withAnimation(.easeOut(duration: 0.22)) {
                        badgesModel.dismissCurrentCelebration()
                    }
                },
                onDismiss: {
                    withAnimation(.easeOut(duration: 0.22)) {
                        badgesModel.dismissCurrentCelebration()
                    }
                }
            )
            .id(celebration.id)
            .transition(.opacity)
            .zIndex(10)
        }
    }

    /// L'artéfact gagné, annoncé où que l'on soit.
    ///
    /// Il attend qu'un éventuel badge ait fini de se montrer : deux planches
    /// l'une sur l'autre ne se lisent pas, et la galerie qui grossit peut très
    /// bien déclencher les deux d'un même geste.
    @ViewBuilder
    private var doorOverlay: some View {
        if let key = doorStore.celebration, badgesModel.currentCelebration == nil {
            let format: MediaFormat = doorStore.celebrationDoor.series ? .series : .film
            DoorCelebrationOverlay(
                door: doorStore.celebrationDoor,
                unlocked: key,
                onDismiss: dismissDoorCelebration,
                onShowDoor: {
                    dismissDoorCelebration()
                    doorStore.post(.showDoor(format))
                    selectedTab = 1
                },
                onCompare: {
                    dismissDoorCelebration()
                    doorStore.post(.compare(format))
                    selectedTab = 1
                }
            )
            .id(key)
            .transition(.opacity)
            .zIndex(11)
        }
    }

    private func dismissDoorCelebration() {
        withAnimation(.easeOut(duration: 0.22)) {
            doorStore.dismissCelebration()
        }
    }

    /// L'onglet sélectionné est monté dans la même passe de rendu que sa
    /// sélection, sans attendre le `onChange` — sinon il manquerait une frame.
    private var visibleTabs: Set<Int> {
        mountedTabs.union([selectedTab])
    }

    @ViewBuilder
    private func content(for tab: Int) -> some View {
        switch tab {
        case 0:
            HomeView(homeModel: homeModel)
        case 1:
            CineMatchView(
                viewModel: cineMatchModel,
                selectedTab: $selectedTab
            )
        case 2:
            SwipeDeckView(model: swipeModel, selectedTab: $selectedTab)
        case 3:
            GalleryView(model: galleryModel, selectedTab: $selectedTab)
        default:
            WatchlistView(model: watchlistModel, selectedTab: $selectedTab)
        }
    }
}
