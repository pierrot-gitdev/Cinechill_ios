//
//  MainTabView.swift
//  Cinechill_iOS
//

import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    @Environment(OnboardingTour.self) private var tour
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Prêtés par `RootView`, qui les a créés bien avant cette vue pour que l'accueil se
    /// charge pendant l'ouverture. Les autres onglets n'étant pas montés au lancement, ils
    /// n'ont rien à gagner à remonter d'un cran.
    private let catalog: MediaCatalog
    private let homeModel: HomeViewModel

    @State private var questionnaireModel: QuestionnaireViewModel
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

    /// Les onglets tenus allumés par la dernière étape de la prise en main, et
    /// la position imposée de la lampe pendant qu'elle les parcourt.
    @State private var litTabs: Set<Int> = []
    @State private var closingLamp: Int?

    private static let tabCount = 5

    init(catalog: MediaCatalog, homeModel: HomeViewModel) {
        self.catalog = catalog
        self.homeModel = homeModel
        _questionnaireModel = State(initialValue: QuestionnaireViewModel(
            recommendationClient: BackendRecommendationClient(),
            metadataClient: BackendPopularClient()
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
                                .allowsHitTesting(selectedTab == tab && !tour.isRunning)
                                .accessibilityHidden(selectedTab != tab)
                                .zIndex(selectedTab == tab ? 1 : 0)
                        }
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .overlay { if tour.isRunning { OnboardingVeil().transition(.opacity) } }
                .overlay(alignment: .bottom) { cartouche }
            }

            // La barre reste **visible** de bout en bout — c'est elle qui montre
            // où l'on est, et sa lampe est tout ce que la visite a à enseigner
            // sur la navigation. Elle est seulement rendue inerte : on regarde,
            // on ne pilote pas.
            AppTabBar(selectedTab: $selectedTab, litTabs: litTabs, lampOverride: closingLamp)
                .allowsHitTesting(!tour.isRunning)
        }
        .environment(catalog)
        .environment(badgesModel)
        .environment(doorStore)
        .overlay { celebrationOverlay }
        .overlay { doorOverlay }
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
                Task { await badgesModel.checkForNewAchievements(galleryCount: libraryStore.galleryItems.count) }
                Task { await startTourIfNeeded() }
            } else {
                badgesModel.resetAchievementTracking()
            }
        }
        .onChange(of: libraryStore.galleryItems.count) { _, newCount in
            guard libraryStore.hasLoadedGalleryOnce else { return }
            Task { await badgesModel.checkForNewAchievements(galleryCount: newCount) }
        }
        .onChange(of: tour.tabRequest) { _, _ in
            selectedTab = tour.requestedTab
        }
        .onChange(of: tour.isClosing) { _, closing in
            if closing { Task { await runClosingSequence() } }
        }
        .onChange(of: tour.isRunning) { _, running in
            if !running {
                litTabs = []
                closingLamp = nil
            }
        }
        .task {
            // Filet de sécurité : si la galerie était déjà chargée avant que
            // cette vue n'existe, l'`onChange` ci-dessus ne se déclenchera
            // jamais et personne ne serait jamais pris en main.
            if libraryStore.hasLoadedGalleryOnce { await startTourIfNeeded() }
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
        let gallery = libraryStore.galleryItems.count
        let watchlist = libraryStore.watchlistItems.count
        return "\(gallery)-\(libraryStore.lovedCount)-\(watchlist)"
    }

    // MARK: - La prise en main

    private func startTourIfNeeded() async {
        await tour.startIfNeeded(
            galleryCount: libraryStore.galleryItems.count,
            watchlistCount: libraryStore.watchlistItems.count
        )
    }

    @ViewBuilder
    private var cartouche: some View {
        if let step = tour.step {
            OnboardingCartouche(
                step: step,
                counter: tour.counter,
                progress: tour.progress,
                onNext: { tour.next() },
                onSkip: { tour.skip() }
            )
            .transition(.opacity)
        }
    }

    /// La lampe repasse sur les cinq onglets et **allume chacun au passage**.
    /// Au repos la barre n'écrit qu'un seul libellé : pendant ces trois
    /// secondes, et une seule fois dans la vie du compte, la carte entière de
    /// l'application est lisible d'un coup d'œil.
    ///
    /// La lampe est déplacée par `lampOverride`, jamais par la sélection : faire
    /// défiler les onglets pour de vrai monterait les cinq écrans et
    /// déclencherait leurs chargements pour une animation.
    private func runClosingSequence() async {
        guard !reduceMotion else {
            litTabs = Set(0 ..< Self.tabCount)
            closingLamp = 0
            return
        }

        litTabs = []
        closingLamp = 0
        for tab in 0 ..< Self.tabCount {
            // Pas de `withAnimation` ici : `AppTabBar` tient déjà la courbe du
            // Seuil sur cette valeur, et l'envelopper superposerait deux courbes
            // sur un même déplacement.
            closingLamp = tab
            try? await Task.sleep(for: .milliseconds(260))
            guard tour.isClosing else { return }
            withAnimation(.easeOut(duration: 0.22)) { _ = litTabs.insert(tab) }
        }
        try? await Task.sleep(for: .milliseconds(500))
        guard tour.isClosing else { return }
        closingLamp = 0
    }

    // MARK: - Chrome

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

    /// L'artéfact gagné, annoncé où que l'on soit.
    ///
    /// Il attend qu'un éventuel badge ait fini de se montrer : deux planches
    /// l'une sur l'autre ne se lisent pas, et la galerie qui grossit peut très
    /// bien déclencher les deux d'un même geste.
    @ViewBuilder
    private var doorOverlay: some View {
        if let key = doorStore.celebration, badgesModel.currentCelebration == nil {
            DoorCelebrationOverlay(
                door: doorStore.door,
                unlocked: key,
                onDismiss: {
                    withAnimation(.easeOut(duration: 0.22)) {
                        doorStore.dismissCelebration()
                    }
                }
            )
            .id(key)
            .transition(.opacity)
            .zIndex(11)
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
            QuestionnaireView(
                viewModel: questionnaireModel,
                homeModel: homeModel,
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
