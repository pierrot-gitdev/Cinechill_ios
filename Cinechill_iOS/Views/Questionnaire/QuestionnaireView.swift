//
//  QuestionnaireView.swift
//  Cinechill_iOS
//

import SwiftUI

struct QuestionnaireView: View {
    @State var viewModel: QuestionnaireViewModel
    /// Prêté par `MainTabView`, qui l'a reçu de `RootView` : c'est le catalogue de
    /// l'accueil, préchargé pendant l'ouverture de l'app. L'entrée y puise ses
    /// affiches, ce qui lui évite la moindre requête.
    let homeModel: HomeViewModel
    /// L'onglet courant : la porte envoie vers Découvrir, là où la galerie se
    /// remplit.
    @Binding var selectedTab: Int
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var libraryStore: LibraryStore
    @EnvironmentObject private var profileStore: UserProfileStore
    @EnvironmentObject private var socialStore: SocialStore
    @Environment(BadgesViewModel.self) private var badgesModel
    @Environment(DoorStore.self) private var doorStore
    @State private var showProfile = false
    @State private var showTasteSheet = false
    @State private var showLovePicker = false
    /// Le seuil a été franchi une fois : la porte ouverte ne se remontre plus,
    /// sauf si le serveur la referme.
    @AppStorage("cinematch.doorOpened") private var doorOpened = false

    var body: some View {
        NavigationStack {
            ZStack {
                Ink.ground.ignoresSafeArea()
                content
            }
            // Pas de `safeAreaInset` pour l'en-tête de l'entrée : il réserverait
            // sa hauteur et couperait le mur sous lui. `SessionEntryView` le pose
            // elle-même en surcouche, ce que le voile en dégradé d'`AppHeaderView`
            // prévoit depuis toujours.
            .navigationBarHidden(true)
            .fullScreenCover(isPresented: $showProfile) {
                ProfileView(badgesModel: badgesModel)
                    .environmentObject(profileStore)
                    .environmentObject(libraryStore)
                    .environmentObject(authService)
                    .environmentObject(socialStore)
            }
            .sheet(isPresented: $showTasteSheet) {
                TasteSheetView(profile: viewModel.taste) { axis, value in
                    await viewModel.correctTaste(axis: axis, value: value)
                }
            }
            .sheet(isPresented: $showLovePicker) {
                LovePickerView(
                    target: doorStore.door.artifact(.coeur)?.target ?? 12,
                    onClose: { showLovePicker = false }
                )
                .environmentObject(libraryStore)
            }
        }
        // Chaque retour sur l'onglet remesure la porte : la galerie a pu se
        // remplir depuis Découvrir, et la jauge doit le raconter sans attendre.
        .onChange(of: selectedTab) { _, tab in
            guard tab == 1 else { return }
            Task { await doorStore.refresh() }
        }
        // La planche refermée, on remesure aussi : c'est peut-être elle qui
        // vient d'allumer le Cœur.
        .onChange(of: showLovePicker) { _, isOpen in
            guard !isOpen else { return }
            Task { await doorStore.refresh() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .intro:
            // La porte garde l'onglet tant que le profil n'est pas prêt, et
            // reste une dernière fois pour l'ouverture : le seuil ne se
            // franchit qu'en la voyant céder.
            if !doorStore.door.unlocked || !doorOpened {
                CineMatchGateView(
                    door: doorStore.door,
                    isMeasured: doorStore.hasMeasured,
                    lovedCount: libraryStore.lovedCount,
                    onProfileTap: { showProfile = true },
                    onDiscover: { selectedTab = 2 },
                    onLovePicker: { showLovePicker = true },
                    onEnter: {
                        withAnimation(.easeOut(duration: 0.3)) { doorOpened = true }
                    },
                    isCelebrating: doorStore.celebration != nil
                )
                .task {
                    await doorStore.refresh()
                    await viewModel.loadTasteProfile()
                    await viewModel.catchUpGalleryIfNeeded()
                    await doorStore.refresh()
                }
            } else {
                SessionEntryView(
                    posters: homeModel.popularItems,
                    audience: $viewModel.answers.audience,
                    onProfileTap: { showProfile = true },
                    onNext: {
                        viewModel.start(
                            preferredPlatformIDs: libraryStore.preferredPlatformIDs,
                            bannedGenreIDs: libraryStore.bannedGenreIDs,
                            audience: viewModel.answers.audience
                        )
                    }
                )
                .task {
                    await viewModel.loadPlatformsIfNeeded()
                    await viewModel.loadTasteProfile()
                }
            }
        case .frame:
            frameFlow
        case .filmChoice:
            filmChoiceFlow
        case .poolLoading:
            SessionLoadingView(message: String(localized: "On cherche des films qui te correspondent…", bundle: .app))
        case .asking:
            adaptiveFlow
        case .enriching:
            SessionLoadingView(message: String(localized: "On regarde les meilleurs de plus près…", bundle: .app))
        case .finalizing:
            SessionLoadingView(message: String(localized: "On choisit ton film…", bundle: .app))
        case .results:
            ResultView(
                results: viewModel.results,
                onRestart: { viewModel.restart() },
                onExplain: { showTasteSheet = true },
                onLaunch: { viewModel.recordLaunch(tmdbID: $0) },
                onPass: { viewModel.passFilm(tmdbID: $0) },
                onReject: { viewModel.rejectTrio() }
            )
        case .error(let message):
            errorView(message)
        }
    }

    // MARK: - Ta soirée

    private var frameFlow: some View {
        VStack(spacing: 0) {
            sessionHeader(step: String(localized: "Étape 1 sur 2", bundle: .app), onBack: { viewModel.restart() }, isFirst: true)

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Ta soirée", bundle: .app)
                            .planTitle()
                            .foregroundStyle(Ink.ink)

                        Text("Deux réglages pour éliminer d'emblée ce qui ne convient pas.", bundle: .app)
                            .font(.system(size: 13))
                            .foregroundStyle(Ink.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    SessionFrameView(
                        budget: $viewModel.answers.runtime,
                        contentFormat: $viewModel.answers.contentFormat,
                        lateHourNote: viewModel.lateHourNote
                    )
                }
                .padding(.horizontal, Metrics.margin)
                .padding(.top, 26)
                .padding(.bottom, 32)
            }

            PlanButton(
                title: String(localized: "Continuer", bundle: .app),
                isEnabled: viewModel.canAdvanceFrame,
                height: Metrics.control
            ) {
                viewModel.goNextFrame()
            }
            .padding(.horizontal, Metrics.margin)
            .padding(.bottom, Metrics.margin)
        }
    }

