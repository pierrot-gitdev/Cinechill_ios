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

    /// L'ancien moteur reste construit tant qu'il n'est pas retiré du projet,
    /// mais l'onglet CinéMatch ne le monte plus.
    @State private var questionnaireModel: QuestionnaireViewModel
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

    /// Les onglets tenus allumés par la dernière étape de la prise en main, et
    /// la position imposée de la lampe pendant qu'elle les parcourt.
    @State private var litTabs: Set<Int> = []
    @State private var closingLamp: Int?
    /// La hauteur du cartouche, mesurée : la vignette prend ce qui reste.
    @State private var cartoucheHeight: CGFloat = 240

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
                let scale = tourScale(in: proxy.size)

                ZStack(alignment: .bottom) {
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
                    // Pendant la prise en main, l'application devient une
                    // vignette : réduite, cernée d'un filet, posée au-dessus du
                    // cartouche. Le texte ne recouvre plus l'écran qu'il
                    // présente, et l'écart entre les deux fait la rupture sans
                    // voile ni ombre. Chaque modificateur reste en place hors
                    // visite, à sa valeur neutre : en poser ou en retirer un
                    // changerait l'identité des onglets, qui se remonteraient.
                    .overlay {
                        if tour.isRunning {
                            Rectangle()
                                .strokeBorder(Ink.ruleSet, lineWidth: 1 / scale)
                                .allowsHitTesting(false)
                        }
                    }
                    .clipShape(TourWindowClip(isActive: tour.isRunning))
                    .scaleEffect(scale, anchor: .top)
                    .offset(y: tour.isRunning ? Self.tourWindowTop : 0)
                    .animation(reduceMotion ? nil : Self.tourMotion, value: scale)

                    cartouche
                        .onGeometryChange(for: CGFloat.self) { geometry in
                            geometry.size.height
                        } action: { height in
                            cartoucheHeight = height
                        }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .background(Ink.ground)

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
        // Le préambule de la prise en main : un compte neuf dit d'abord quelles
        // plateformes il a. La visite part quand la feuille a fini de se retirer.
        .sheet(
            isPresented: Binding(get: { tour.asksPlatforms }, set: { _ in }),
            onDismiss: { tour.platformsSheetDidDismiss() }
        ) {
            OnboardingPlatformsSheet(onContinue: { tour.answerPlatforms() })
                .environmentObject(libraryStore)
                .environment(catalog)
        }
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

    /// L'écart entre le haut de l'écran et la vignette, et entre la vignette et
    /// le cartouche.
    private static let tourWindowTop: CGFloat = 12
    private static let tourWindowGap: CGFloat = 14
    /// Au-delà, la vignette ne se distingue plus assez de l'application en
    /// service ; en deçà de la valeur basse, elle ne se lit plus.
    private static let tourWindowMaxScale: CGFloat = 0.78
    private static let tourWindowMinScale: CGFloat = 0.45
    private static var tourMotion: Animation { .easeInOut(duration: 0.32) }

    /// L'échelle de la vignette : la hauteur laissée par le cartouche, bornée.
    /// Elle suit la hauteur du cartouche d'une étape à l'autre, en douceur.
    private func tourScale(in size: CGSize) -> CGFloat {
        guard tour.isRunning, size.height > 0 else { return 1 }
        let room = size.height - cartoucheHeight - Self.tourWindowTop - Self.tourWindowGap
        return min(Self.tourWindowMaxScale, max(Self.tourWindowMinScale, room / size.height))
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

/// Le cadre de la vignette. Inactif, il ne rogne rien : un `clipped()` qu'on
/// poserait seulement pendant la visite changerait la structure de la vue, et
/// les cinq onglets perdraient leur état en entrant et en sortant.
private struct TourWindowClip: Shape {
    var isActive: Bool

    func path(in rect: CGRect) -> Path {
        Path(isActive ? rect : rect.insetBy(dx: -4000, dy: -4000))
    }
}
