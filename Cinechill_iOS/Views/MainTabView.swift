//
//  MainTabView.swift
//  Cinechill_iOS
//

import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var libraryStore: LibraryStore

    @State private var homeModel: HomeViewModel
    @State private var questionnaireModel: QuestionnaireViewModel
    @State private var swipeModel = SwipeDeckViewModel()
    @State private var galleryModel = GalleryViewModel()
    @State private var watchlistModel = WatchlistViewModel()
    @State private var catalog = MediaCatalog()
    @State private var badgesModel = BadgesViewModel()
    @State private var selectedTab = 0
    /// Onglets déjà ouverts au moins une fois. Ils restent montés pour garder
    /// leur état — position de scroll, pile de navigation, réponses en cours —
    /// mais ne sont construits qu'à la première visite, pour qu'ouvrir l'app ne
    /// déclenche pas les chargements des quatre autres onglets.
    @State private var mountedTabs: Set<Int> = [0]

    private static let tabCount = 5

    init() {
        let client = BackendPopularClient()
        _homeModel = State(initialValue: HomeViewModel(
            repository: PopularRepository(client: client),
            metadataClient: client
        ))
        _questionnaireModel = State(initialValue: QuestionnaireViewModel(
            recommendationClient: BackendRecommendationClient(),
            metadataClient: client
        ))
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

            AppTabBar(selectedTab: $selectedTab)
        }
        .environment(catalog)
        .environment(badgesModel)
        .overlay { celebrationOverlay }
        .onChange(of: selectedTab) { _, tab in
            mountedTabs.insert(tab)
        }
        // Le seul signal commun à tout ce qui peut débloquer un badge ou
        // faire franchir un palier — swipe, fiche film, CinéMatch — c'est la
        // galerie qui grossit. `hasLoadedGalleryOnce` sert à distinguer
        // l'arrivée du tout premier chargement d'un vrai ajout : sans lui, le
        // 0 → N initial se ferait passer pour une avalanche de déblocages.
        .onChange(of: libraryStore.hasLoadedGalleryOnce) { _, loaded in
            if loaded {
                Task { await badgesModel.checkForNewAchievements(galleryCount: libraryStore.galleryItems.count) }
            } else {
                badgesModel.resetAchievementTracking()
            }
        }
        .onChange(of: libraryStore.galleryItems.count) { _, newCount in
            guard libraryStore.hasLoadedGalleryOnce else { return }
            Task { await badgesModel.checkForNewAchievements(galleryCount: newCount) }
        }
    }

    @ViewBuilder
    private var celebrationOverlay: some View {
        if let celebration = badgesModel.currentCelebration {
            AchievementCelebrationOverlay(
                celebration: celebration,
                onEquip: {
                    if case .badge(let badge) = celebration {
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
            QuestionnaireView(viewModel: questionnaireModel)
        case 2:
            SwipeDeckView(model: swipeModel, selectedTab: $selectedTab)
        case 3:
            GalleryView(model: galleryModel, selectedTab: $selectedTab)
        default:
            WatchlistView(model: watchlistModel, selectedTab: $selectedTab)
        }
    }
}
