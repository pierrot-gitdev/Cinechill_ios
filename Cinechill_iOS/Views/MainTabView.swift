//
//  MainTabView.swift
//  Cinechill_iOS
//

import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    @Environment(OnboardingTour.self) private var tour
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(NotificationRouter.self) private var notificationRouter
    @Environment(\.scenePhase) private var scenePhase

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
    /// Le guichet des fenêtres : badges, Porte, feuilles et planches de
    /// Découvrir passent une à la fois, dans l'ordre de `PopupQueue.Kind`.
    @State private var popupQueue = PopupQueue()
    @State private var selectedTab = 0
    /// Onglets déjà ouverts au moins une fois. Ils restent montés pour garder
    /// leur état — position de scroll, pile de navigation, réponses en cours —
    /// mais ne sont construits qu'à la première visite, pour qu'ouvrir l'app ne
    /// déclenche pas les chargements des quatre autres onglets.
    @State private var mountedTabs: Set<Int> = [0]
    /// Ce qu'une notification a ouvert par-dessus les onglets.
    @State private var notificationSheet: NotificationSheet?
    /// La feuille qui précède la demande d'autorisation d'iOS.
    @State private var notificationPermission = NotificationPermission.shared
    /// La décision d'onboarding est prise. Avant, un toucher de notification
    /// attend : il ouvrirait une fiche que le parcours recouvrirait aussitôt.
    @State private var tourChecked = false

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
                                .environment(\.isSelectedTab, selectedTab == tab)
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
        .environment(popupQueue)
        .overlay(alignment: .top) { writeFailureToast }
        .overlay { celebrationOverlay }
        .overlay { doorOverlay }
        .overlay { onboarding }
        .onChange(of: selectedTab) { _, tab in
            mountedTabs.insert(tab)
        }
        // Le toucher d'une notification, rejoué dès que l'app peut l'accueillir.
        .onChange(of: notificationRouter.pending, initial: true) { _, _ in
            routeNotificationIfPossible()
        }
        .onChange(of: canRouteNotifications) { _, _ in
            routeNotificationIfPossible()
        }
        // Une bibliothèque qui ne répond pas (hors ligne) ne doit pas retenir
        // un toucher indéfiniment.
        .task {
            try? await Task.sleep(for: .seconds(8))
            tourChecked = true
        }
        .sheet(item: $notificationSheet) { sheet in
            NotificationSheetContent(sheet: sheet)
                .environmentObject(libraryStore)
                .environment(catalog)
                .environment(badgesModel)
                .environment(doorStore)
        }
        .sheet(item: notificationPromptBinding, onDismiss: { popupQueue.finish(.notificationPrompt) }) { moment in
            NotificationPromptSheet(moment: moment)
        }
        // Chaque annonce demande son tour au guichet. Deux badges d'affilée
        // repassent par lui : le second attend la respiration.
        .onChange(of: badgesModel.currentCelebration?.id, initial: true) { old, new in
            if old != nil { popupQueue.finish(.badge) }
            if new != nil { popupQueue.request(.badge) }
        }
        .onChange(of: doorStore.celebration, initial: true) { old, new in
            if old != nil { popupQueue.finish(.door) }
            if new != nil { popupQueue.request(.door) }
        }
        .onChange(of: notificationPermission.pendingPrompt, initial: true) { _, moment in
            guard moment != nil else {
                popupQueue.withdraw(.notificationPrompt)
                return
            }
            // Écartée parce qu'une autre fenêtre vient de partir : la demande
            // reviendra au prochain moment qui la justifie.
            if !popupQueue.request(.notificationPrompt) {
                notificationPermission.pendingPrompt = nil
            }
        }
        // « Ce soir ? » et les rappels se réécrivent à chaque départ, sur l'état
        // de la Porte et de la galerie à cet instant ; les rappels tombent au
        // retour, puisqu'on est revenu.
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .background:
                LocalReminders.appDidEnterBackground(
                    door: doorStore.door,
                    doorKnown: doorStore.hasMeasured || DoorState.cached != nil,
                    galleryFilmCount: libraryStore.hasLoadedGalleryOnce ? libraryStore.galleryFilms.count : 0
                )
            case .active:
                LocalReminders.appDidBecomeActive()
            default:
                break
            }
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
            // jamais et personne ne serait jamais pris en main, ni aucune
            // référence de badges posée : le premier badge de la session
            // aurait alors servi de référence au lieu d'être fêté.
            if libraryStore.hasLoadedGalleryOnce {
                Task { await badgesModel.checkForNewAchievements(galleryCount: libraryStore.galleryFilms.count) }
                await startTourIfNeeded()
            }
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

    /// Une écriture de la bibliothèque qui n'a pas abouti. Le bouton touché est
    /// déjà revenu à son état d'avant : ce mot dit pourquoi, quel que soit
    /// l'onglet d'où elle est partie.
    @ViewBuilder
    private var writeFailureToast: some View {
        if let failure = libraryStore.writeFailure {
            PlanToast(
                title: String(localized: "Pas enregistré", bundle: .app),
                destination: String(localized: "Vérifie ta connexion et réessaie.", bundle: .app),
                showsMark: false
            ) {
                libraryStore.acknowledgeWriteFailure(failure)
            }
            .id(failure)
            .padding(.horizontal, Metrics.margin)
            .padding(.top, 10)
            .task(id: failure) {
                // Le toast se tait pour ne pas doubler l'annonce du deck ; un
                // échec, lui, n'est annoncé par personne d'autre.
                AccessibilityNotification.Announcement(
                    String(localized: "Pas enregistré. Vérifie ta connexion et réessaie.", bundle: .app)
                ).post()
            }
        }
    }

    /// La demande d'autorisation des notifications, à son tour seulement.
    private var notificationPromptBinding: Binding<NotificationPermission.Moment?> {
        Binding(
            get: { popupQueue.current == .notificationPrompt ? notificationPermission.pendingPrompt : nil },
            set: { if $0 == nil { notificationPermission.pendingPrompt = nil } }
        )
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
        // Les « Pas aimé » aussi : l'étape des déceptions en dépend.
        let disliked = libraryStore.galleryItems.filter { $0.dislikedAt != nil }.count
        return "\(gallery)-\(libraryStore.lovedCount)-\(watchlist)-\(seasons)-\(lovedSeasons)-\(queued)-\(disliked)"
    }

    // MARK: - L'onboarding

    private func startTourIfNeeded() async {
        await tour.startIfNeeded(
            galleryCount: libraryStore.galleryFilms.count,
            watchlistCount: libraryStore.watchlistFilms.count
        )
        tourChecked = true
    }

    // MARK: - Les notifications

    private var canRouteNotifications: Bool {
        tourChecked && !tour.isRunning
    }

    /// Une destination de notification devient un onglet, une feuille, ou le
    /// panneau des recommandations de l'en-tête.
    private func routeNotificationIfPossible() {
        guard canRouteNotifications, let destination = notificationRouter.consume() else { return }
        // Une feuille ou un plein écran ouvert ailleurs (le profil, une
        // recommandation en cours) cachait la destination, ou empêchait la
        // feuille de la notification de se présenter. Il se ferme d'abord.
        guard !dismissForeignPresentation() else {
            Task {
                try? await Task.sleep(for: .milliseconds(450))
                route(destination)
            }
            return
        }
        route(destination)
    }

    private func route(_ destination: NotificationRouter.Destination) {
        switch destination {
        case .suggestions:
            showTab(0)
            notificationRouter.requestPanel()
        case .cinematch:
            showTab(1)
        case .decouvrir:
            showTab(2)
        case .profile(let uid):
            presentNotificationSheet(.profile(uid: uid))
        case .item(let item):
            presentNotificationSheet(.item(item, asksVerdict: false))
        case .verdict(let item):
            presentNotificationSheet(.item(item, asksVerdict: true))
        case .followers:
            presentNotificationSheet(.followers)
        }
    }

    /// Ferme ce qui est présenté par-dessus les onglets, sauf la feuille d'une
    /// notification précédente, que `presentNotificationSheet` remplace
    /// lui-même. Vrai si quelque chose se ferme.
    private func dismissForeignPresentation() -> Bool {
        guard notificationSheet == nil,
              let root = UIApplication.shared.connectedScenes
                .compactMap({ ($0 as? UIWindowScene)?.keyWindow })
                .first?.rootViewController,
              root.presentedViewController != nil
        else { return false }
        root.dismiss(animated: true)
        return true
    }

    private func showTab(_ tab: Int) {
        notificationSheet = nil
        mountedTabs.insert(tab)
        selectedTab = tab
    }

    /// Une seconde notification touchée pendant qu'une première feuille est
    /// ouverte la remplace : iOS ne présente pas deux feuilles à la fois, on
    /// laisse donc la première partir.
    private func presentNotificationSheet(_ sheet: NotificationSheet) {
        guard notificationSheet != nil else {
            notificationSheet = sheet
            return
        }
        notificationSheet = nil
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            notificationSheet = sheet
        }
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
            // Mouvement réduit : le parcours s'efface au lieu de descendre.
            .transition(reduceMotion ? .opacity : .move(edge: .bottom))
            .zIndex(20)
        }
    }

    // MARK: - Chrome

    @ViewBuilder
    private var celebrationOverlay: some View {
        if popupQueue.current == .badge, let celebration = badgesModel.currentCelebration {
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
    /// Il attend son tour au guichet : la galerie qui grossit peut déclencher
    /// un badge et une étape d'un même geste, et l'étape passe la première.
    @ViewBuilder
    private var doorOverlay: some View {
        if popupQueue.current == .door, let key = doorStore.celebration {
            let format: MediaFormat = doorStore.celebrationDoor.series ? .series : .film
            DoorCelebrationOverlay(
                door: doorStore.celebrationDoor,
                unlocked: key,
                onDismiss: dismissDoorCelebration,
                onShowDoor: {
                    dismissDoorCelebration()
                    doorStore.post(.showDoor(format))
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
