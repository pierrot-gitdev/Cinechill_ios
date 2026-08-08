//
//  QuestionnaireView.swift
//  Cinechill_iOS
//

import SwiftUI

struct QuestionnaireView: View {
    @State var viewModel: QuestionnaireViewModel
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var libraryStore: LibraryStore
    @EnvironmentObject private var profileStore: UserProfileStore
    @EnvironmentObject private var socialStore: SocialStore
    @Environment(BadgesViewModel.self) private var badgesModel
    @State private var showProfile = false
    @State private var showTasteSheet = false

    var body: some View {
        NavigationStack {
            ZStack {
                Ink.ground.ignoresSafeArea()
                content
            }
            .safeAreaInset(edge: .top) {
                if viewModel.phase == .intro {
                    AppHeaderView(title: "CinéMatch", onProfileTap: { showProfile = true })
                }
            }
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
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .intro:
            introView
        case .frame:
            frameFlow
        case .filmChoice:
            filmChoiceFlow
        case .poolLoading:
            SessionLoadingView(message: "On cherche des films qui vous correspondent…")
        case .asking:
            adaptiveFlow
        case .enriching:
            SessionLoadingView(message: "On regarde les meilleurs de plus près…")
        case .finalizing:
            SessionLoadingView(message: "On choisit vos trois films…")
        case .results:
            ResultView(
                results: viewModel.results,
                onRestart: { viewModel.restart() },
                onExplain: { showTasteSheet = true },
                onLaunch: { viewModel.recordLaunch(tmdbID: $0) },
                onReject: { viewModel.rejectTrio() }
            )
        case .error(let message):
            errorView(message)
        }
    }

    // MARK: - L'accueil

    private var introView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()

            CinechillHallIconView(.salle)
                .frame(width: 34, height: 34)
                .foregroundStyle(Ink.ink3)

            Text(viewModel.openingTitle)
                .planTitle(28)
                .foregroundStyle(Ink.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 24)

            Text(viewModel.openingLead)
                .font(.system(size: 13.5))
                .foregroundStyle(Ink.ink2)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)

            // Ce que la personne obtient, dit avant de commencer plutôt que
            // promis en abstrait. Les trois lignes sont numérotées parce qu'elles
            // décrivent un ordre réel, pas pour décorer.
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(viewModel.openingSteps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("\(index + 1)")
                            .planLabel()
                            .foregroundStyle(Ink.ink3)
                            .monospacedDigit()
                        Text(step)
                            .font(.system(size: 13))
                            .foregroundStyle(Ink.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.top, 22)

            Text(viewModel.openingDuration)
                .font(.system(size: 12.5))
                .foregroundStyle(Ink.ink3)
                .padding(.top, 18)

            // N'apparaît qu'une fois le profil chargé, et ne remplace rien : le
            // reste de l'écran est lisible dès la première image.
            if let provenance = viewModel.openingProvenance {
                Button { showTasteSheet = true } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        PlanLight()
                        Text(provenance)
                            .font(.system(size: 12))
                            .foregroundStyle(Ink.ink2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Ink.ink3)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 16)
                .transition(.opacity)
                .accessibilityHint("Voir ce que Cinechill a retenu de vos goûts")
            }

            Spacer()

            if let pending = viewModel.taste.pendingVerdict {
                VerdictPromptView(
                    pending: pending,
                    onAnswer: { viewModel.answerVerdict($0) },
                    onDismiss: { viewModel.dismissVerdict() }
                )
                .padding(.bottom, 24)
                .transition(.opacity)
            }

            if !viewModel.selectedPlatformNames.isEmpty {
                PlanEdge()
                HStack(alignment: .firstTextBaseline) {
                    Text("Vos plateformes")
                        .planLabel()
                        .foregroundStyle(Ink.ink3)
                    Spacer(minLength: 16)
                    Text(viewModel.selectedPlatformNames.joined(separator: " · "))
                        .font(.system(size: 12))
                        .foregroundStyle(Ink.ink2)
                        .multilineTextAlignment(.trailing)
                }
                .padding(.vertical, 14)
                PlanEdge()
                    .padding(.bottom, 24)
            }

            PlanButton(title: "Commencer") {
                viewModel.start(
                    preferredPlatformIDs: libraryStore.preferredPlatformIDs,
                    bannedGenreIDs: libraryStore.bannedGenreIDs
                )
            }
        }
        .padding(.horizontal, Metrics.margin)
        .padding(.bottom, Metrics.margin)
        .animation(Metrics.shift, value: viewModel.openingProvenance)
        .task {
            await viewModel.loadPlatformsIfNeeded()
            await viewModel.loadTasteProfile()
        }
    }

    // MARK: - Votre soirée

    private var frameFlow: some View {
        VStack(spacing: 0) {
            sessionHeader(step: "Étape 1 sur 2", onBack: { viewModel.restart() }, isFirst: true)

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Votre soirée")
                            .planTitle()
                            .foregroundStyle(Ink.ink)

                        Text("Trois réglages pour éliminer d'emblée ce qui ne convient pas.")
                            .font(.system(size: 13))
                            .foregroundStyle(Ink.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    SessionFrameView(
                        audience: $viewModel.answers.audience,
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
                title: "Continuer",
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
            sessionHeader(step: "Étape 2 sur 2", onBack: { viewModel.goBackToFrame() }, isFirst: false)

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Quel film ce soir ?")
                            .planTitle()
                            .foregroundStyle(Ink.ink)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("C'est ce qui nous permet de resserrer la recherche. Les questions suivantes affineront.")
                            .font(.system(size: 13))
                            .foregroundStyle(Ink.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    FilmChoiceView(
                        availableGenres: viewModel.availableGenres,
                        selectedGenres: viewModel.answers.genres,
                        mood: $viewModel.answers.mood,
                        maxGenres: viewModel.maxGenres,
                        isGenreSelectable: { viewModel.isGenreSelectable($0) },
                        onToggleGenre: { viewModel.toggleGenre($0) }
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
                title: viewModel.canConfirmFilmChoice ? "Trouver mes films" : "Choisissez une ambiance",
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
                step: "Question \(viewModel.questionNumber)",
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
                            PairwiseComparisonView(optionA: options.0, optionB: options.1) { winner, loser in
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
                    title: "Suivant",
                    isEnabled: viewModel.canAdvanceAdaptive,
                    height: Metrics.control
                ) {
                    viewModel.goNextAdaptive()
                }
            }

            Button {
                viewModel.finishNow()
            } label: {
                Text("Passer les questions et voir mes films")
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
                .accessibilityLabel(isFirst ? "Quitter la recherche" : "Revenir à l'écran précédent")

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
        .accessibilityLabel("Ce que ça change : \(text)")
    }

    // MARK: - Erreur

    private func errorView(_ message: String) -> some View {
        PlanEmptyState(
            icon: .salle,
            title: "La recherche s'est interrompue",
            message: message,
            actionTitle: "Réessayer",
            action: { viewModel.retrySubmit() },
            secondaryTitle: "Recommencer du début",
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
