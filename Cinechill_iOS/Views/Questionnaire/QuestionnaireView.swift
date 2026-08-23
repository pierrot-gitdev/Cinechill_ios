//
//  QuestionnaireView.swift
//  Cinechill_iOS
//

import SwiftUI

struct QuestionnaireView: View {
    @State var viewModel: QuestionnaireViewModel
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
    @State private var showLovePicker = false
    /// Le seuil a été franchi **dans cette ouverture de l'app**. Volontairement
    /// un état de session et non une préférence gardée : la cérémonie se rejoue
    /// à chaque lancement, elle ne se consomme pas une fois pour toutes.
    @State private var hasCrossedThreshold = false

    var body: some View {
        NavigationStack {
            ZStack {
                Ink.ground.ignoresSafeArea()

                // La Salle, posée ici et nulle part ailleurs : c'est parce
                // qu'elle survit au changement de phase que sa lumière peut
                // descendre au lieu de sauter. Chaque écran ne fournit ensuite
                // que ce qu'il projette et ce qu'il demande.
                SalleBackdrop(
                    light: viewModel.salleLight,
                    showsScreen: viewModel.phase != .results,
                    showsAisleLights: viewModel.phase != .results
                )
                .ignoresSafeArea()
                    .animation(.easeInOut(duration: 0.7), value: viewModel.salleLight)

                content
            }
            // Pas de `safeAreaInset` pour l'en-tête de l'entrée : il réserverait
            // sa hauteur et couperait la salle sous lui. `SessionEntryView` le
            // pose elle-même en surcouche, ce que le voile en dégradé
            // d'`AppHeaderView` prévoit depuis toujours.
            .navigationBarHidden(true)
            .fullScreenCover(isPresented: $showProfile) {
                ProfileView(badgesModel: badgesModel)
                    .environmentObject(profileStore)
                    .environmentObject(libraryStore)
                    .environmentObject(authService)
                    .environmentObject(socialStore)
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
            if !doorStore.door.unlocked || !hasCrossedThreshold {
                CineMatchGateView(
                    door: doorStore.door,
                    isMeasured: doorStore.hasMeasured,
                    lovedCount: libraryStore.lovedCount,
                    onProfileTap: { showProfile = true },
                    onDiscover: { selectedTab = 2 },
                    onLovePicker: { showLovePicker = true },
                    onEnter: {
                        withAnimation(.easeOut(duration: 0.45)) { hasCrossedThreshold = true }
                    },
                    isCelebrating: doorStore.celebration != nil
                )
                // Le raccord : le travelling finit dans l'entrée de séance au
                // lieu de la laisser apparaître d'un coup. Sans transition
                // explicite, l'échange des deux branches se ferait sec.
                .transition(.opacity)
                .task {
                    await doorStore.refresh()
                    await viewModel.loadTasteProfile()
                }
            } else {
                SessionEntryView(
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
                .transition(.opacity)
                .task {
                    await viewModel.loadPlatformsIfNeeded()
                    await viewModel.loadTasteProfile()
                }
            }
        case .frame:
            frameFlow
        case .filmGenre:
            genreFlow
        case .filmOrigin:
            originFlow
        case .filmMood:
            moodFlow
        case .poolLoading:
            waiting(String(localized: "On cherche des films qui te correspondent…", bundle: .app))
        case .asking:
            adaptiveFlow
        case .enriching:
            waiting(String(localized: "On regarde les meilleurs de plus près…", bundle: .app))
        case .finalizing:
            waiting(String(localized: "On choisit ton film…", bundle: .app))
        case .results:
            ResultView(
                results: viewModel.results,
                onRestart: { viewModel.restart() },
                onLaunch: { viewModel.recordLaunch(tmdbID: $0) },
                onPass: { viewModel.passFilm(tmdbID: $0) },
                onReject: { viewModel.rejectTrio() }
            )
        case .error(let message):
            errorView(message)
        }
    }

    // MARK: - Ta soirée

    /// La durée. La question est projetée sur la toile ; l'écran ne porte plus
    /// que ses réponses. Le titre d'écran et son sous-titre ont disparu avec
    /// elle : les réécrire sous la projection les dédoublerait.
    private var frameFlow: some View {
        SalleStage(
            question: String(localized: "Durée du film", bundle: .app),
            eyebrow: nil
        ) {
            VStack(spacing: 0) {
                sessionHeader(onBack: { viewModel.restart() }, isFirst: true)

                SalleAnswers {
                    SessionFrameView(
                        // Passer par le modèle plutôt que par le champ : c'est
                        // ainsi qu'on distingue une durée choisie d'une durée
                        // présélectionnée par l'heure.
                        budget: Binding(
                            get: { viewModel.answers.runtime },
                            set: { viewModel.pickRuntime($0) }
                        ),
                        lateHourNote: viewModel.lateHourNote
                    )
                    .padding(.horizontal, Metrics.margin)
                    .padding(.bottom, 24)
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
    }

    // MARK: - Quel film ce soir

    /// Le genre, et la forme du contenu qui pose la même question sur le même
    /// objet. C'est le seul écran du parcours qui en porte deux, et elles n'en
    /// font qu'une : de quelle sorte de film on parle.
    private var genreFlow: some View {
        SalleStage(question: String(localized: "Quel genre de film ?", bundle: .app)) {
            VStack(spacing: 0) {
                sessionHeader(onBack: { viewModel.goBackToFrame() }, isFirst: false)

                SalleAnswers {
                    GenreChoiceView(
                        availableGenres: viewModel.availableGenres,
                        selectedGenres: viewModel.answers.genres,
                        isGenreSelectable: { viewModel.isGenreSelectable($0) },
                        onToggleGenre: { viewModel.toggleGenre($0) },
                        contentFormat: $viewModel.answers.contentFormat
                    )
                    .padding(.horizontal, Metrics.margin)
                    .padding(.bottom, 24)
                }

                PlanButton(
                    title: String(localized: "Continuer", bundle: .app),
                    isEnabled: viewModel.canAdvanceGenre,
                    height: Metrics.control
                ) {
                    viewModel.goNextGenre()
                }
                .padding(.horizontal, Metrics.margin)
                .padding(.bottom, Metrics.margin)
            }
        }
    }

    /// L'origine, seule sur son écran. Facultative : laisser vide n'exclut rien.
    private var originFlow: some View {
        SalleStage(question: String(localized: "D'où vient le film ?", bundle: .app)) {
            VStack(spacing: 0) {
                sessionHeader(onBack: { viewModel.goBackToGenre() }, isFirst: false)

                SalleAnswers {
                    OriginChoiceView(
                        selectedOrigins: viewModel.answers.originCountries,
                        isOriginSelectable: { viewModel.isOriginCountrySelectable($0) },
                        onToggleOrigin: { viewModel.toggleOriginCountry($0) }
                    )
                    .padding(.horizontal, Metrics.margin)
                    .padding(.bottom, 24)
                }

                PlanButton(
                    title: String(localized: "Continuer", bundle: .app),
                    isEnabled: true,
                    height: Metrics.control
                ) {
                    viewModel.goNextOrigin()
                }
                .padding(.horizontal, Metrics.margin)
                .padding(.bottom, Metrics.margin)
            }
        }
    }

    /// L'ambiance, seule sur son écran : c'est la seule des deux qui demande
    /// une réponse pour avancer.
    private var moodFlow: some View {
        SalleStage(
            question: String(localized: "Quelle ambiance ?", bundle: .app),
            eyebrow: nil
        ) {
            VStack(spacing: 0) {
                sessionHeader(onBack: { viewModel.goBackToOrigin() }, isFirst: false)

                SalleAnswers {
                    MoodChoiceView(
                        selectedMood: viewModel.answers.mood,
                        isMoodAny: viewModel.isMoodAny,
                        onPickMood: { viewModel.pickMood($0) },
                        onMoodAny: { viewModel.pickMoodAny() }
                    )
                    .padding(.horizontal, Metrics.margin)
                    .padding(.bottom, 24)
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
    }

    // MARK: - Les questions

    private var adaptiveFlow: some View {
        SalleStage(
            question: adaptiveQuestion,
            eyebrow: String(localized: "Question \(viewModel.questionNumber)", bundle: .app)
        ) {
            VStack(spacing: 0) {
                sessionHeader(onBack: { viewModel.goBackAdaptive() }, isFirst: false)

                SalleAnswers {
                    VStack(alignment: .leading, spacing: 22) {
                        Group {
                            if let options = viewModel.pairwiseOptions {
                                PairwiseComparisonView(
                                    optionA: options.0,
                                    optionB: options.1
                                ) { winner, loser in
                                    viewModel.recordPairwiseChoice(winner: winner, loser: loser)
                                }
                        } else if let options = viewModel.eliminationOptions {
                            EliminationView(options: options) { loser in
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
                    .padding(.bottom, 24)
                }

                adaptiveFooter
            }
        }
        .animation(Metrics.unfold, value: viewModel.currentDimension)
    }

    /// La question projetée sur la toile. Les affiches ont la leur, qui change
    /// selon qu'on oppose des films vus ou des paris (C2).
    private var adaptiveQuestion: String? {
        if viewModel.pairwiseOptions != nil {
            return viewModel.duelSourceIsGallery
                ? String(localized: "Ce soir tu es plutôt…", bundle: .app)
                : QuestionStep.posterDuel.title
        }
        if viewModel.eliminationOptions != nil {
            return viewModel.duelSourceIsGallery
                ? String(localized: "Parmi ces films que tu as vus, écarte celui qui ne colle pas à ce soir", bundle: .app)
                : QuestionStep.elimination.title
        }
        return viewModel.currentDimension?.questionStep.title
    }

    /// « Suivant » n'existe que pour les puces : les affiches valident au tap.
    ///
    /// **La sortie manuelle a disparu.** Elle portait le compromis « plus de
    /// questions, plus de précision, mais vous décidez » ; la Salle le porte
    /// autrement, en éteignant ses lumières à mesure qu'on avance. On va
    /// désormais au bout du questionnaire.
    private var adaptiveFooter: some View {
        Group {
            if viewModel.pairwiseOptions == nil && viewModel.eliminationOptions == nil {
                PlanButton(
                    title: String(localized: "Suivant", bundle: .app),
                    isEnabled: viewModel.canAdvanceAdaptive,
                    height: Metrics.control
                ) {
                    viewModel.goNextAdaptive()
                }
                .padding(.horizontal, Metrics.margin)
                .padding(.bottom, Metrics.margin)
            }
        }
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
        case .paceWish:
            singleSelectCard(step: step, options: PaceWish.chipOptions, current: viewModel.answers.paceWish) { id in
                if let value = PaceWish(rawValue: id) { viewModel.select(value, in: \.paceWish) }
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

    /// L'en-tête ne porte plus que le retour. Le rang de l'étape est projeté
    /// sur la toile, avec la question : l'écrire ici aussi le dédoublerait, et
    /// le filet du bas coupait la salle en deux.
    private func sessionHeader(onBack: @escaping () -> Void, isFirst: Bool) -> some View {
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
            }
            .padding(.horizontal, Metrics.margin - 8)
            .padding(.top, 4)
        }
    }

    /// L'attente, dans la salle : le décor continue de s'éteindre pendant qu'on
    /// cherche, et le message est projeté sur la toile plutôt que posé sur les
    /// fauteuils. C'est ce qui fait que la recherche appartient à la séance au
    /// lieu d'être une parenthèse posée dessus.
    private func waiting(_ message: String) -> some View {
        SalleStage(projected: { SalleLeader(message: message) }) {
            // La toile n'est pas lisible par VoiceOver : le message y est un
            // dessin. Il est redit ici, où il sera annoncé.
            Color.clear
                .accessibilityElement()
                .accessibilityLabel(message)
                .accessibilityAddTraits(.updatesFrequently)
        }
    }


    // MARK: - Erreur

    private func errorView(_ message: String) -> some View {
        // Dans la salle comme le reste : une panne ne sort pas du décor, sinon
        // elle se lit comme un autre écran de l'application.
        SalleStage {
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
}

