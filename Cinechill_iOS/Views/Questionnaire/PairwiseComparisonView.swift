//
//  PairwiseComparisonView.swift
//  Cinechill_iOS
//

import SwiftUI

/// Le duel : deux affiches du vivier courant, on en choisit une.
///
/// C'est la seule question du parcours qui observe un comportement au lieu
/// d'écouter une déclaration — et c'est pour ça qu'elle ne saute jamais. La paire
/// n'est pas décorative : `QuestionEngine` la choisit aussi contrastée que possible,
/// comparer deux films semblables n'apprendrait rien.
struct PairwiseComparisonView: View {
    let optionA: CandidateRow
    let optionB: CandidateRow
    /// Le titre change quand le duel oppose deux films **vus** (C2) : la
    /// question parle alors de souvenirs, plus de paris. Sans valeur, le
    /// titre du duel de découverte reste celui de toujours.
    var title: String?
    var subtitle: String?
    let onPick: (_ winner: CandidateRow, _ loser: CandidateRow) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title ?? QuestionStep.posterDuel.title)
                    .planTitle()
                    .foregroundStyle(Ink.ink)
                    .fixedSize(horizontal: false, vertical: true)

                if let subtitle = subtitle ?? QuestionStep.posterDuel.subtitle {
                    Text(subtitle)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Ink.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(alignment: .top, spacing: Metrics.gutter) {
                posterChoice(optionA, opponent: optionB)
                posterChoice(optionB, opponent: optionA)
            }
        }
    }

    private func posterChoice(_ candidate: CandidateRow, opponent: CandidateRow) -> some View {
        Button {
            onPick(candidate, opponent)
        } label: {
            VStack(spacing: 10) {
                CandidatePosterView(candidate: candidate)

                Text(candidate.title ?? String(localized: "Sans titre", bundle: .app))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Ink.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .buttonStyle(PressableScaleStyle(scale: 0.97))
        .accessibilityLabel(candidate.title ?? String(localized: "Film sans titre", bundle: .app))
        .accessibilityHint(String(localized: "Choisir ce film : c'est celui-ci qui te tente le plus", bundle: .app))
    }
}

/// L'affiche d'un candidat, au format de l'application : un seul rayon, un filet,
/// et une réserve lisible quand TMDB n'a pas d'image.
struct CandidatePosterView: View {
    let candidate: CandidateRow

    var body: some View {
        Group {
            if let url = candidate.posterURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .aspectRatio(2 / 3, contentMode: .fill)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                .strokeBorder(Ink.rule, lineWidth: 1)
        }
    }

    private var placeholder: some View {
        ZStack {
            Rectangle().fill(Ink.ground)
            CinechillHallIconView(.salle)
                .frame(width: 22, height: 22)
                .foregroundStyle(Ink.ink3)
        }
    }
}

#Preview("Duel") {
    ZStack {
        Ink.ground.ignoresSafeArea()
        PairwiseComparisonView(
            optionA: CandidateRow(
                id: 1, title: "Dune", overview: nil, posterPath: nil, voteAverage: 8,
                voteCount: 1000, popularity: 90, genreIds: [878], releaseDate: "2021-01-01", originCountry: ["US"]
            ),
            optionB: CandidateRow(
                id: 2, title: "Portrait de la jeune fille en feu", overview: nil, posterPath: nil, voteAverage: 8,
                voteCount: 1000, popularity: 40, genreIds: [18], releaseDate: "2019-01-01", originCountry: ["FR"]
            ),
            onPick: { _, _ in }
        )
        .padding(Metrics.margin)
    }
}
