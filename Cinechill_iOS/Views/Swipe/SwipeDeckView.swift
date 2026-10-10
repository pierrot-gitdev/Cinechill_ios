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
    @Environment(DoorStore.self) private var doorStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Distance à parcourir pour valider un verdict.
    private static let sideThreshold: CGFloat = 105
    private static let upThreshold: CGFloat = 130
    private static let deckHorizontalInset: CGFloat = 26
    private static let deckVerticalInset: CGFloat = 12
    /// Débord vers le bas des deux cartes empilées sous celle du dessus.
    private static let backingCardsOverhang: CGFloat = 24
    /// La proportion de la carte. Plus haute qu'une affiche, qui est en 2:3 :
    /// la plaque de légende prend le bas, l'affiche tient dans ce qui reste à
    /// ses propres proportions. Resserrer la carte sur l'affiche ne la
    /// grandirait pas : le titre se replierait sur plus de lignes, la plaque
    /// monterait d'autant, et l'affiche perdrait plus qu'elle ne gagne.
    private static let cardRatio: CGFloat = 1.62
    /// L'écart de position et d'échelle d'un cran de pile à l'autre.
    private static let deckStep: CGFloat = 12
    private static let deckScaleStep: CGFloat = 0.05

    @State private var drag: CGSize = .zero
    /// Le doigt est posé sur la carte de tête, avant même d'avoir bougé.
    @State private var isPressing = false
    /// Le rappel des trois issues, joué à chaque arrivée sur l'écran.
    @State private var showsReminder = false
    /// Incrémenté à chaque arrivée : c'est lui qui relance le rappel, et qui
    /// annule celui d'une arrivée précédente resté en cours.
    @State private var arrival = 0
    /// Le doigt s'est posé sur la moitié haute de la carte — c'est ce qui
    /// détermine autour de quel bord elle pivote.
    @State private var grabbedHigh = true
    /// Le seuil est franchi : lever le doigt tranche.
    @State private var isArmed = false
    /// Ramené sur la carte suivante après une décision prise par VoiceOver.
    @AccessibilityFocusState private var isCardFocused: Bool
    /// La démonstration de la prise en main en est au double tap : le cœur est
    /// posé sur la carte, qui ne part pas.
    @State private var isDemoLoving = false
    /// L'enfoncement de la carte sous les deux taps de la démonstration.
    @State private var demoPress: CGFloat = 1
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
    /// La saga proposée après un « vu », s'il y en a une.
    @State private var sagaOffer: SagaOffer?
    /// Les sagas déjà proposées depuis l'ouverture de l'onglet. Une saga ne se
    /// propose qu'une fois : passé le premier refus, ses opus partent en
    /// retrait côté serveur et ne reviennent plus la poser.
    @State private var offeredSagas: Set<String> = []

    /// L'aide s'ouvre d'elle-même à la première venue, et une seule fois : elle
    /// reste à un tap dans le plafond pour tout le reste de la vie de
    /// l'application.
    @AppStorage("swipe.guideSeen") private var guideSeen = false

    /// Le rappel du coup de cœur. La planche des gestes ne s'ouvre qu'une fois,
    /// et le double tap est le seul geste qu'on ne devine pas : on le rappelle
    /// sur la carte à qui range des films vus à la file sans jamais en adorer
    /// un. Une fois par jour au plus, et plus du tout une fois le geste pris.
    @AppStorage("swipe.loveHint.doubleTaps") private var doubleTapLoves = 0
    @AppStorage("swipe.loveHint.day") private var loveHintDay = ""
    @State private var seenWithoutLove = 0
    @State private var showsLoveHint = false
    private static let loveHintStreak = 8
    private static let loveHintRetiredAfter = 5

    /// Le palier de la galerie tant que CinéMatch est fermé.
    @State private var goalMilestone: Int?
    /// La galerie au moment du premier film rangé de la session : le palier se
    /// compte à partir d'elle, plus les films rangés depuis. La galerie seule
    /// retarde d'une carte (la dernière décision reste en main jusqu'à la
    /// suivante) et peut sauter d'un coup à son chargement, ce qui ferait
    /// fêter un palier qu'aucun geste n'a franchi.
    @State private var goalBase: Int?
    /// Films ou séries : le réglage que Découvrir partage avec CinéMatch.
    @AppStorage(MediaFormat.storageKey) private var formatRaw = MediaFormat.film.rawValue

    private var format: MediaFormat { MediaFormat(rawValue: formatRaw) ?? .film }

    var body: some View {
        NavigationStack {
            ZStack {
                Ink.ground.ignoresSafeArea()

                VStack(spacing: 0) {
                    statusBar
                    goalLine
                    deckArea
                }
            }
            .safeAreaInset(edge: .top) {
                AppHeaderView(title: String(localized: "Découvrir", bundle: .app), onProfileTap: { showProfile = true })
            }
            .navigationBarHidden(true)
            .overlay { milestoneOverlay }
            .overlay { goalMilestoneOverlay }
            .overlay { guideOverlay }
            .fullScreenCover(isPresented: $showProfile) {
                ProfileView(badgesModel: badgesModel)
                    .environmentObject(profileStore)
                    .environmentObject(libraryStore)
                    .environmentObject(authService)
                    .environmentObject(socialStore)
            }
            // La feuille ne coupe pas le rythme : le balayage est déjà
            // tranché, la carte déjà partie, et la carte suivante est déjà en
            // place derrière. Deux feuilles d'affilée sont par ailleurs très
            // improbables — les cartes issues de la règle de saga portent
            // toutes la même source, que l'ordonnancement du lot écarte les
            // unes des autres.
            .sheet(item: $sagaOffer) { offer in
                SagaSheet(offer: offer, onClose: { sagaOffer = nil })
                    .environmentObject(libraryStore)
            }
        }
        .task {
            model.prepare(format: format)
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
        // L'interrupteur a pu basculer ici ou dans CinéMatch : le deck suit.
        .onChange(of: formatRaw) { _, _ in
            toast = nil
            Task { await model.setFormat(format) }
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
            // L'arrivée sur l'onglet est le seul moment où la planche peut
            // s'ouvrir. Le `.task` de la vue ne suffit pas : l'onglet reste
            // monté une fois quitté, donc il ne se rejoue jamais — et c'est
            // précisément par une arrivée que la visite guidée se termine,
            // puisqu'elle dépose ici en se refermant.
            guard tab != 2 else {
                Task { await openGuideOnFirstVisit() }
                arrival &+= 1
                return
            }
            closeGuide()
            Task { await model.flushPending() }
        }
        // Au tout premier lancement, l'écran arrive avant ses cartes : la
        // requête tourne encore, il n'y a pas de carte de tête, donc pas de
        // boussole à montrer — et les cinq secondes s'écoulaient dans le vide.
        // L'apparition de la première carte vaut donc arrivée, au même titre
        // qu'un retour sur l'onglet.
        .onChange(of: displayedCards.isEmpty) { wasEmpty, isEmpty in
            guard wasEmpty, !isEmpty else { return }
            arrival &+= 1
        }
        // `.task(id:)` annule le rappel de l'arrivée précédente avant de jouer
        // le suivant : sans ça, deux allers-retours rapides sur l'onglet
        // laisseraient deux comptes à rebours se marcher dessus.
        .task(id: arrival) { await playReminder() }
        // La prise en main montre les trois gestes sur la carte elle-même.
        .task(id: isShowingTourDemo) { await playTourDemo() }
        .onDisappear {
            Task { await model.flushPending() }
        }
    }

    // MARK: - Bandeau de session

    private var statusBar: some View {
        HStack(spacing: 14) {
            // L'interrupteur prend la place du compte de session : ce qu'on
            // remplit compte plus que ce qu'on a fait depuis l'ouverture.
            FormatSwitch(isEnabled: !tour.isRunning)

            Spacer()

            if model.canUndo {
                Button {
                    undo()
                } label: {
                    // « Revenir », pas « Annuler » : la clé « Annuler » sert aussi
                    // aux feuilles, et l'anglais lisait « Cancel » pour « Undo ».
                    Text("Revenir", bundle: .app)
                        .planFont(12)
                        .foregroundStyle(Ink.ink2)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(Ink.ruleSet).frame(height: 1).offset(y: 2)
                        }
                        .contentShape(Rectangle().inset(by: -15))
                }
                .buttonStyle(PressableScaleStyle())
                .transition(.opacity)
                .accessibilityLabel(String(localized: "Annuler le dernier swipe", bundle: .app))
            }

            helpButton
        }
        .frame(minHeight: 34)
        .padding(.horizontal, Metrics.margin)
        // L'écart sous le filet de l'en-tête, le même que dans CinéMatch :
        // collé au filet, l'interrupteur se lisait comme une part du plafond.
        .padding(.top, 12)
        .animation(Metrics.shift, value: model.addedThisSession)
        .animation(Metrics.shift, value: model.canUndo)
    }

    // MARK: - Le but

    /// La Porte du format, écrite sous le bandeau tant qu'elle est fermée.
    ///
    /// Découvrir sert à ouvrir CinéMatch, et l'écran ne le disait pas : on
    /// balayait vers un but qu'on ne voyait pas. Un compteur qui avance est ce
    /// qui fait faire la carte suivante. Il disparaît une fois la Porte ouverte.
    @ViewBuilder
    private var goalLine: some View {
        let door = doorStore.door(for: format)
        if !door.unlocked, !tour.isRunning, let memory = door.artifact(.memoire) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(format == .series
                         ? String(localized: "\(min(memory.current, memory.target)) sur \(memory.target) séries", bundle: .app)
                         : String(localized: "\(min(memory.current, memory.target)) sur \(memory.target) films", bundle: .app))
                        .planLabel()
                        .monospacedDigit()
                        .foregroundStyle(Ink.ink)
                        .contentTransition(.numericText())
                    Spacer(minLength: 8)
                    Text("pour ouvrir CinéMatch", bundle: .app)
                        .planLabel()
                        .foregroundStyle(Ink.ink3)
                }
                PlanProgressRule(
                    fraction: memory.target > 0 ? Double(memory.current) / Double(memory.target) : 0
                )
            }
            .padding(.horizontal, Metrics.margin)
            .padding(.top, 8)
            .animation(Metrics.shift, value: memory.current)
            .accessibilityElement(children: .combine)
        }
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
                .frame(width: 44, height: 44, alignment: .trailing)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableScaleStyle(scale: 0.9))
        .accessibilityLabel(String(localized: "Revoir comment ça marche", bundle: .app))
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
            // La carte doit tenir entière sur l'écran : son texte s'arrête au
            // premier cran des tailles d'accessibilité. Posé sur toute la pile,
            // pour qu'une carte qui s'envole garde la taille de texte qu'elle
            // avait sous le doigt.
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
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
                    // Seule la carte du dessus se lit : les deux dessous
                    // répétaient titre et consigne.
                    .accessibilityHidden(true)
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
                    showsCompass: (isPressing || showsReminder) && !isSynopsisOpen,
                    compassEnabled: !isShowingTourDemo,
                    onTap: toggleSynopsis,
                    onDoubleTap: love
                )
                .frame(width: size.width, height: size.height)
                .overlay { if isShowingTourDemo { tourStamp } }
                .overlay { SwipeLoveBurst(isOn: isDemoLoving) }
                .overlay {
                    if showsLoveHint {
                        SwipeLoveHint()
                            .padding(.horizontal, 16)
                            .offset(y: -size.height * 0.06)
                            .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96)))
                            .task {
                                try? await Task.sleep(for: .seconds(5))
                                withAnimation(.easeOut(duration: 0.2)) { showsLoveHint = false }
                            }
                    }
                }
                .scaleEffect(demoPress)
                .offset(x: drag.width + returnOffset.width, y: drag.height + returnOffset.height)
                .rotationEffect(.degrees(pivot.angle + returnAngle), anchor: pivot.anchor)
                // Le geste n'existe pas pour VoiceOver ni Switch Control : les
                // trois issues y sont des actions, sans quoi le deck ne se
                // tranchait pas du tout.
                .accessibilityAction(named: Text("Vu", bundle: .app)) { accessibleCommit(.right) }
                .accessibilityAction(named: Text("Pas vu", bundle: .app)) { accessibleCommit(.left) }
                .accessibilityAction(named: Text("À voir", bundle: .app)) { accessibleCommit(.up) }
                .accessibilityFocused($isCardFocused)
                .gesture(dragGesture(cardHeight: size.height))
                // Le geste de décision ne part qu'au bout de huit points : il ne
                // sait donc rien du moment où le doigt se pose, qui est
                // justement celui où l'on hésite. Ce second geste, à distance
                // nulle et simultané, ne sert qu'à cet instant-là et ne décide
                // de rien.
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            guard !isPressing else { return }
                            withAnimation(SwipeMotion.unfold) { isPressing = true }
                        }
                        .onEnded { _ in releasePress() }
                )
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
                    title: format == .series
                        ? String(localized: "Impossible de charger les séries", bundle: .app)
                        : String(localized: "Impossible de charger les films", bundle: .app),
                    message: errorMessage,
                    actionTitle: String(localized: "Réessayer", bundle: .app),
                    action: { Task { await model.retry() } }
                )
            } else if model.isLoading {
                VStack(spacing: 16) {
                    CinechillSpinner(size: 34)
                    Text("On prépare ta sélection…", bundle: .app)
                        .planFont(12.5)
                        .foregroundStyle(Ink.ink3)
                }
            } else if model.isExhausted {
                PlanEmptyState(
                    icon: .hall,
                    title: format == .series
                        ? String(localized: "Plus de séries pour l'instant", bundle: .app)
                        : String(localized: "Plus de films pour l'instant", bundle: .app),
                    message: format == .series
                        ? String(localized: "Les séries que tu as passées reviendront plus tard.", bundle: .app)
                        : String(localized: "Les films que tu as passés reviendront plus tard.", bundle: .app),
                    actionTitle: String(localized: "Voir ma galerie", bundle: .app),
                    action: { selectedTab = 3 },
                    secondaryTitle: String(localized: "Chercher encore", bundle: .app),
                    secondaryAction: { Task { await model.restart() } }
                )
            } else {
                // Un lot vide isolé ne déclare pas l'épuisement : sans relance,
                // l'écran restait noir pour de bon.
                CinechillSpinner(size: 34)
                    .task { await model.start() }
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
                SwipeMilestoneOverlay(count: milestone, isSeries: format == .series)
            }
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.92)))
            .allowsHitTesting(false)
            .task(id: milestone) {
                Haptics.success()
                AccessibilityNotification.Announcement(
                    SwipeMilestoneOverlay.spokenText(count: milestone, isSeries: format == .series)
                ).post()
                try? await Task.sleep(for: .milliseconds(1900))
                withAnimation(.easeOut(duration: 0.3)) {
                    model.celebratedMilestone = nil
                }
            }
        }
    }

    @ViewBuilder
    private var goalMilestoneOverlay: some View {
        if let milestone = goalMilestone, let target = memoryArtifact?.target {
            ZStack {
                Ink.ground.opacity(0.55)
                    .ignoresSafeArea()
                SwipeGoalMilestoneOverlay(count: milestone, target: target, isSeries: format == .series)
            }
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96)))
            .allowsHitTesting(false)
            .task(id: milestone) {
                Haptics.success()
                AccessibilityNotification.Announcement(
                    SwipeGoalMilestoneOverlay.spokenText(count: milestone, target: target, isSeries: format == .series)
                ).post()
                // Plus long que le palier de session : il y a une phrase à lire.
                try? await Task.sleep(for: .milliseconds(2600))
                withAnimation(.easeOut(duration: 0.25)) {
                    goalMilestone = nil
                }
            }
        }
    }

    // MARK: - Geste

    /// Avancement du geste en cours vers son seuil, entre 0 et 1.
    private var dragProgress: CGFloat {
        currentVerdict.map { CGFloat($0.intensity) } ?? 0
    }

    // MARK: - La démonstration de la prise en main

    /// L'étape « Découvrir » de la visite est à l'écran.
    private var isShowingTourDemo: Bool {
        tour.step == .decouvrir && selectedTab == 2
    }

    /// Les gestes, joués sur la carte du dessus au lieu d'être écrits.
    ///
    /// La carte penche vers chaque direction jusqu'au seuil, le tampon
    /// s'allume, puis elle revient au centre. Le tour se termine par le double
    /// tap : la carte bat deux fois et le cœur s'y pose. **Elle ne part jamais** : rien
    /// n'est classé, et `commit` n'est jamais appelé. Le mouvement passe par
    /// `drag`, la même valeur que le doigt : inclinaison, parallaxe et tampon
    /// sont exactement ceux du vrai geste. Aucune vibration, elles ne partent
    /// que du geste réel.
    ///
    /// Sans danger ici, alors que `SwipeGuideOverlay` a renoncé à animer la
    /// vraie carte : pendant la visite l'application est inerte, réduite en
    /// vignette, et la carte est un film d'exemple.
    private func playTourDemo() async {
        guard isShowingTourDemo, !reduceMotion else { return }
        grabbedHigh = true
        try? await Task.sleep(for: .milliseconds(600))

        while !Task.isCancelled {
            for direction in [SwipeDirection.right, .left, .up] {
                let target: CGSize = switch direction {
                case .right: CGSize(width: Self.sideThreshold + 16, height: 0)
                case .left: CGSize(width: -(Self.sideThreshold + 16), height: 0)
                case .up: CGSize(width: 0, height: -(Self.upThreshold + 12))
                }
                withAnimation(.easeInOut(duration: 0.55)) { drag = target }
                try? await Task.sleep(for: .milliseconds(550))
                guard !Task.isCancelled else { break }

                withAnimation(SwipeMotion.lock) { isArmed = true }
                try? await Task.sleep(for: .milliseconds(750))
                guard !Task.isCancelled else { break }

                isArmed = false
                withAnimation(recenterMotion) { drag = .zero }
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled else { break }
            }
            guard !Task.isCancelled else { break }

            // Le double tap : deux battements de la carte, le cœur s'y pose,
            // puis s'efface. La carte reste au centre.
            for _ in 0 ..< 2 {
                withAnimation(.easeOut(duration: 0.08)) { demoPress = 0.96 }
                try? await Task.sleep(for: .milliseconds(90))
                withAnimation(.spring(response: 0.22, dampingFraction: 0.6)) { demoPress = 1 }
                try? await Task.sleep(for: .milliseconds(110))
            }
            withAnimation(SwipeLoveBurst.pop) { isDemoLoving = true }
            try? await Task.sleep(for: .milliseconds(1100))
            withAnimation(.easeOut(duration: 0.25)) { isDemoLoving = false }
            try? await Task.sleep(for: .milliseconds(700))
        }

        // L'étape a changé en plein mouvement : la carte revient au centre.
        isArmed = false
        isDemoLoving = false
        demoPress = 1
        withAnimation(recenterMotion) { drag = .zero }
    }

    /// Le tampon de la démonstration : les mots « VU », « PAS VU », « À VOIR »,
    /// posés sur la carte du côté d'où elle part.
    ///
    /// Le dessin est celui de `SwipeGuideOverlay` (point plein pour l'acquis,
    /// creux pour le prévu, liseré à la teinte du verdict), en plus grand : la
    /// carte est réduite dans la vignette, et les repères de 10 pt de la boussole
    /// ne s'y lisaient plus.
    @ViewBuilder
    private var tourStamp: some View {
        if let current = currentVerdict {
            let verdict = current.verdict
            HStack(spacing: 8) {
                if verdict.isFilled {
                    PlanLight(tint: verdict.tint)
                } else {
                    PlanLightOutline(tint: verdict.tint)
                }
                Text(verdict.label)
                    .planFont(17, weight: .semibold)
                    .tracking(2)
            }
            .foregroundStyle(verdict.tint)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                Ink.ground.opacity(0.92),
                in: RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                    .strokeBorder(verdict.tint.opacity(isArmed ? 1 : 0.7), lineWidth: isArmed ? 1.5 : 1)
            )
            .scaleEffect(isArmed ? 1.06 : 1)
            .padding(18)
            // « À VOIR » au milieu de la carte, pas en haut : la carte monte, et
            // son bord haut passe sous l'en-tête de la vignette avec le tampon.
            // Les deux autres partent de côté, leurs coins hauts restent visibles.
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: verdict == .watchlist ? .center : verdict.alignment
            )
            .opacity(min(1, current.intensity * 1.4))
            .animation(SwipeMotion.lock, value: isArmed)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
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
                releasePress()
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
                    withAnimation(recenterMotion) { drag = .zero }
                }
            }
    }

    /// Le seuil se sent avant de se voir : un cran tactile au franchissement, un
    /// autre, plus léger, quand on revient en arrière. Le tampon s'enclenche au
    /// même instant — c'est ce qui rend la limite négociable au doigt, sans
    /// jamais l'écrire.
    /// Le rappel au centre garde son petit dépassement, sauf quand le
    /// mouvement est réduit : la carte revient alors sans rebond.
    private var recenterMotion: Animation {
        reduceMotion ? .smooth(duration: 0.2) : SwipeMotion.recenter
    }

    private func updateArming() {
        // Hystérésis : armée à 100 %, désarmée sous 90 %. Un doigt qui tremble
        // au seuil ne déclenche plus une salve de crans tactiles.
        let armed = isArmed ? dragProgress >= 0.9 : dragProgress >= 1
        guard armed != isArmed else { return }
        isArmed = armed
        if armed {
            Haptics.impact(.light, intensity: 0.85)
        } else {
            Haptics.selection()
        }
    }

    /// C'est la position projetée qui décide, comme le défilement d'iOS : un
    /// flick court mais rapide valide, une carte armée puis relancée vers le
    /// centre revient. La translation réelle ne sert qu'à vérifier que le
    /// doigt est bien parti dans ce sens. Une carte armée ne se désarme qu'à
    /// 90 % du seuil, la même règle que `updateArming`.
    private func resolvedDirection(translation t: CGSize, predicted p: CGSize) -> SwipeDirection? {
        let side = Self.sideThreshold * (isArmed ? 0.9 : 1)
        let rise = Self.upThreshold * (isArmed ? 0.9 : 1)
        let up = -p.height
        if up > rise, abs(p.width) < up * 0.8, -t.height > 12 {
            return .up
        }
        if abs(p.width) > side, abs(t.width) > 12, (p.width > 0) == (t.width > 0) {
            return p.width > 0 ? .right : .left
        }
        return nil
    }

    /// Une décision prise sans geste (VoiceOver, Switch Control), annoncée
    /// puisque rien ne se voit partir.
    private func accessibleCommit(_ direction: SwipeDirection) {
        guard !tour.isRunning, let card = model.topCard else { return }
        commit(direction, velocity: .zero)
        let outcome = direction.confirmation ?? String(localized: "Il reviendra plus tard", bundle: .app)
        AccessibilityNotification.Announcement("\(card.title). \(outcome)").post()
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            isCardFocused = true
        }
    }

    private func commit(_ direction: SwipeDirection, loved: Bool = false, velocity: CGSize) {
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
                loved: loved,
                reduceMotion: reduceMotion
            )
        )
        lastCommitted = direction
        drag = .zero
        isArmed = false
        isSynopsisOpen = false
        model.sessionMilestonesEnabled = memoryIsDone
        model.swipe(direction, loved: loved)
        if case .right = direction {
            checkGoalMilestone()
            updateLoveHint(loved: loved)
        } else if showsLoveHint {
            withAnimation(.easeOut(duration: 0.15)) { showsLoveHint = false }
        }

        // La feuille de saga passe avant le toast : quand elle s'ouvre, c'est
        // elle qui accuse réception, et un toast qui descend pendant qu'elle
        // monte ferait deux accusés pour un geste.
        offerSagaIfAny(for: card, direction: direction)

        // Après `swipe`, parce que c'est lui qui sait si un palier vient d'être
        // franchi : la célébration plein écran dit déjà que le film est rangé, et
        // deux accusés de réception pour le même geste en font un de trop.
        if let confirmation = direction.confirmation, model.celebratedMilestone == nil,
           goalMilestone == nil, sagaOffer == nil {
            toast = ToastMark(
                title: card.title,
                // Le cœur s'ajoute à la destination, il ne la remplace pas :
                // le film est bien rangé en galerie, et le toast doit le dire.
                destination: card.isSeries
                    ? seasonConfirmation(direction) ?? confirmation
                    : (loved
                       ? String(localized: "Ajouté à ta galerie · Coup de cœur", bundle: .app)
                       : confirmation),
                isAcquired: direction.verdict.isFilled
            )
        }
    }

    /// Une carte de série range sa première saison, et le toast le dit : c'est
    /// elle, et pas la série, qui vient d'entrer.
    private func seasonConfirmation(_ direction: SwipeDirection) -> String? {
        switch direction {
        case .right: String(localized: "Saison 1 ajoutée à ta galerie", bundle: .app)
        case .up: String(localized: "Saison 1 ajoutée à ta watchlist", bundle: .app)
        case .left: nil
        }
    }

    /// La saga, proposée **après un « vu » seulement**.
    ///
    /// C'est la condition qui rend la feuille légitime : la personne vient de
    /// déclarer qu'elle connaît ce film, donc la question « et les autres ? » a
    /// un sens et peut rapporter sept films pour un tap. Après un « pas vu »,
    /// elle n'en aurait aucun — et le serveur met déjà la suite de la saga en
    /// retrait de lui-même.
    ///
    /// Une série est une saga de saisons : balayer « Dark » vers la droite
    /// range sa saison 1, et la même feuille propose les deux autres.
    private func offerSagaIfAny(for card: SwipeCard, direction: SwipeDirection) {
        guard case .right = direction else { return }
        // Un palier occupe déjà l'écran : deux planches l'une sur l'autre ne
        // se lisent pas, et la saga passe son tour.
        guard !tour.isRunning, model.celebratedMilestone == nil, goalMilestone == nil else { return }

        let offer: SagaOffer
        if card.hasSeasonsToOffer {
            offer = SagaOffer(source: .series(card.tmdbId), originID: card.mediaItem.id, title: card.title)
        } else if card.hasSagaToOffer, let collectionID = card.collectionID {
            offer = SagaOffer(source: .collection(collectionID), originID: card.mediaItem.id, title: card.title)
        } else {
            return
        }
        guard !offeredSagas.contains(offer.id) else { return }
        offeredSagas.insert(offer.id)
        sagaOffer = offer
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
            departing.removeAll { $0.card.id == model.topCard?.id }
            return
        }

        returnOffset = Self.returnOrigin(for: direction)
        returnAngle = Self.returnAngle(for: direction)
        model.undo()
        // La carte encore en vol disparaît : sinon on en voyait deux, l'une
        // qui finissait de sortir pendant que l'autre rentrait.
        departing.removeAll { $0.card.id == model.topCard?.id }

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

    /// Le coup de cœur : deux taps sur l'affiche valent « vu et adoré ».
    ///
    /// Il remplace le second cran du balayage à droite, qu'il fallait tirer
    /// jusqu'au bord de l'écran : un geste qu'on ne trouvait pas seul, et qu'on
    /// déclenchait parfois sans le vouloir en lançant fort. Le double tap est
    /// celui que tout le monde connaît pour « j'aime ».
    ///
    /// La carte part à droite, comme un « vu » : le cœur s'ajoute à la
    /// destination, il ne la remplace pas. Elle marque d'abord un temps sur
    /// place, le cœur posé dessus — voir `DepartingCardView`.
    private func love() {
        guard !tour.isRunning, drag == .zero, model.topCard != nil else { return }
        // La carte part sous le doigt : le geste de contact, lié à son
        // identité, ne recevrait jamais sa fin, et la boussole resterait
        // allumée sur la suivante.
        releasePress()
        doubleTapLoves += 1
        commit(.right, loved: true, velocity: CGSize(width: 240, height: 0))
    }

    // MARK: - Le rappel du coup de cœur

    /// Après un « vu » : le rappel part si l'on range des films à la file sans
    /// en adorer un, et s'efface au geste suivant, quel qu'il soit.
    private func updateLoveHint(loved: Bool) {
        if showsLoveHint {
            withAnimation(.easeOut(duration: 0.15)) { showsLoveHint = false }
        }
        guard !loved else {
            seenWithoutLove = 0
            return
        }
        seenWithoutLove += 1
        let today = Date.now.formatted(.iso8601.year().month().day())
        guard seenWithoutLove >= Self.loveHintStreak,
              doubleTapLoves < Self.loveHintRetiredAfter,
              loveHintDay != today,
              guideSeen, !tour.isRunning
        else { return }
        seenWithoutLove = 0
        loveHintDay = today
        // La carte suivante finit d'arriver avant que le rappel s'y pose.
        Task {
            try? await Task.sleep(for: .milliseconds(320))
            guard model.topCard != nil else { return }
            withAnimation(.easeOut(duration: 0.22)) { showsLoveHint = true }
        }
    }

    // MARK: - Le palier de la galerie

    private var memoryArtifact: DoorArtifact? {
        doorStore.door(for: format).artifact(.memoire)
    }

    private var memoryIsDone: Bool { memoryArtifact?.done == true }

    /// Ce que la Porte compte, d'après la bibliothèque locale : des films, ou
    /// des séries distinctes. La carte encore en main compte déjà.
    private var localMemoryCount: Int {
        let held = model.heldSeenCard
        if format == .series {
            var ids = Set(libraryStore.gallerySeasons.map(\.tmdbId))
            if let held, held.isSeries { ids.insert(held.tmdbId) }
            return ids.count
        }
        let films = libraryStore.galleryFilms
        guard let held, !held.isSeries, !films.contains(where: { $0.tmdbId == held.tmdbId }) else {
            return films.count
        }
        return films.count + 1
    }

    /// Le palier franchi par ce « vu », s'il y en a un, une fois par palier et
    /// par format dans la vie du compte : annuler puis reranger ne le refête pas.
    private func checkGoalMilestone() {
        guard !memoryIsDone, !tour.isRunning, let target = memoryArtifact?.target, target > 0 else { return }
        if model.addedThisSession <= 1 || goalBase == nil {
            goalBase = localMemoryCount - model.addedThisSession
        }
        let count = (goalBase ?? 0) + model.addedThisSession
        let storageKey = "swipe.goalMilestones.\(format.rawValue)"
        var celebrated = Set(UserDefaults.standard.array(forKey: storageKey) as? [Int] ?? [])
        guard let step = SwipeGoalMilestoneOverlay.steps(for: target).last(where: { $0 <= count }),
              count - step < 3, !celebrated.contains(step)
        else { return }
        celebrated.insert(step)
        UserDefaults.standard.set(Array(celebrated).sorted(), forKey: storageKey)
        goalMilestone = step
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
    /// Pendant la visite guidée, elle ne s'ouvre pas : une planche par-dessus
    /// recouvrirait la carte qu'on est en train de présenter. Elle s'ouvre en
    /// revanche à la fin, quand la visite dépose sur cet onglet — le cartouche
    /// vient de nommer « Découvrir », la planche montre comment s'en servir.
    /// Marquer la planche comme vue au passage de l'étape, ce qui se faisait
    /// avant, revenait à ne jamais la montrer à personne.
    private func openGuideOnFirstVisit() async {
        guard !guideSeen, !tour.isRunning else { return }
        try? await Task.sleep(for: .milliseconds(280))
        guard !guideSeen, selectedTab == 2 else { return }
        guideSeen = true
        withAnimation(.easeOut(duration: 0.24)) { showGuide = true }
    }

    /// Le doigt se lève : la boussole s'efface, quelle que soit l'issue du
    /// geste. Elle est appelée aussi bien par le relâchement simple que par la
    /// fin d'un glissement, parce que ni l'un ni l'autre ne couvre les deux cas.
    private func releasePress() {
        guard isPressing else { return }
        withAnimation(SwipeMotion.unfold) { isPressing = false }
    }

    /// Le rappel des trois issues : cinq secondes à l'arrivée, puis il s'efface.
    ///
    /// La planche des gestes ne s'ouvre qu'une fois dans une vie, et le
    /// cartouche de la visite guidée non plus. Ce rappel-ci revient à chaque
    /// visite parce qu'il ne coûte rien : il ne demande aucun geste, ne
    /// recouvre pas la carte et part tout seul. Il tient la même place que la
    /// boussole du contact, si bien qu'on ne lit jamais deux dispositifs pour
    /// la même chose.
    ///
    /// Il se tait pendant la visite guidée et derrière la planche, qui disent
    /// déjà les trois gestes, et il laisse la bascule d'onglet se terminer :
    /// un rappel qui arrive dans le même mouvement que l'écran se lit comme un
    /// raté d'animation.
    private func playReminder() async {
        guard !tour.isRunning else { return }
        try? await Task.sleep(for: .milliseconds(420))
        guard !showGuide, !tour.isRunning, selectedTab == 2 else { return }

        // Sans carte de tête, la boussole n'a aucun support : mieux vaut ne
        // rien jouer que consommer le rappel à vide.
        guard !displayedCards.isEmpty else { return }

        withAnimation(SwipeMotion.unfold) { showsReminder = true }
        try? await Task.sleep(for: .seconds(5))
        guard !Task.isCancelled else { return }
        withAnimation(SwipeMotion.unfold) { showsReminder = false }
    }

    private func closeGuide() {
        guard showGuide else { return }
        withAnimation(.easeOut(duration: 0.22)) { showGuide = false }
    }

    /// Ce qui est déjà rangé, dans l'identité des cartes. Une série compte dès
    /// qu'une de ses saisons est rangée : le deck demande si on la connaît, et
    /// cette question a déjà sa réponse.
    private var libraryIDs: Set<String> {
        Set(libraryStore.galleryItems.map { "\($0.mediaType.rawValue)-\($0.tmdbId)" })
            .union(libraryStore.watchlistItems.map { "\($0.mediaType.rawValue)-\($0.tmdbId)" })
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
    /// Un coup de cœur : la carte s'arrête le temps que le cœur s'y pose.
    let loved: Bool
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
    @State private var showsLove = false

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
        .overlay { SwipeLoveBurst(isOn: showsLove) }
        .offset(offset)
        .rotationEffect(.degrees(angle), anchor: item.anchor)
        .opacity(opacity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task {
            if item.loved {
                // Le cœur se voit avant que la carte parte : sans ce temps, il
                // s'envolerait avec elle sans avoir été lu.
                withAnimation(item.reduceMotion ? .easeOut(duration: 0.15) : SwipeLoveBurst.pop) {
                    showsLove = true
                }
                try? await Task.sleep(for: .milliseconds(item.reduceMotion ? 450 : 520))
            }
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
            withAnimation(.easeOut(duration: 0.12).delay(0.18)) { opacity = 0 }

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
