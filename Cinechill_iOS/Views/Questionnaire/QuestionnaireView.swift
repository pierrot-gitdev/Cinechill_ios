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
        case .question:
            questionFlow
        case .loading:
            loadingView
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
            .buttonStyle(ChipPressStyle())
            .padding(.horizontal, 40)
            Spacer()
            Spacer()
        }
        .padding()
    }

    // MARK: - Question flow

    private var questionFlow: some View {
        VStack(spacing: 0) {
            progressHeader
            ScrollView {
                questionCard(for: viewModel.currentStep)
                    .padding(.horizontal)
                    .padding(.top, 24)
                    .id(viewModel.currentStep)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        )
                    )
            }
            navigationBar
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.stepIndex)
    }

    private var progressHeader: some View {
        VStack(spacing: 12) {
            HStack {
                Button {
                    if viewModel.isFirstStep {
                        viewModel.restart()
                    } else {
                        viewModel.goBack()
                    }
                } label: {
                    Image(systemName: viewModel.isFirstStep ? "xmark" : "chevron.left")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .background(.ultraThinMaterial, in: Circle())
                }
                Spacer()
                Text("\(viewModel.stepIndex + 1) / \(viewModel.steps.count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            stepDots
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    /// Indicateur de progression en pastilles plutôt qu'une simple barre — chaque question
    /// franchie se voit distinctement, avec la question courante mise en avant.
    private var stepDots: some View {
        HStack(spacing: 5) {
            ForEach(viewModel.steps, id: \.self) { step in
                Capsule()
                    .fill(dotColor(for: step))
                    .frame(width: step == viewModel.currentStep ? 20 : 6, height: 6)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: viewModel.stepIndex)
    }

    private func dotColor(for step: QuestionStep) -> AnyShapeStyle {
        if step.rawValue < viewModel.stepIndex {
            return AnyShapeStyle(Color.indigo)
        } else if step == viewModel.currentStep {
            return AnyShapeStyle(LinearGradient(colors: [.indigo, .pink], startPoint: .leading, endPoint: .trailing))
        } else {
            return AnyShapeStyle(Color.gray.opacity(0.25))
        }
    }

    @ViewBuilder
    private func questionCard(for step: QuestionStep) -> some View {
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
        case .mood:
            singleSelectCard(step: step, options: Mood.chipOptions, current: viewModel.answers.mood) { id in
                if let value = Mood(rawValue: id) { viewModel.select(value, in: \.mood) }
            }
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

    private var navigationBar: some View {
        Button {
            viewModel.goNext()
        } label: {
            HStack(spacing: 8) {
                Text(viewModel.isLastStep ? "Voir mes films" : "Suivant")
                    .font(.headline)
                Image(systemName: viewModel.isLastStep ? "sparkles" : "arrow.right")
                    .font(.subheadline.weight(.bold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background {
                Capsule().fill(
                    viewModel.canAdvance ?
                        LinearGradient(colors: [.indigo, .pink], startPoint: .leading, endPoint: .trailing) :
                        LinearGradient(colors: [.gray.opacity(0.35)], startPoint: .leading, endPoint: .trailing)
                )
            }
            .shadow(color: viewModel.canAdvance ? .indigo.opacity(0.3) : .clear, radius: 16, y: 8)
        }
        .buttonStyle(ChipPressStyle())
        .disabled(!viewModel.canAdvance)
        .padding()
    }

    // MARK: - Loading

    private var loadingView: some View {
        LoadingAnimationView()
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

    /// Le fond dérive subtilement vers la couleur de l'ambiance choisie (Q4) une fois répondue —
    /// signature visuelle du quiz décrite dans la spec (section Design & UX).
    private var backgroundGradient: some View {
        Group {
            if let mood = viewModel.answers.mood, viewModel.phase == .question || viewModel.phase == .loading {
                LinearGradient(
                    colors: [moodColor(mood).opacity(0.18), Color(.systemBackground)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            } else {
                Color(.systemBackground)
            }
        }
        .animation(.easeInOut(duration: 0.6), value: viewModel.answers.mood)
    }

    private func moodColor(_ mood: Mood) -> Color {
        switch mood {
        case .lightFun: .yellow
        case .intense: .red
        case .emotional: .blue
        case .scary: .purple
        case .escapist: .teal
        case .thoughtful: .indigo
        }
    }
}

private struct ChipPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// État "les résultats se compilent" : bobine de film qui tourne devant un halo de projecteur,
/// bande perforée qui défile en dessous, et des messages à thème cinéma — plus évocateur qu'un
/// simple `ProgressView`.
private struct LoadingAnimationView: View {
    private static let messages = [
        "On prépare la projection…",
        "On croise vos réponses avec des dizaines de milliers de films…",
        "On sélectionne les meilleures bobines…",
        "Le clap va tomber…"
    ]

    @State private var messageIndex = 0

    var body: some View {
        VStack(spacing: 30) {
            FilmReelView()
            FilmstripMarquee()
                .frame(width: 220)
            Text(Self.messages[messageIndex])
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
                    messageIndex = (messageIndex + 1) % Self.messages.count
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
