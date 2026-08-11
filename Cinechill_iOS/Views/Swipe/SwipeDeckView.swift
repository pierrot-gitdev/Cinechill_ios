//
//  SwipeDeckView.swift
//  Cinechill_iOS
//

import SwiftUI

struct SwipeDeckView: View {
    @Bindable var model: SwipeDeckViewModel
    @Binding var selectedTab: Int

    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var libraryStore: LibraryStore
    @EnvironmentObject private var profileStore: UserProfileStore
    @EnvironmentObject private var socialStore: SocialStore
    @Environment(BadgesViewModel.self) private var badgesModel
    @Environment(MediaCatalog.self) private var catalog
    @Environment(OnboardingTour.self) private var tour
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Distance à parcourir pour valider un verdict.
    private static let sideThreshold: CGFloat = 105
    private static let upThreshold: CGFloat = 130
    private static let deckHorizontalInset: CGFloat = 26
    private static let deckVerticalInset: CGFloat = 12
    /// Débord vers le bas des deux cartes empilées sous celle du dessus.
    private static let backingCardsOverhang: CGFloat = 24
    /// La proportion de la carte. Plus haute que l'affiche seule : la plaque de
    /// légende occupe le bas, et c'est ce qui rend à l'affiche une hauteur
    /// proche de la sienne au lieu de la rogner de moitié.
    private static let cardRatio: CGFloat = 1.62
    /// L'écart de position et d'échelle d'un cran de pile à l'autre.
    private static let deckStep: CGFloat = 12
    private static let deckScaleStep: CGFloat = 0.05

    @State private var drag: CGSize = .zero
    /// Le doigt s'est posé sur la moitié haute de la carte — c'est ce qui
    /// détermine autour de quel bord elle pivote.
    @State private var grabbedHigh = true
    /// Le seuil est franchi : lever le doigt tranche.
    @State private var isArmed = false
    @State private var departing: [DepartingCard] = []
    /// L'accusé de réception du dernier classement. Un seul à la fois : le
    /// suivant remplace le précédent plutôt que de s'empiler, sinon swiper vite
    /// remplirait le bas de l'écran d'une file de plaques.
    @State private var toast: ToastMark?
    /// Le retour d'une carte annulée : elle rentre par le bord d'où elle est
    /// sortie, elle ne réapparaît pas au centre.
    @State private var returnOffset: CGSize = .zero
    @State private var returnAngle: Double = 0
    @State private var lastCommitted: SwipeDirection?
    @State private var isSynopsisOpen = false
    @State private var showProfile = false
    /// L'aide aux gestes — voir `SwipeGuideOverlay`.
    @State private var showGuide = false

    /// L'aide s'ouvre d'elle-même à la première venue, et une seule fois : elle
    /// reste à un tap dans le plafond pour tout le reste de la vie de
    /// l'application.
    @AppStorage("swipe.guideSeen") private var guideSeen = false

