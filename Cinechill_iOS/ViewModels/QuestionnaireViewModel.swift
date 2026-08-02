//
//  QuestionnaireViewModel.swift
//  Cinechill_iOS
//

import Foundation

/// Les 11 questions de CinéMatch, dans l'ordre d'affichage — voir la spec produit pour le détail
/// du mapping de chacune vers l'algorithme de recommandation (certaines filtrent le pool, d'autres
/// pondèrent le score — ce n'est plus affiché à l'utilisateur mais reste vrai côté algorithme).
enum QuestionStep: Int, CaseIterable, Hashable {
    case contentFormat, genres, platforms, audience, mood, origin, mindset, dealbreaker, popularity, cast, runtime, era

    var title: String {
        switch self {
        case .contentFormat: "Dessin animé ou film ?"
        case .genres: "Genres qui vous attirent"
        case .platforms: "Sur quelles plateformes pouvez-vous regarder ?"
        case .audience: "Avec qui regardez-vous ?"
        case .mood: "Quelle ambiance ce soir ?"
        case .origin: "Cinéma français ou plutôt international ?"
        case .mindset: "Là, tout de suite, vous avez plutôt envie de…"
        case .dealbreaker: "Qu'est-ce qui vous ferait le plus décrocher d'un film ?"
        case .popularity: "Blockbuster ou pépite méconnue ?"
        case .cast: "Un casting que vous reconnaissez, ou l'envie de découvrir de nouvelles têtes ?"
        case .runtime: "Combien de temps devant vous ?"
        case .era: "Récent ou vintage ?"
        }
    }

    var subtitle: String? {
        switch self {
        case .genres: "Jusqu'à \(QuestionnaireAnswers.maxGenres) genres"
        case .platforms: "On ne vous proposera que ce que vous pouvez regarder tout de suite"
        default: nil
        }
    }
}

@Observable
@MainActor
final class QuestionnaireViewModel {
    enum Phase: Equatable {
        case intro
        case question
        case loading
        case results
        case error(String)
    }

    private let recommendationClient: any RecommendationFetching
    private let metadataClient: any HomeMetadataFetching

    private(set) var phase: Phase = .intro
    private(set) var stepIndex = 0
    private(set) var availablePlatforms: [StreamingPlatform] = []
    private(set) var results: [RecommendationResult] = []
    var answers = QuestionnaireAnswers()

    let steps = QuestionStep.allCases

    init(recommendationClient: any RecommendationFetching, metadataClient: any HomeMetadataFetching) {
        self.recommendationClient = recommendationClient
        self.metadataClient = metadataClient
    }

    var currentStep: QuestionStep { steps[stepIndex] }
    var progress: Double { Double(stepIndex + 1) / Double(steps.count) }
    var isFirstStep: Bool { stepIndex == 0 }
    var isLastStep: Bool { stepIndex == steps.count - 1 }

    var canAdvance: Bool {
        switch currentStep {
        case .contentFormat: answers.contentFormat != nil
        case .genres: !answers.genres.isEmpty
        case .platforms: !answers.platformIDs.isEmpty
        case .audience: answers.audience != nil
        case .mood: answers.mood != nil
        case .mindset: answers.mindset != nil
        case .dealbreaker: answers.dealbreaker != nil
        case .origin, .popularity, .cast, .runtime, .era: true
        }
    }

    func start(preferredPlatformIDs: Set<String>) {
        answers = QuestionnaireAnswers()
        answers.platformIDs = preferredPlatformIDs
        stepIndex = 0
        phase = .question
        Task { await loadPlatformsIfNeeded() }
    }

    func loadPlatformsIfNeeded() async {
        guard availablePlatforms.isEmpty else { return }
        guard let providers = try? await metadataClient.movieProviders() else { return }
        availablePlatforms = StreamingPlatform.curated(from: providers)
    }

    func goBack() {
        guard stepIndex > 0 else { return }
        stepIndex -= 1
    }

    func goNext() {
        guard canAdvance else { return }
        guard !isLastStep else {
            Task { await submit() }
            return
        }
        stepIndex += 1
    }

    func toggleGenre(_ genre: Genre) {
        if answers.genres.contains(genre) {
            answers.genres.remove(genre)
        } else if answers.genres.count < QuestionnaireAnswers.maxGenres {
            answers.genres.insert(genre)
        }
    }

    func togglePlatform(_ id: String) {
        if answers.platformIDs.contains(id) {
            answers.platformIDs.remove(id)
        } else {
            answers.platformIDs.insert(id)
        }
    }

    func select<T: QuestionOption>(_ value: T, in keyPath: WritableKeyPath<QuestionnaireAnswers, T>) {
        answers[keyPath: keyPath] = value
    }

    func select<T: QuestionOption>(_ value: T, in keyPath: WritableKeyPath<QuestionnaireAnswers, T?>) {
        answers[keyPath: keyPath] = value
    }

    func restart() {
        phase = .intro
        stepIndex = 0
        results = []
    }

    func retrySubmit() {
        Task { await submit() }
    }

    private func submit() async {
        phase = .loading
        do {
            results = try await recommendationClient.fetchRecommendations(for: answers)
            phase = .results
        } catch {
            if error is CancellationError { return }
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            phase = .error(message)
        }
    }
}
