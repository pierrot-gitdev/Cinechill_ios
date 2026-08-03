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
    @State private var showProfile = false

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundGradient
                    .ignoresSafeArea()

                content
            }
            .safeAreaInset(edge: .top) {
                if viewModel.phase == .intro {
                    AppHeaderView(onProfileTap: { showProfile = true })
                        .padding(.horizontal)
                        .padding(.top, 10)
                        .padding(.bottom, 6)
                        .background(.ultraThinMaterial)
                }
            }
            .navigationBarHidden(true)
            .fullScreenCover(isPresented: $showProfile) {
                ProfileView()
                    .environmentObject(profileStore)
                    .environmentObject(libraryStore)
                    .environmentObject(authService)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .intro:
            introView
        case .trunk:
            trunkFlow
        case .poolLoading:
            LoadingAnimationView(messages: [
                "On regarde ce qui correspond à vos premiers critères…",
                "On prépare un pool de films sur mesure…",
            ])
        case .tier1, .tier2:
            adaptiveFlow
        case .enriching:
            LoadingAnimationView(messages: [
                "On affine — on regarde ces films de plus près…",
                "Durée, casting, bande-annonce… on creuse les meilleurs candidats.",
            ])
        case .finalizing:
            LoadingAnimationView()
        case .results:
            ResultView(results: viewModel.results, onRestart: { viewModel.restart() })
        case .error(let message):
            errorView(message)
        }
    }

    // MARK: - Intro

    private var introView: some View {
        VStack(spacing: 28) {
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(
                        LinearGradient(colors: [.indigo, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 96, height: 96)
                    .shadow(color: .indigo.opacity(0.35), radius: 24, y: 12)
                Image(systemName: "popcorn.fill")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(.white)
            }
            VStack(spacing: 10) {
                Text("CinéMatch")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text("Répondez à quelques questions, on trouve votre trio de films parfait pour ce soir.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Button {
                viewModel.start(preferredPlatformIDs: libraryStore.preferredPlatformIDs)
            } label: {
                HStack(spacing: 8) {
                    Text("Commencer le quiz")
                        .font(.headline)
                    Image(systemName: "arrow.right")
                        .font(.subheadline.weight(.bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(colors: [.indigo, .pink], startPoint: .leading, endPoint: .trailing),
                    in: Capsule()
                )
                .shadow(color: .indigo.opacity(0.3), radius: 16, y: 8)
            }
            .buttonStyle(PressableScaleStyle(scale: 0.97))
            .padding(.horizontal, 40)
            Spacer()
            Spacer()
        }
        .padding()
    }

    // MARK: - Socle (T1-T4)

    private var trunkFlow: some View {
        VStack(spacing: 0) {
            trunkProgressHeader
            ScrollView {
                trunkQuestionCard(for: viewModel.currentTrunkStep)
                    .padding(.horizontal)
                    .padding(.top, 24)
                    .id(viewModel.currentTrunkStep)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        )
                    )
            }
            trunkNavigationBar
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.trunkIndex)
    }

    private var trunkProgressHeader: some View {
        VStack(spacing: 12) {
            HStack {
                Button {
                    if viewModel.isFirstTrunkStep {
                        viewModel.restart()
                    } else {
                        viewModel.goBackTrunk()
                    }
                } label: {
                    Image(systemName: viewModel.isFirstTrunkStep ? "xmark" : "chevron.left")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .background(.ultraThinMaterial, in: Circle())
                }
                Spacer()
                Text("\(viewModel.trunkIndex + 1) / 4")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            trunkStepDots
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    /// Indicateur de progression en pastilles — le socle a un total connu (4), contrairement à
    /// la phase adaptative qui suit (voir `adaptiveProgressHeader`).
    private var trunkStepDots: some View {
        HStack(spacing: 5) {
            ForEach(0..<4, id: \.self) { index in
                Capsule()
                    .fill(trunkDotColor(for: index))
                    .frame(width: index == viewModel.trunkIndex ? 20 : 6, height: 6)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: viewModel.trunkIndex)
    }

    private func trunkDotColor(for index: Int) -> AnyShapeStyle {
        if index < viewModel.trunkIndex {
            return AnyShapeStyle(Color.indigo)
        } else if index == viewModel.trunkIndex {
            return AnyShapeStyle(LinearGradient(colors: [.indigo, .pink], startPoint: .leading, endPoint: .trailing))
        } else {
            return AnyShapeStyle(Color.gray.opacity(0.25))
        }
    }

    @ViewBuilder
    private func trunkQuestionCard(for step: QuestionStep) -> some View {
        switch step {
        case .contentFormat:
            singleSelectCard(step: step, options: ContentFormat.chipOptions, current: viewModel.answers.contentFormat) { id in
                if let value = ContentFormat(rawValue: id) { viewModel.select(value, in: \.contentFormat) }
            }
        case .genres:
            QuestionCardView(
                step: step,
                options: Genre.chipOptions,
                selectedIDs: Set(viewModel.answers.genres.map(\.rawValue)),
                onToggle: { id in
                    if let value = Genre(rawValue: id) { viewModel.toggleGenre(value) }
                }
            )
        case .platforms:
            QuestionCardView(
                step: step,
                options: viewModel.availablePlatforms.map { ChipOption(id: $0.id, label: $0.name) },
                selectedIDs: viewModel.answers.platformIDs,
                onToggle: { id in viewModel.togglePlatform(id) }
            )
        case .audience:
            singleSelectCard(step: step, options: Audience.chipOptions, current: viewModel.answers.audience) { id in
                if let value = Audience(rawValue: id) { viewModel.select(value, in: \.audience) }
            }
        default:
            EmptyView()
        }
    }

    private var trunkNavigationBar: some View {
        Button {
            viewModel.goNextTrunk()
        } label: {
            HStack(spacing: 8) {
                Text("Suivant")
                    .font(.headline)
                Image(systemName: "arrow.right")
                    .font(.subheadline.weight(.bold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background {
                Capsule().fill(
                    viewModel.canAdvanceTrunk ?
                        LinearGradient(colors: [.indigo, .pink], startPoint: .leading, endPoint: .trailing) :
                        LinearGradient(colors: [.gray.opacity(0.35)], startPoint: .leading, endPoint: .trailing)
                )
            }
            .shadow(color: viewModel.canAdvanceTrunk ? .indigo.opacity(0.3) : .clear, radius: 16, y: 8)
        }
        .buttonStyle(PressableScaleStyle(scale: 0.97))
        .disabled(!viewModel.canAdvanceTrunk)
        .padding()
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

    // MARK: - Phase adaptative (tier 1 / tier 2)

    private var adaptiveFlow: some View {
        VStack(spacing: 0) {
            adaptiveProgressHeader
            ScrollView {
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
                .padding(.horizontal)
                .padding(.top, 24)
                .id(viewModel.currentDimension)
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    )
                )
            }
            adaptiveNavigationBar
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.currentDimension)
    }

    private var adaptiveProgressHeader: some View {
        HStack {
            Button {
                if viewModel.canGoBackAdaptive {
                    viewModel.goBackAdaptive()
                } else {
                    viewModel.restart()
                }
            } label: {
                Image(systemName: viewModel.canGoBackAdaptive ? "chevron.left" : "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .background(.ultraThinMaterial, in: Circle())
            }
            Spacer()
            Text("Question \(viewModel.questionsAskedCount + 1)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    @ViewBuilder
    private func adaptiveQuestionCard(for dimension: AdaptiveDimension) -> some View {
        let step = dimension.questionStep
        switch dimension {
        case .mood:
            EmptyView() // Toujours présentée en comparaison directe — voir `pairwiseOptions`.
        case .elimination:
            EmptyView() // Toujours présentée en grille d'élimination — voir `eliminationOptions`.
        case .origin:
            singleSelectCard(step: step, options: OriginPreference.chipOptions, current: viewModel.answers.origin) { id in
                if let value = OriginPreference(rawValue: id) { viewModel.select(value, in: \.origin) }
            }
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
        case .runtime:
            singleSelectCard(step: step, options: RuntimePreference.chipOptions, current: viewModel.answers.runtime) { id in
                if let value = RuntimePreference(rawValue: id) { viewModel.select(value, in: \.runtime) }
            }
        case .era:
            singleSelectCard(step: step, options: EraPreference.chipOptions, current: viewModel.answers.era) { id in
                if let value = EraPreference(rawValue: id) { viewModel.select(value, in: \.era) }
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
        case .surpriseIntensity:
            IntensitySliderView(value: Binding(
                get: { viewModel.answers.surpriseIntensity },
                set: { viewModel.answers.surpriseIntensity = $0 }
            ))
        }
    }

    /// Le "Suivant" ne s'affiche que pour les chips classiques — la comparaison directe avance
    /// d'elle-même au tap. "Voir mes films maintenant" reste toujours accessible en dessous : c'est
    /// elle qui porte le compromis "plus de questions = plus précis, mais vous décidez où vous
    /// arrêter" (voir la spec).
    private var adaptiveNavigationBar: some View {
        VStack(spacing: 10) {
            if viewModel.pairwiseOptions == nil && viewModel.eliminationOptions == nil {
                Button {
                    viewModel.goNextAdaptive()
                } label: {
                    HStack(spacing: 8) {
                        Text("Suivant")
                            .font(.headline)
                        Image(systemName: "arrow.right")
                            .font(.subheadline.weight(.bold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background {
                        Capsule().fill(
                            viewModel.canAdvanceAdaptive ?
                                LinearGradient(colors: [.indigo, .pink], startPoint: .leading, endPoint: .trailing) :
                                LinearGradient(colors: [.gray.opacity(0.35)], startPoint: .leading, endPoint: .trailing)
                        )
                    }
                    .shadow(color: viewModel.canAdvanceAdaptive ? .indigo.opacity(0.3) : .clear, radius: 16, y: 8)
                }
                .buttonStyle(PressableScaleStyle(scale: 0.97))
                .disabled(!viewModel.canAdvanceAdaptive)
            }

            Button {
                viewModel.finishNow()
            } label: {
                Text("Voir mes films maintenant")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.indigo)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
        }
        .padding()
    }

    // MARK: - Error

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
            Button("Réessayer") {
                viewModel.retrySubmit()
            }
            .buttonStyle(.borderedProminent)
            .tint(.indigo)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Background

    /// Un léger halo de marque (indigo/rose) dès que le quiz est en cours — l'ambiance ne se
    /// choisit plus par chip (voir `PairwiseComparisonView`), donc plus de teinte dynamique par
    /// mood ; on garde un fond identifiable pendant tout le parcours plutôt qu'une valeur figée.
    private var backgroundGradient: some View {
        Group {
            if viewModel.phase != .intro && viewModel.phase != .results {
                LinearGradient(
                    colors: [Color.indigo.opacity(0.08), Color(.systemBackground)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            } else {
                Color(.systemBackground)
            }
        }
        .animation(.easeInOut(duration: 0.6), value: viewModel.phase)
    }
}


/// État "les résultats se compilent" : bobine de film qui tourne devant un halo de projecteur,
/// bande perforée qui défile en dessous, et des messages à thème cinéma — plus évocateur qu'un
/// simple `ProgressView`.
private struct LoadingAnimationView: View {
    static let defaultMessages = [
        "On prépare la projection…",
        "On croise vos réponses avec des dizaines de milliers de films…",
        "On sélectionne les meilleures bobines…",
        "Le clap va tomber…"
    ]

    var messages: [String] = Self.defaultMessages
    @State private var messageIndex = 0

    var body: some View {
        VStack(spacing: 30) {
            FilmReelView()
            FilmstripMarquee()
                .frame(width: 220)
            Text(messages[messageIndex % messages.count])
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .id(messageIndex)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_700_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.35)) {
                    messageIndex = (messageIndex + 1) % messages.count
                }
            }
        }
    }
}

/// Bobine de film en rotation continue, devant un halo pulsant façon lumière de projecteur.
private struct FilmReelView: View {
    private let holeCount = 6

    @State private var rotation: Double = 0
    @State private var glow = false

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.indigo.opacity(0.35), .clear],
                        center: .center, startRadius: 4, endRadius: 70
                    )
                )
                .frame(width: 140, height: 140)
                .scaleEffect(glow ? 1.15 : 0.9)

            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.indigo, .pink], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 84, height: 84)
                Circle()
                    .fill(Color(.systemBackground))
                    .frame(width: 68, height: 68)

                ForEach(0..<holeCount, id: \.self) { index in
                    Circle()
                        .fill(LinearGradient(colors: [.indigo, .pink], startPoint: .top, endPoint: .bottom))
                        .frame(width: 15, height: 15)
                        .offset(y: -25)
                        .rotationEffect(.degrees(Double(index) / Double(holeCount) * 360))
                }

                Circle()
                    .fill(Color(.systemBackground))
                    .frame(width: 18, height: 18)
                Circle()
                    .strokeBorder(Color.indigo.opacity(0.5), lineWidth: 2)
                    .frame(width: 18, height: 18)
            }
            .rotationEffect(.degrees(rotation))
        }
        .onAppear {
            withAnimation(.linear(duration: 2.4).repeatForever(autoreverses: false)) {
                rotation = 360
            }
            withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true)) {
                glow = true
            }
        }
    }
}

/// Bande de pellicule perforée qui défile en boucle — motif uniforme, donc le bouclage est
/// parfaitement continu quel que soit le décalage appliqué.
private struct FilmstripMarquee: View {
    private let holeSize: CGFloat = 8
    private let spacing: CGFloat = 10
    private let holeCount = 24

    @State private var offsetX: CGFloat = 0

    private var unitWidth: CGFloat { holeSize + spacing }

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<holeCount, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.indigo.opacity(0.3))
                    .frame(width: holeSize, height: holeSize)
            }
        }
        .offset(x: offsetX)
        .frame(height: holeSize)
        .clipped()
        .onAppear {
            let shift = CGFloat(holeCount / 2) * unitWidth
            withAnimation(.linear(duration: 5).repeatForever(autoreverses: false)) {
                offsetX = -shift
            }
        }
    }
}