    var body: some View {
        NavigationStack {
            ZStack {
                Ink.ground.ignoresSafeArea()

                VStack(spacing: 0) {
                    statusBar
                    deckArea
                }
            }
            .safeAreaInset(edge: .top) {
                AppHeaderView(title: String(localized: "Découvrir", bundle: .app), onProfileTap: { showProfile = true })
            }
            .navigationBarHidden(true)
            .overlay { milestoneOverlay }
            .overlay { guideOverlay }
            .fullScreenCover(isPresented: $showProfile) {
                ProfileView(badgesModel: badgesModel)
                    .environmentObject(profileStore)
                    .environmentObject(libraryStore)
                    .environmentObject(authService)
                    .environmentObject(socialStore)
            }
        }
        .task {
            model.syncLibrary(libraryIDs)
            // Le répertoire des genres ne conditionne pas le deck : la légende
            // s'écrira sans son genre plutôt que de retarder la première carte.
            Task { await catalog.loadIfNeeded() }
            // En parallèle du chargement, jamais devant : la planche doit
            // s'ouvrir pendant que le deck se remplit derrière elle, et non
            // retarder de 280 ms la première carte.
            Task { await openGuideOnFirstVisit() }
            await model.start()
        }
        .onChange(of: libraryIDs) { _, ids in
            model.syncLibrary(ids)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active else { return }
            Task { await model.flushPending() }
        }
        // L'onglet reste monté quand on le quitte (voir `MainTabView`), donc
        // `onDisappear` ne suffit pas : c'est le changement d'onglet qui dit
        // qu'il faut envoyer la décision restée en main. L'aide, elle, appartient
        // à cet écran et n'a pas à attendre derrière un autre.
        .onChange(of: selectedTab) { _, tab in
            guard tab != 2 else { return }
            closeGuide()
            Task { await model.flushPending() }
        }
        // L'étape « Découvrir » de la prise en main écrit les trois gestes : la
        // planche n'a plus rien à apprendre à quelqu'un qui vient de les lire,
        // et s'ouvrir à la première venue serait une seconde leçon pour la même
        // chose. Le « ? » reste là pour ceux qui voudront la revoir.
        .onChange(of: tour.step) { _, step in
            if step == .decouvrir { guideSeen = true }
        }
        .onDisappear {
            Task { await model.flushPending() }
        }
    }

    // MARK: - Bandeau de session