    // MARK: - Quel film ce soir

    /// L'écran du film cherché : genre et ambiance, deux listes d'options.
    private var filmChoiceFlow: some View {
        VStack(spacing: 0) {
            sessionHeader(step: String(localized: "Étape 2 sur 2", bundle: .app), onBack: { viewModel.goBackToFrame() }, isFirst: false)

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Quel film ce soir ?", bundle: .app)
                            .planTitle()
                            .foregroundStyle(Ink.ink)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("C'est ce qui nous permet de resserrer la recherche. Les questions suivantes affineront.", bundle: .app)
                            .font(.system(size: 13))
                            .foregroundStyle(Ink.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    FilmChoiceView(
                        availableGenres: viewModel.availableGenres,
                        selectedGenres: viewModel.answers.genres,
                        selectedMood: viewModel.answers.mood,
                        isMoodAny: viewModel.isMoodAny,
                        onPickMood: { viewModel.pickMood($0) },
                        onMoodAny: { viewModel.pickMoodAny() },
                        maxGenres: viewModel.maxGenres,
                        isGenreSelectable: { viewModel.isGenreSelectable($0) },
                        onToggleGenre: { viewModel.toggleGenre($0) },
                        selectedOrigins: viewModel.answers.originCountries,
                        maxOrigins: viewModel.maxOriginCountries,
                        isOriginSelectable: { viewModel.isOriginCountrySelectable($0) },
                        onToggleOrigin: { viewModel.toggleOriginCountry($0) }
                    )

                    if let reading = viewModel.ambianceReading {
                        readingLine(reading)
                    }
                }
                .padding(.horizontal, Metrics.margin)
                .padding(.top, 26)
                .padding(.bottom, 32)
            }

            // Le bouton inactif dit ce qui manque plutôt que de rester muet.
            PlanButton(
                title: viewModel.canConfirmFilmChoice
                    ? String(localized: "Trouver mes films", bundle: .app)
                    : String(localized: "Choisis une ambiance", bundle: .app),
                isEnabled: viewModel.canConfirmFilmChoice,
                height: Metrics.control
            ) {
                viewModel.confirmFilmChoice()
            }
            .padding(.horizontal, Metrics.margin)
            .padding(.bottom, Metrics.margin)
        }
    }

    // MARK: - Les questions

    private var adaptiveFlow: some View {
        VStack(spacing: 0) {
            sessionHeader(
                step: String(localized: "Question \(viewModel.questionNumber)", bundle: .app),
                onBack: { viewModel.goBackAdaptive() },
                isFirst: false
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let reading = viewModel.reading {
                        readingLine(reading)
                    }

                    Group {
                        if let options = viewModel.pairwiseOptions {
                            PairwiseComparisonView(
                                optionA: options.0,
                                optionB: options.1,
                                title: viewModel.duelSourceIsGallery
                                    ? String(localized: "Tu as vu les deux. Lequel tu relancerais ce soir ?", bundle: .app)
                                    : nil,
                                subtitle: viewModel.duelSourceIsGallery
                                    ? String(localized: "Choisir entre deux souvenirs nous dit ton goût mieux que n'importe quelle question.", bundle: .app)
                                    : nil
                            ) { winner, loser in
                                viewModel.recordPairwiseChoice(winner: winner, loser: loser)
                            }
                        } else if let options = viewModel.eliminationOptions {
                            EliminationView(
                                options: options,
                                title: viewModel.duelSourceIsGallery
                                    ? String(localized: "Parmi ces films que tu as vus, écarte celui qui ne colle pas à ce soir", bundle: .app)
                                    : nil
                            ) { loser in
                                viewModel.recordElimination(loser: loser)
                            }
                        } else if let dimension = viewModel.currentDimension {
                            adaptiveQuestionCard(for: dimension)
                        }
                    }
                    .id(viewModel.currentDimension)
                    .transition(.opacity)
                }
                .padding(.horizontal, Metrics.margin)
                .padding(.top, 26)
                .padding(.bottom, 32)
            }

            adaptiveFooter
        }
        .animation(Metrics.unfold, value: viewModel.currentDimension)
    }

    /// « Suivant » n'existe que pour les puces : les affiches valident au tap. La sortie
    /// manuelle, elle, reste accessible à chaque instant — c'est elle qui porte le
    /// compromis « plus de questions, plus de précision, mais vous décidez ».
    private var adaptiveFooter: some View {
        VStack(spacing: 12) {
            if viewModel.pairwiseOptions == nil && viewModel.eliminationOptions == nil {
                PlanButton(
                    title: String(localized: "Suivant", bundle: .app),
                    isEnabled: viewModel.canAdvanceAdaptive,
                    height: Metrics.control
                ) {
                    viewModel.goNextAdaptive()
                }
            }

            Button {
                viewModel.finishNow()
            } label: {
                Text("Passer les questions et voir mes films", bundle: .app)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Ink.ink2)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(Ink.ruleSet)
                            .frame(height: 1)
                            .offset(y: 2)
                    }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Metrics.margin)
        .padding(.bottom, Metrics.margin)
    }

    @ViewBuilder
    private func adaptiveQuestionCard(for dimension: AdaptiveDimension) -> some View {
        let step = dimension.questionStep
        switch dimension {
        case .posterDuel:
            EmptyView() // Toujours présentée en comparaison directe — voir `pairwiseOptions`.
        case .elimination:
            EmptyView() // Toujours présentée en grille d'élimination — voir `eliminationOptions`.
        case .mindset:
            singleSelectCard(step: step, options: Mindset.chipOptions, current: viewModel.answers.mindset) { id in
                if let value = Mindset(rawValue: id) { viewModel.select(value, in: \.mindset) }
            }
        case .dealbreaker:
            singleSelectCard(step: step, options: Dealbreaker.chipOptions, current: viewModel.answers.dealbreaker) { id in
                if let value = Dealbreaker(rawValue: id) { viewModel.select(value, in: \.dealbreaker) }
            }
        case .popularity:
            singleSelectCard(step: step, options: PopularityPreference.chipOptions, current: viewModel.answers.popularity) { id in
                if let value = PopularityPreference(rawValue: id) { viewModel.select(value, in: \.popularity) }
            }
        case .cast:
            singleSelectCard(step: step, options: CastPreference.chipOptions, current: viewModel.answers.cast) { id in
                if let value = CastPreference(rawValue: id) { viewModel.select(value, in: \.cast) }
            }
        case .horrorFlavor:
            singleSelectCard(step: step, options: HorrorFlavor.chipOptions, current: viewModel.answers.horrorFlavor) { id in
                if let value = HorrorFlavor(rawValue: id) { viewModel.select(value, in: \.horrorFlavor) }
            }
        case .comedyFlavor:
            singleSelectCard(step: step, options: ComedyFlavor.chipOptions, current: viewModel.answers.comedyFlavor) { id in
                if let value = ComedyFlavor(rawValue: id) { viewModel.select(value, in: \.comedyFlavor) }
            }
        case .dramaFlavor:
            singleSelectCard(step: step, options: DramaFlavor.chipOptions, current: viewModel.answers.dramaFlavor) { id in
                if let value = DramaFlavor(rawValue: id) { viewModel.select(value, in: \.dramaFlavor) }
            }
        case .cognitiveMode:
            singleSelectCard(step: step, options: CognitiveMode.chipOptions, current: viewModel.answers.cognitiveMode) { id in
                if let value = CognitiveMode(rawValue: id) { viewModel.select(value, in: \.cognitiveMode) }
            }
        case .storyOrigin:
            singleSelectCard(step: step, options: StoryOrigin.chipOptions, current: viewModel.answers.storyOrigin) { id in
                if let value = StoryOrigin(rawValue: id) { viewModel.select(value, in: \.storyOrigin) }
            }
        case .attachment:
            singleSelectCard(step: step, options: AttachmentMode.chipOptions, current: viewModel.answers.attachment) { id in
                if let value = AttachmentMode(rawValue: id) { viewModel.select(value, in: \.attachment) }
            }
        case .creditsMoment:
            singleSelectCard(step: step, options: CreditsMoment.chipOptions, current: viewModel.answers.creditsMoment) { id in
                if let value = CreditsMoment(rawValue: id) { viewModel.select(value, in: \.creditsMoment) }
            }
        case .lastingTrace:
            singleSelectCard(step: step, options: LastingTrace.chipOptions, current: viewModel.answers.lastingTrace) { id in
                if let value = LastingTrace(rawValue: id) { viewModel.select(value, in: \.lastingTrace) }
            }
        case .surpriseIntensity:
            IntensitySliderView(value: $viewModel.answers.surpriseIntensity)
        }
    }

    private func singleSelectCard<T: QuestionOption>(
        step: QuestionStep,
        options: [ChipOption],
        current: T?,
        onSelect: @escaping (String) -> Void
    ) -> some View {
        QuestionCardView(
            step: step,
            options: options,
            selectedIDs: current.map { [$0.rawValue] } ?? [],
            onToggle: onSelect
        )
    }

    // MARK: - Chrome commun

    private func sessionHeader(step: String, onBack: @escaping () -> Void, isFirst: Bool) -> some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onBack) {
                    Image(systemName: isFirst ? "xmark" : "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Ink.ink2)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isFirst
                                    ? String(localized: "Quitter la recherche", bundle: .app)
                                    : String(localized: "Revenir à l'écran précédent", bundle: .app))

                Spacer()

                Text(step)
                    .planLabel()
                    .foregroundStyle(Ink.ink3)
                    .monospacedDigit()
            }
            .padding(.horizontal, Metrics.margin - 8)
            .padding(.bottom, 12)

            PlanRail()
        }
    }

    /// Ce que la réponse change pour la sélection, en une ligne. Le filet à
    /// gauche la détache du contenu sans en faire un encart — c'est une voix, pas
    /// un panneau.
    private func readingLine(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Rectangle()
                .fill(Ink.light)
                .frame(width: 1)
            Text(text)
                .font(.system(size: 12.5))
                .foregroundStyle(Ink.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .fixedSize(horizontal: false, vertical: true)
        .transition(.opacity)
        .animation(Metrics.shift, value: text)
        .accessibilityLabel(String(localized: "Ce que ça change : \(text)", bundle: .app))
    }

    // MARK: - Erreur

    private func errorView(_ message: String) -> some View {
        PlanEmptyState(
            icon: .salle,
            title: String(localized: "La recherche s'est interrompue", bundle: .app),
            message: message,
            actionTitle: String(localized: "Réessayer", bundle: .app),
            action: { viewModel.retrySubmit() },
            secondaryTitle: String(localized: "Recommencer du début", bundle: .app),
            secondaryAction: { viewModel.restart() }
        )
        .frame(maxHeight: .infinity)
        .padding(Metrics.margin)
    }
}

/// L'attente, dans la langue du système : rien ne tourne, rien ne rebondit. Un filet
/// parcourt le bord bas du bloc — le même dispositif que le chargement de `PlanButton`,
/// pour que l'application ne change pas de vocabulaire selon l'écran.
private struct SessionLoadingView: View {
    let message: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var travel: CGFloat = -0.4

    var body: some View {
        VStack(spacing: 18) {
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(Ink.ink2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Ink.rule)
                        .frame(height: 1)
                    if reduceMotion {
                        Rectangle()
                            .fill(Ink.ink3)
                            .frame(width: proxy.size.width * 0.4, height: 1)
                    } else {
                        Rectangle()
                            .fill(Ink.ink)
                            .frame(width: proxy.size.width * 0.4, height: 1)
                            .offset(x: travel * proxy.size.width)
                            .onAppear {
                                withAnimation(.easeInOut(duration: 1.15).repeatForever(autoreverses: false)) {
                                    travel = 1
                                }
                            }
                    }
                }
                .frame(height: 1)
            }
            .frame(width: 160, height: 1)
            .clipped()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Metrics.margin)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
    }
}
