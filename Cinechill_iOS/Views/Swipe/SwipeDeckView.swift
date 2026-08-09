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
    @Environment(\.scenePhase) private var scenePhase

    /// Distance à parcourir pour valider un verdict.
    private static let sideThreshold: CGFloat = 105
    private static let upThreshold: CGFloat = 130
    private static let deckHorizontalInset: CGFloat = 26
    private static let deckVerticalInset: CGFloat = 12
    /// Débord vers le bas des deux cartes empilées sous celle du dessus.
    private static let backingCardsOverhang: CGFloat = 24

    @State private var drag: CGSize = .zero
    @State private var departing: [DepartingCard] = []
    @State private var isSynopsisOpen = false
    @State private var showProfile = false
    /// La démonstration des gestes tient la carte du dessus le temps de sa
    /// séquence — voir `SwipeIntroSequence`.
    @State private var isIntroPlaying = false

    @AppStorage("swipe.introPlayed") private var introPlayed = false

    var body: some View {
        NavigationStack {
            ZStack {
                Ink.ground.ignoresSafeArea()

                VStack(spacing: 0) {
                    statusBar
                    deckArea
                    footer
                }
            }
            .safeAreaInset(edge: .top) {
                AppHeaderView(title: String(localized: "Découvrir", bundle: .app), onProfileTap: { showProfile = true })
            }
            .navigationBarHidden(true)
            .overlay { milestoneOverlay }
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
            await model.start()
            await startIntro()
        }
        .onChange(of: libraryIDs) { _, ids in
            model.syncLibrary(ids)
        }
        // Une démonstration jouée écran éteint serait une démonstration perdue :
        // elle se remet en attente avec l'application, et repart avec elle.
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active else {
                Task { await startIntro() }
                return
            }
            suspendIntro()
            Task { await model.flushPending() }
        }
        // L'onglet reste monté quand on le quitte (voir `MainTabView`), donc
        // `onDisappear` ne suffit pas : c'est le changement d'onglet qui dit
        // qu'il faut envoyer la décision restée en main — et, au retour, qu'il
        // faut reprendre la démonstration si elle n'a pas été vue.
        .onChange(of: selectedTab) { _, tab in
            if tab == 2 {
                Task { await startIntro() }
            } else {
                suspendIntro()
                Task { await model.flushPending() }
            }
        }
        // Les réglages s'ouvrent depuis l'en-tête de cet écran, et c'est de là
        // qu'on réarme la démonstration : elle doit donc pouvoir repartir dès la
        // fermeture, sans avoir à quitter l'onglet.
        .onChange(of: showProfile) { _, isOpen in
            if isOpen {
                suspendIntro()
            } else {
                Task { await startIntro() }
            }
        }
        .onDisappear {
            Task { await model.flushPending() }
        }
    }

    // MARK: - Bandeau de session

    private var statusBar: some View {
        HStack(spacing: 9) {
            if model.addedThisSession > 0 {
                PlanLight()
                Text(String(localized: "\(model.addedThisSession) ajoutés", bundle: .app))
                    .planLabel()
                    .monospacedDigit()
                    .foregroundStyle(Ink.ink2)
                    .contentTransition(.numericText())
                    .transition(.opacity)
            }

            Spacer()

            if model.canUndo {
                Button {
                    Haptics.impact(.light)
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.75)) {
                        model.undo()
                    }
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
        }
        .frame(height: 34)
        .padding(.horizontal, Metrics.margin)
        .padding(.top, 6)
        .animation(Metrics.shift, value: model.addedThisSession)
        .animation(Metrics.shift, value: model.canUndo)
    }

    // MARK: - Le deck

    private var deckArea: some View {
        GeometryReader { proxy in
            let card = cardSize(in: proxy.size)

            ZStack {
                if model.cards.isEmpty {
                    placeholderState
                        .padding(.horizontal, 32)
                } else {
                    cardStack(size: card)
                }

                ForEach(departing) { item in
                    DepartingCardView(item: item, size: card) {
                        departing.removeAll { $0.id == item.id }
                    }
                }

                // La démonstration emprunte la carte du dessus et la joue
                // au-dessus de la pile restée en place : à la dernière image, il
                // n'y a donc rien à raccorder — le fondu suffit.
                if isIntroPlaying, let topCard = model.topCard {
                    SwipeIntroSequence(card: topCard, cardSize: card, onFinished: endIntro)
                        // Rien à fondre à l'entrée : la carte de la démonstration
                        // est celle qui vient d'être retirée de la pile, au même
                        // endroit et à la même taille. Un fondu d'entrée ferait
                        // clignoter le deck ; c'est à la sortie qu'il sert, pour
                        // éteindre les repères.
                        .transition(.asymmetric(insertion: .identity, removal: .opacity))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
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
        let width = max(0, min(usableWidth, usableHeight * 2 / 3))
        return CGSize(width: width, height: width * 3 / 2)
    }

    private func cardStack(size: CGSize) -> some View {
        ZStack {
            ForEach(Array(model.backingCards.enumerated()).reversed(), id: \.element.id) { index, card in
                SwipeCardView(card: card)
                    .frame(width: size.width, height: size.height)
                    .scaleEffect(backingScale(at: index))
                    .offset(y: CGFloat(index + 1) * 12)
                    .opacity(index == 0 ? 1 : 0.7)
                    .allowsHitTesting(false)
            }

            // Pendant la démonstration, la carte du dessus est jouée par
            // `SwipeIntroSequence` : la dessiner deux fois la dédoublerait.
            if let card = model.topCard, !isIntroPlaying {
                SwipeCardView(
                    card: card,
                    verdict: currentVerdict?.verdict,
                    verdictIntensity: currentVerdict?.intensity ?? 0,
                    isSynopsisOpen: isSynopsisOpen,
                    onTap: toggleSynopsis
                )
                .frame(width: size.width, height: size.height)
                .offset(x: drag.width, y: drag.height)
                .rotationEffect(.degrees(Double(drag.width) / 24), anchor: .bottom)
                .gesture(dragGesture)
                .id(card.id)
                .transition(.identity)
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: model.topCard?.id)
        .animation(.easeOut(duration: 0.2), value: isSynopsisOpen)
    }

    private func backingScale(at index: Int) -> CGFloat {
        let base = 1 - 0.05 * CGFloat(index + 1)
        guard index == 0 else { return base }
        // La carte suivante se rapproche à mesure que celle du dessus s'en va :
        // le deck a l'air de respirer plutôt que de sauter d'un cran.
        return base + 0.05 * dragProgress
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
                    Text("On prépare votre sélection…", bundle: .app)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Ink.ink3)
                }
            } else if model.isExhausted {
                PlanEmptyState(
                    icon: .hall,
                    title: String(localized: "Vous avez fait le tour", bundle: .app),
                    message: String(localized: "Les films écartés reviendront plus tard. En attendant, votre galerie a de quoi faire.", bundle: .app),
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

    // MARK: - Pied

    /// Le pied ne porte plus de légende — la démonstration a remplacé la notice.
    /// Il garde sa hauteur, et n'accueille que la sortie de secours de cette
    /// démonstration : rien ne se déplace quand elle se termine.
    private var footer: some View {
        ZStack {
            if isIntroPlaying {
                Button {
                    Haptics.impact(.light, intensity: 0.6)
                    endIntro()
                } label: {
                    Text("Passer", bundle: .app)
                        .planLabel()
                        .foregroundStyle(Ink.ink3)
                        .padding(.horizontal, 16)
                        .contentShape(Rectangle().inset(by: -10))
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .frame(height: 26)
        .padding(.bottom, 8)
        .animation(.easeOut(duration: 0.3), value: isIntroPlaying)
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

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                if isSynopsisOpen {
                    withAnimation(.easeOut(duration: 0.15)) { isSynopsisOpen = false }
                }
                drag = value.translation
            }
            .onEnded { value in
                if let direction = resolvedDirection(
                    translation: value.translation,
                    predicted: value.predictedEndTranslation
                ) {
                    commit(direction, from: value.translation)
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        drag = .zero
                    }
                }
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

    private func commit(_ direction: SwipeDirection, from translation: CGSize) {
        guard let card = model.topCard else { return }

        Haptics.impact(.medium)
        departing.append(
            DepartingCard(card: card, direction: direction, start: translation)
        )
        drag = .zero
        isSynopsisOpen = false
        model.swipe(direction)
    }

    private func toggleSynopsis() {
        guard model.topCard?.overview?.isEmpty == false else { return }
        Haptics.impact(.light, intensity: 0.6)
        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
            isSynopsisOpen.toggle()
        }
    }

    // MARK: - La démonstration

    /// Lance la démonstration, une fois la première carte en main.
    ///
    /// Le délai laisse à l'affiche le temps d'arriver : une séquence qui commence
    /// sur un cadre vide ne démontre rien.
    private func startIntro() async {
        guard !introPlayed, !isIntroPlaying else { return }
        try? await Task.sleep(for: .milliseconds(360))
        guard !introPlayed, !isIntroPlaying, selectedTab == 2, model.topCard != nil else { return }
        withAnimation(.easeOut(duration: 0.3)) { isIntroPlaying = true }
    }

    /// Quitter l'onglet en cours de séquence ne la consomme pas : elle n'a pas
    /// été vue, elle reprendra au retour.
    private func suspendIntro() {
        guard isIntroPlaying else { return }
        isIntroPlaying = false
    }

    /// La séquence est allée au bout, ou l'utilisateur l'a coupée : dans les deux
    /// cas le geste est acquis, et le deck prend la main.
    private func endIntro() {
        guard isIntroPlaying else { return }
        introPlayed = true
        withAnimation(.easeOut(duration: 0.34)) { isIntroPlaying = false }
    }

    private var libraryIDs: Set<Int> {
        Set(libraryStore.galleryItems.map(\.tmdbId))
            .union(libraryStore.watchlistItems.map(\.tmdbId))
    }
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
}

private struct DepartingCardView: View {
    let item: DepartingCard
    let size: CGSize
    let onFinished: () -> Void

    @State private var offset: CGSize
    @State private var opacity: Double = 1

    init(item: DepartingCard, size: CGSize, onFinished: @escaping () -> Void) {
        self.item = item
        self.size = size
        self.onFinished = onFinished
        _offset = State(initialValue: item.start)
    }

    var body: some View {
        SwipeCardView(
            card: item.card,
            verdict: verdict,
            verdictIntensity: 1
        )
        .frame(width: size.width, height: size.height)
        .offset(offset)
        .rotationEffect(.degrees(Double(offset.width) / 24), anchor: .bottom)
        .opacity(opacity)
        .allowsHitTesting(false)
        .task {
            withAnimation(.easeOut(duration: 0.34)) {
                offset = exitOffset
                opacity = 0
            }
            try? await Task.sleep(for: .milliseconds(360))
            onFinished()
        }
    }

    private var verdict: SwipeVerdict {
        switch item.direction {
        case .right: .seen
        case .left: .notSeen
        case .up: .watchlist
        }
    }

    private var exitOffset: CGSize {
        switch item.direction {
        case .right: CGSize(width: 620, height: item.start.height + 40)
        case .left: CGSize(width: -620, height: item.start.height + 40)
        case .up: CGSize(width: item.start.width, height: -900)
        }
    }
}