    private var statusBar: some View {
        HStack(spacing: 14) {
            if model.addedThisSession > 0 {
                SessionTally(count: model.addedThisSession)
                    .transition(.opacity)
            }

            Spacer()

            if model.canUndo {
                Button {
                    undo()
                } label: {
                    Text("Annuler", bundle: .app)
                        .font(.system(size: 12))
                        .foregroundStyle(Ink.ink2)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(Ink.ruleSet).frame(height: 1).offset(y: 2)
                        }
                        .contentShape(Rectangle().inset(by: -12))
                }
                .buttonStyle(.plain)
                .transition(.opacity)
                .accessibilityLabel(String(localized: "Annuler le dernier swipe", bundle: .app))
            }

            helpButton
        }
        .frame(height: 34)
        .padding(.horizontal, Metrics.margin)
        .padding(.top, 6)
        .animation(Metrics.shift, value: model.addedThisSession)
        .animation(Metrics.shift, value: model.canUndo)
    }

    /// Le « ? », en haut à droite de la vue.
    ///
    /// Il est le seul élément permanent du bandeau — le compteur et l'annulation
    /// vont et viennent, lui reste, et c'est ce qui en fait un repère plutôt qu'un
    /// bouton qu'on cherche. Posé le dernier de la rangée, il ne bouge donc
    /// jamais : « Annuler » apparaît à sa gauche.
    ///
    /// Les trois directions ne sont pas devinables et l'écran n'a aucune autre
    /// place où les écrire — une légende permanente sous le deck a déjà été
    /// essayée, et retirée pour ça.
    private var helpButton: some View {
        Button {
            Haptics.impact(.light, intensity: 0.6)
            withAnimation(.easeOut(duration: 0.2)) { showGuide = true }
        } label: {
            SwipeHelpGlyph()
                .foregroundStyle(showGuide ? Ink.ink : Ink.ink2)
                // La cible déborde le tracé : 17 pt ne se touchent pas.
                .frame(width: 34, height: 34, alignment: .trailing)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableScaleStyle(scale: 0.9))
        .accessibilityLabel(String(localized: "Revoir les gestes", bundle: .app))
        // Le tracé n'occupe pas toute sa grille : il laisse 4 pt de vide à sa
        // droite. Sans ce retrait, le « ? » s'alignerait sur son cadre et non sur
        // son encre, et rentrerait de 4 pt par rapport à tout le reste de l'écran.
        .padding(.trailing, -4)
    }

    // MARK: - Le deck

    private var deckArea: some View {
        GeometryReader { proxy in
            let card = cardSize(in: proxy.size)

            ZStack {
                if displayedCards.isEmpty {
                    placeholderState
                        .padding(.horizontal, 32)
                } else {
                    cardStack(size: card)
                }

                ForEach(departing) { item in
                    DepartingCardView(item: item, size: card, genre: genre(for: item.card)) {
                        departing.removeAll { $0.id == item.id }
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            // Le toast est posé sur le haut du **deck**, et non sur le haut de
            // l'écran : le bandeau au-dessus porte l'annulation, et la masquer
            // pendant la seconde et demie qui suit un classement serait la
            // masquer précisément au moment où on s'en sert. Ici il ne recouvre
            // que le haut de l'affiche.
            .overlay(alignment: .top) { toastLayer }
        }
    }

    /// Taille de carte calculée à partir de la place réellement disponible.
    ///
    /// Explicite, et non déduite d'un `aspectRatio` qui se propagerait à
    /// travers la pile de vues : c'est ce qui garantit que la carte ne peut
    /// pas déborder, quelle que soit la taille proposée par le parent.
    private func cardSize(in available: CGSize) -> CGSize {
        let usableWidth = available.width - Self.deckHorizontalInset * 2
        // Les cartes du dessous débordent vers le bas, il leur faut leur place.
        let usableHeight = available.height - Self.deckVerticalInset * 2 - Self.backingCardsOverhang
        let width = max(0, min(usableWidth, usableHeight / Self.cardRatio))
        return CGSize(width: width, height: width * Self.cardRatio)
    }

    /// Les cartes affichées.
    ///
    /// Pendant la prise en main, ce sont trois films d'exemple : le deck réel
    /// arrive par le réseau, et l'étape qui explique les trois gestes ne peut
    /// pas se jouer devant une roue de chargement ou un message d'erreur. Le
    /// vrai deck continue de se remplir derrière — il sera prêt à la sortie.
    private var displayedCards: [SwipeCard] {
        tour.isRunning ? OnboardingShowcase.deck : model.cards
    }

    private func cardStack(size: CGSize) -> some View {
        // Les deux cartes qu'on voit dépasser sous celle du dessus.
        let backing = Array(displayedCards.dropFirst().prefix(2))

        return ZStack {
            ForEach(Array(backing.enumerated()).reversed(), id: \.element.id) { index, card in
                let step = depth(at: index)

                SwipeCardView(card: card, genre: genre(for: card))
                    .frame(width: size.width, height: size.height)
                    .scaleEffect(1 - Self.deckScaleStep * step)
                    .offset(y: Self.deckStep * step)
                    .opacity(Self.deckOpacity(atDepth: step))
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }

            if let card = displayedCards.first {
                let pivot = SwipeMotion.pivot(for: drag, grabbedHigh: grabbedHigh)

                SwipeCardView(
                    card: card,
                    genre: genre(for: card),
                    verdict: currentVerdict?.verdict,
                    verdictIntensity: currentVerdict?.intensity ?? 0,
                    isArmed: isArmed,
                    isSynopsisOpen: isSynopsisOpen,
                    parallax: reduceMotion ? .zero : SwipeMotion.parallax(for: drag),
                    onTap: toggleSynopsis
                )
                .frame(width: size.width, height: size.height)
                .offset(x: drag.width + returnOffset.width, y: drag.height + returnOffset.height)
                .rotationEffect(.degrees(pivot.angle + returnAngle), anchor: pivot.anchor)
                .gesture(dragGesture(cardHeight: size.height))
                .id(card.id)
                .transition(.identity)
            }
        }
        // Le seul mouvement que le deck a encore à jouer de lui-même : un flick
        // court valide sans que la pile ait eu le temps d'arriver, et c'est ce
        // ressort qui rattrape le cran manquant. Un glissement mené jusqu'au
        // seuil, lui, ne déclenche rien ici — la pile y est déjà.
        //
        // Le dépliage du synopsis, lui, est animé **dans** la carte et non ici :
        // refermer le synopsis se fait à la première image d'un glissement, et
        // un ressort posé à cette hauteur ferait traîner la carte derrière le
        // doigt pendant toute sa détente.
        .animation(SwipeMotion.advance, value: displayedCards.first?.id)
    }

    /// La profondeur d'une carte du dessous, en crans, **avancement du geste
    /// déduit**.
    ///
    /// C'est la pièce maîtresse de la fluidité du deck : chaque carte occupe la
    /// place de celle qui la précède à mesure que la carte du dessus s'en va. Au
    /// moment du lâcher, il n'y a donc plus un cran à franchir — la carte
    /// suivante est déjà exactement là où la carte du dessus va la remplacer, à
    /// la même échelle et à la même opacité, et le raccord est invisible.
    /// L'écran sautait d'un cran après coup, en 0,32 s, une fois la décision
    /// prise.
    private func depth(at index: Int) -> CGFloat {
        max(0, CGFloat(index + 1) - dragProgress)
    }

    /// La première carte du dessous est pleinement opaque — elle est le prochain
    /// film, pas un décor. Celles d'après s'éteignent, sans jamais disparaître :
    /// c'est ce qui donne au deck une épaisseur lisible.
    private static func deckOpacity(atDepth depth: CGFloat) -> Double {
        guard depth > 1 else { return 1 }
        return max(0.55, 1 - 0.3 * Double(depth - 1))
    }

    private var placeholderState: some View {
        Group {
            if let errorMessage = model.errorMessage {
                PlanEmptyState(
                    icon: .salle,
                    title: String(localized: "Impossible de charger les films", bundle: .app),
                    message: errorMessage,
                    actionTitle: String(localized: "Réessayer", bundle: .app),
                    action: { Task { await model.retry() } }
                )
            } else if model.isLoading {
                VStack(spacing: 16) {
                    CinechillSpinner(size: 34)
                    Text("On prépare ta sélection…", bundle: .app)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Ink.ink3)
                }
            } else if model.isExhausted {
                PlanEmptyState(
                    icon: .hall,
                    title: String(localized: "Tu as fait le tour", bundle: .app),
                    message: String(localized: "Les films écartés reviendront plus tard. En attendant, ta galerie a de quoi faire.", bundle: .app),
                    actionTitle: String(localized: "Voir ma galerie", bundle: .app),
                    action: { selectedTab = 3 },
                    secondaryTitle: String(localized: "Chercher encore", bundle: .app),
                    secondaryAction: { Task { await model.restart() } }
                )
            } else {
                Color.clear
            }
        }
    }

    // MARK: - L'aide aux gestes

    @ViewBuilder
    private var guideOverlay: some View {
        if showGuide {
            SwipeGuideOverlay(onClose: closeGuide)
                // La séquence tourne tant que la planche est là ; son retrait
                // annule la `task` qui la fait tourner.
                .transition(.opacity)
                .zIndex(20)
        }
    }

    /// L'accusé de réception. Il ne recouvre que le haut de l'affiche : la légende
    /// de la carte suivante — son titre, son année, sa note — est ce qu'on lit
    /// pour trancher, et elle vit dans la plaque du bas.
    @ViewBuilder
    private var toastLayer: some View {
        if let mark = toast {
            PlanToast(
                title: mark.title,
                destination: mark.destination,
                isAcquired: mark.isAcquired
            ) {
                if toast?.id == mark.id { toast = nil }
            }
            .id(mark.id)
            .padding(.horizontal, Metrics.margin)
            .padding(.top, 10)
        }
    }

    @ViewBuilder
    private var milestoneOverlay: some View {
        if let milestone = model.celebratedMilestone {
            ZStack {
                Ink.ground.opacity(0.55)
                    .ignoresSafeArea()
                SwipeMilestoneOverlay(count: milestone)
            }
            .transition(.opacity.combined(with: .scale(scale: 0.92)))
            .allowsHitTesting(false)
            .task(id: milestone) {
                Haptics.success()
                try? await Task.sleep(for: .milliseconds(1900))
                withAnimation(.easeOut(duration: 0.3)) {
                    model.celebratedMilestone = nil
                }
            }
        }
    }

    // MARK: - Geste

    /// Avancement du geste en cours vers son seuil, entre 0 et 1.
    private var dragProgress: CGFloat {
        currentVerdict.map { CGFloat($0.intensity) } ?? 0
    }

    private var currentVerdict: (verdict: SwipeVerdict, intensity: Double)? {
        let translation = drag
        let upward = -translation.height

        if upward > abs(translation.width), upward > 18 {
            return (.watchlist, min(1, Double(upward / Self.upThreshold)))
        }
        guard abs(translation.width) > 12 else { return nil }
        return (
            translation.width > 0 ? .seen : .notSeen,
            min(1, Double(abs(translation.width) / Self.sideThreshold))
        )
    }

    private func dragGesture(cardHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                // La carte est seule propriétaire de la courbe de son dépliage :
                // ici on n'a qu'à refermer, et sous condition — une écriture
                // d'état par image de geste invaliderait la vue pour rien.
                if isSynopsisOpen { isSynopsisOpen = false }
                // Relevé une seule fois par geste : le point d'appui d'une carte
                // ne change pas en cours de route.
                if drag == .zero {
                    grabbedHigh = value.startLocation.y < cardHeight / 2
                }

                drag = CGSize(
                    width: SwipeMotion.resisted(value.translation.width, threshold: Self.sideThreshold),
                    height: SwipeMotion.resisted(value.translation.height, threshold: Self.upThreshold)
                )
                updateArming()
            }
            .onEnded { value in
                if let direction = resolvedDirection(
                    translation: value.translation,
                    predicted: value.predictedEndTranslation
                ) {
                    commit(
                        direction,
                        velocity: CGSize(
                            width: value.predictedEndTranslation.width - value.translation.width,
                            height: value.predictedEndTranslation.height - value.translation.height
                        )
                    )
                } else {
                    isArmed = false
                    withAnimation(SwipeMotion.recenter) { drag = .zero }
                }
            }
    }

    /// Le seuil se sent avant de se voir : un cran tactile au franchissement, un
    /// autre, plus léger, quand on revient en arrière. Le tampon s'enclenche au
    /// même instant — c'est ce qui rend la limite négociable au doigt, sans
    /// jamais l'écrire.
    private func updateArming() {
        let armed = (dragProgress >= 1)
        guard armed != isArmed else { return }
        isArmed = armed
        if armed {
            Haptics.impact(.light, intensity: 0.85)
        } else {
            Haptics.selection()
        }
    }

    /// Un flick court mais rapide doit valider comme un long glissement : d'où
    /// la prise en compte de la translation projetée en plus de la réelle.
    private func resolvedDirection(translation: CGSize, predicted: CGSize) -> SwipeDirection? {
        let upward = max(-translation.height, -predicted.height)
        let horizontal = abs(translation.width) >= 24 ? translation.width : predicted.width

        if upward > Self.upThreshold, abs(horizontal) < upward * 0.8 {
            return .up
        }
        if abs(horizontal) > Self.sideThreshold {
            return horizontal > 0 ? .right : .left
        }
        return nil
    }

    private func commit(_ direction: SwipeDirection, velocity: CGSize) {
        guard let card = model.topCard else { return }

        Haptics.impact(.medium)
        let pivot = SwipeMotion.pivot(for: drag, grabbedHigh: grabbedHigh)
        departing.append(
            DepartingCard(
                card: card,
                direction: direction,
                // La carte reprend son vol exactement où le doigt l'a laissée —
                // position comprimée par la résistance comprise, sinon elle
                // sauterait en avant à l'instant du lâcher.
                start: drag,
                velocity: velocity,
                angle: pivot.angle,
                anchor: pivot.anchor,
                reduceMotion: reduceMotion
            )
        )
        lastCommitted = direction
        drag = .zero
        isArmed = false
        isSynopsisOpen = false
        model.swipe(direction)

        // Après `swipe`, parce que c'est lui qui sait si un palier vient d'être
        // franchi : la célébration plein écran dit déjà que le film est rangé, et
        // deux accusés de réception pour le même geste en font un de trop.
        if let confirmation = direction.confirmation, model.celebratedMilestone == nil {
            toast = ToastMark(
                title: card.title,
                destination: confirmation,
                isAcquired: direction.verdict.isFilled
            )
        }
    }

    /// Le retour arrière. La carte rentre par le bord d'où elle est sortie : sans
    /// ça, annuler fait apparaître un film au centre de l'écran, et rien ne dit
    /// que c'est celui qu'on vient d'écarter.
    private func undo() {
        Haptics.impact(.light)
        // Le film n'est plus rangé : sa confirmation ne doit pas rester à
        // l'écran une seconde de plus.
        toast = nil

        guard let direction = lastCommitted, !reduceMotion else {
            withAnimation(SwipeMotion.advance) { model.undo() }
            return
        }

        returnOffset = Self.returnOrigin(for: direction)
        returnAngle = Self.returnAngle(for: direction)
        model.undo()

        Task { @MainActor in
            // Une frame de battement, sinon SwiftUI regroupe l'insertion de la
            // carte et la remise à zéro dans la même passe : la carte serait
            // rendue directement en place, et ne reviendrait de nulle part.
            try? await Task.sleep(for: .milliseconds(16))
            withAnimation(SwipeMotion.advance) {
                returnOffset = .zero
                returnAngle = 0
            }
        }
    }

    private static func returnOrigin(for direction: SwipeDirection) -> CGSize {
        switch direction {
        case .right: CGSize(width: 520, height: 40)
        case .left: CGSize(width: -520, height: 40)
        case .up: CGSize(width: 0, height: -640)
        }
    }

    private static func returnAngle(for direction: SwipeDirection) -> Double {
        switch direction {
        case .right: 7
        case .left: -7
        case .up: 0
        }
    }

    private func toggleSynopsis() {
        guard model.topCard?.overview?.isEmpty == false else { return }
        Haptics.impact(.light, intensity: 0.6)
        isSynopsisOpen.toggle()
    }

    private func genre(for card: SwipeCard) -> String? {
        card.genreIds.lazy.compactMap { catalog.name(forGenre: $0) }.first
    }

    // MARK: - L'aide

    /// Ouvre l'aide à la toute première venue sur l'onglet.
    ///
    /// Le drapeau est posé **avant** l'animation, et non à la fermeture : quitter
    /// l'écran en cours de route ne doit pas condamner l'utilisateur à revoir la
    /// planche à chaque retour. Le « ? » est là pour ceux qui l'ont manquée.
    ///
    /// La courte attente laisse la bascule d'onglet se terminer — une planche qui
    /// arrive dans le même mouvement que l'écran se lit comme un raté d'animation.
    ///
    /// Pendant la prise en main, elle ne s'ouvre pas : l'étape « Découvrir »
    /// écrit déjà les trois gestes dans son cartouche, et une planche qui
    /// s'ouvrirait par-dessus recouvrirait la carte qu'on est en train de
    /// présenter.
    private func openGuideOnFirstVisit() async {
        guard !guideSeen, !tour.isRunning else { return }
        try? await Task.sleep(for: .milliseconds(280))
        guard !guideSeen, selectedTab == 2 else { return }
        guideSeen = true
        withAnimation(.easeOut(duration: 0.24)) { showGuide = true }
    }

    private func closeGuide() {
        guard showGuide else { return }
        withAnimation(.easeOut(duration: 0.22)) { showGuide = false }
    }

    private var libraryIDs: Set<Int> {
        Set(libraryStore.galleryItems.map(\.tmdbId))
            .union(libraryStore.watchlistItems.map(\.tmdbId))
    }
}

