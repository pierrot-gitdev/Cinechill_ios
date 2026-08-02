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
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 44))
                .foregroundStyle(
                    LinearGradient(colors: [.indigo, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
            VStack(spacing: 10) {
                Text("CinéMatch")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text("Répondez à quelques questions, on trouve votre trio de films parfait pour ce soir.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Button {
                viewModel.start(preferredPlatformIDs: libraryStore.preferredPlatformIDs)
            } label: {
                Text("Commencer le quiz")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(.indigo)
            .padding(.horizontal, 40)
            Text("~45 secondes · 11 questions")
                .font(.caption)
                .foregroundStyle(.secondary)
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
        VStack(spacing: 8) {
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
                        .background(Color(.secondarySystemBackground), in: Circle())
                }
                Spacer()
                Text("Question \(viewModel.stepIndex + 1) sur \(viewModel.steps.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: viewModel.progress)
                .tint(.indigo)
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    @ViewBuilder
    private func questionCard(for step: QuestionStep) -> some View {
        switch step {
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
        Button(viewModel.isLastStep ? "Voir mes films" : "Suivant") {
            viewModel.goNext()
        }
        .buttonStyle(.borderedProminent)
        .tint(.indigo)
        .disabled(!viewModel.canAdvance)
        .frame(maxWidth: .infinity)
        .padding()
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 18) {
            ProgressView()
                .controlSize(.large)
                .tint(.indigo)
            Text("On croise vos réponses avec des dizaines de milliers de films…")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
