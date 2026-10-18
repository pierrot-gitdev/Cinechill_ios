//
//  DarkerQuestionPrompt.swift
//  Cinechill_iOS
//

import SwiftUI

/// « Lequel est le plus sombre ? » : deux films de la galerie, en tête de la
/// fiche, à la place de la question du lendemain une fois celle-ci répondue.
///
/// C'est le seul moment calme où on la pose : jamais pendant une soirée, une
/// fois par jour au plus (le serveur y veille). Les réponses apprennent au
/// moteur ce que « Plus sombre » veut dire ; quand il l'a appris, le serveur
/// ne la renvoie plus.
///
/// Toucher une affiche répond. « Pareil » répond aussi ; « Plus tard » retire
/// le bloc sans rien envoyer.
struct DarkerQuestionPrompt: View {
    let question: CineMatchDarkerQuestion
    let client: any CineMatchFetching
    /// Le bloc a fini son travail : la fiche le retire.
    let onFinished: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    private enum Phase: Equatable {
        case asking
        /// La réponse part : le film désigné, ou `nil` pour « Pareil ».
        case sending(Int?)
        case done
        case failed
    }

    @State private var phase: Phase = .asking

    /// Une affiche de fiche, pas une affiche d'écran : deux côte à côte
    /// tiennent sur un iPhone SE sans repousser la fiche hors de vue.
    private static let posterWidth: CGFloat = 120
    /// Deux lignes de titre réservées, pour que les deux affiches restent
    /// alignées quand un seul titre passe à la ligne.
    @ScaledMetric(relativeTo: .caption) private var titleHeight: CGFloat = 31

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if phase == .done {
                HStack(alignment: .firstTextBaseline, spacing: 11) {
                    PlanLight()
                    Text("C'est noté.", bundle: .app)
                        .planFont(13.5)
                        .foregroundStyle(Ink.ink)
                }
                .accessibilityElement(children: .combine)
                .transition(.opacity)
            } else {
                content
            }
        }
        .padding(.horizontal, Metrics.margin)
        .padding(.top, 18)
        .animation(Metrics.shift, value: phase)
        .task(id: phase) {
            guard phase == .done else { return }
            try? await Task.sleep(for: .seconds(1.4))
            onFinished()
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Lequel est le plus sombre ?", bundle: .app)
                    .planTitle(18)
                    .foregroundStyle(Ink.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text("Ta réponse rend « Plus sombre » plus juste.", bundle: .app)
                    .planFont(12.5)
                    .foregroundStyle(Ink.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(alignment: .top, spacing: Metrics.gutter) {
                choice(question.first)
                choice(question.second)
            }

            answers

            if phase == .failed {
                Text("On n'a pas pu enregistrer ta réponse. Réessaie.", bundle: .app)
                    .planFont(12)
                    .foregroundStyle(Ink.warn)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
        }
    }

    /// « Pareil » et « Plus tard » côte à côte ; en très grand texte, l'un
    /// sous l'autre, comme les réponses de la question du lendemain.
    @ViewBuilder
    private var answers: some View {
        if typeSize.isAccessibilitySize {
            VStack(spacing: Metrics.gutter) {
                sameButton
                laterButton
            }
        } else {
            HStack(spacing: Metrics.gutter) {
                sameButton
                laterButton
            }
        }
    }

    private var isBusy: Bool {
        if case .sending = phase { return true }
        return false
    }

    private func choice(_ film: CineMatchGalleryFilm) -> some View {
        let isChosen = phase == .sending(film.id)
        return Button {
            Task { await send(film.id) }
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                PosterFrame(posterPath: film.posterPath, title: film.title)
                    .overlay(
                        RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                            .strokeBorder(Ink.paper, lineWidth: 1.5)
                            .opacity(isChosen ? 1 : 0)
                    )
                Text(film.title)
                    .planFont(12)
                    .foregroundStyle(Ink.ink)
                    .lineLimit(typeSize.isAccessibilitySize ? 4 : 2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, minHeight: titleHeight, alignment: .topLeading)
            }
            .frame(maxWidth: Self.posterWidth)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableScaleStyle(scale: 0.97))
        // Une seule réponse à la fois : la seconde serait refusée par le
        // serveur, et l'écran dirait l'inverse de ce qui est enregistré.
        .disabled(isBusy)
        .opacity(isBusy && !isChosen ? 0.45 : 1)
        .accessibilityLabel(film.title)
        .accessibilityHint(String(localized: "Le désigne comme le plus sombre.", bundle: .app))
    }

    private var sameButton: some View {
        PlanSecondaryButton(
            title: String(localized: "Pareil", bundle: .app),
            isEnabled: !isBusy
        ) {
            Task { await send(nil) }
        }
    }

    private var laterButton: some View {
        Button(action: onFinished) {
            Text("Plus tard", bundle: .app)
                .planFont(14.5, weight: .medium)
                .foregroundStyle(Ink.ink2)
                .frame(maxWidth: .infinity, minHeight: Metrics.buttonSecondary)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableScaleStyle(scale: 0.985))
        .disabled(isBusy)
    }

    private func send(_ darkerID: Int?) async {
        phase = .sending(darkerID)
        do {
            try await client.recordDarker(question, darkerID: darkerID)
            Haptics.success()
            phase = .done
        } catch {
            phase = .failed
        }
    }
}

#Preview("Lequel est le plus sombre ?") {
    ZStack(alignment: .top) {
        Ink.ground.ignoresSafeArea()
        DarkerQuestionPrompt(
            question: CineMatchDarkerQuestion(
                first: CineMatchGalleryFilm(
                    id: 935,
                    title: "Docteur Folamour ou : comment j'ai appris à ne plus m'en faire et à aimer la bombe",
                    posterPath: nil, releaseDate: nil, genreIDs: []
                ),
                second: CineMatchGalleryFilm(id: 832, title: "M", posterPath: nil, releaseDate: nil, genreIDs: [])
            ),
            client: BackendCineMatchClient(),
            onFinished: {}
        )
    }
}