// MARK: - Le compteur de séance

/// Le compteur d'ajouts de la séance. Le point bat une fois à chaque film
/// rangé : c'est le seul endroit de l'écran où un chiffre change tout seul, et
/// un battement de 300 ms suffit à ce qu'on le remarque sans quitter la carte
/// des yeux.
private struct SessionTally: View {
    let count: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var beat: CGFloat = 1

    var body: some View {
        HStack(spacing: 9) {
            PlanLight()
                .scaleEffect(beat)

            Text(String(localized: "\(count) ajoutés", bundle: .app))
                .planLabel()
                .monospacedDigit()
                .foregroundStyle(Ink.ink2)
                .contentTransition(.numericText())
        }
        .task(id: count) {
            guard !reduceMotion else { return }
            beat = 1.9
            // Deux passes de rendu, sinon la mise à l'échelle et son retour se
            // regroupent et rien ne bat.
            try? await Task.sleep(for: .milliseconds(16))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.34, dampingFraction: 0.5)) { beat = 1 }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - La confirmation à l'écran

/// Un toast en cours d'affichage. L'identité est portée par un `UUID` et non par
/// le film : classer deux fois le même titre — après une annulation — doit bien
/// rejouer la confirmation.
private struct ToastMark: Identifiable {
    let id = UUID()
    let title: String
    let destination: String
    let isAcquired: Bool
}

// MARK: - Carte en cours de sortie

/// Une carte déjà tranchée, qui finit son vol pendant que le deck a déjà
/// avancé — c'est ce qui permet d'enchaîner les swipes sans attendre la fin de
/// l'animation précédente.
private struct DepartingCard: Identifiable {
    let id = UUID()
    let card: SwipeCard
    let direction: SwipeDirection
    let start: CGSize
    /// La course restante projetée au moment du lâcher. C'est elle qui donne au
    /// vol sa direction : une carte lancée en diagonale part en diagonale.
    let velocity: CGSize
    let angle: Double
    let anchor: UnitPoint
    let reduceMotion: Bool
}

private struct DepartingCardView: View {
    let item: DepartingCard
    let size: CGSize
    let genre: String?
    let onFinished: () -> Void

    @State private var offset: CGSize
    @State private var angle: Double
    @State private var opacity: Double = 1

    init(item: DepartingCard, size: CGSize, genre: String?, onFinished: @escaping () -> Void) {
        self.item = item
        self.size = size
        self.genre = genre
        self.onFinished = onFinished
        _offset = State(initialValue: item.start)
        _angle = State(initialValue: item.angle)
    }

    var body: some View {
        SwipeCardView(
            card: item.card,
            genre: genre,
            verdict: item.direction.verdict,
            verdictIntensity: 1,
            isArmed: true
        )
        .frame(width: size.width, height: size.height)
        .offset(offset)
        .rotationEffect(.degrees(angle), anchor: item.anchor)
        .opacity(opacity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task {
            guard !item.reduceMotion else {
                withAnimation(.easeOut(duration: 0.2)) { opacity = 0 }
                try? await Task.sleep(for: .milliseconds(220))
                onFinished()
                return
            }

            withAnimation(SwipeMotion.flight) {
                offset = exitOffset
                // La carte continue de tourner en s'en allant : c'est ce qui la
                // fait lire comme lancée, et non comme tirée par un rail.
                angle = item.angle + spin
            }
            // La carte quitte le cadre avant de s'effacer. L'écran la faisait
            // fondre sur toute sa course, ce qui la faisait disparaître au milieu
            // de l'écran plutôt que sortir par un bord.
            withAnimation(.easeIn(duration: 0.14).delay(0.16)) { opacity = 0 }

            try? await Task.sleep(for: .milliseconds(340))
            onFinished()
        }
    }

    private var spin: Double {
        switch item.direction {
        case .right: 5
        case .left: -5
        case .up: item.start.width > 0 ? 3 : -3
        }
    }

    /// Le point de sortie, dans le sens du geste. La course perpendiculaire est
    /// reprise du lancer, bornée : un flick très oblique ne doit pas envoyer la
    /// carte à l'autre bout de la diagonale.
    private var exitOffset: CGSize {
        let travel: CGFloat = 680
        switch item.direction {
        case .right:
            return CGSize(width: travel, height: item.start.height + drift(item.velocity.height))
        case .left:
            return CGSize(width: -travel, height: item.start.height + drift(item.velocity.height))
        case .up:
            return CGSize(width: item.start.width + drift(item.velocity.width), height: -(size.height + 420))
        }
    }

    private func drift(_ velocity: CGFloat) -> CGFloat {
        min(220, max(-220, velocity * 0.5))
    }
}
