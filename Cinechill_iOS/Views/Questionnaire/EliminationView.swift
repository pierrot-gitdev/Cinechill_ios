//
//  EliminationView.swift
//  Cinechill_iOS
//

import SwiftUI

/// L'élimination : quatre affiches, on écarte celle qui tente le moins.
///
/// Signal plus large qu'un duel — écarter un film parmi quatre en dit plus long
/// qu'en préférer un parmi deux, et le rejet est un jugement que les gens portent
/// plus sûrement que l'adhésion.
struct EliminationView: View {
    let options: [CandidateRow]
    /// Le titre est projeté sur la toile par `SalleStage` et ne figure plus
    /// ici : c'est la salle qui interroge. Le sous-titre a suivi — il
    /// commentait le geste au lieu de le nommer.
    let onEliminate: (_ loser: CandidateRow) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: Metrics.gutter),
        GridItem(.flexible(), spacing: Metrics.gutter),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(options) { candidate in
                    posterChoice(candidate, maxHeight: 118)
                }
            }
        }
    }

    private func posterChoice(_ candidate: CandidateRow, maxHeight: CGFloat) -> some View {
        Button {
            onEliminate(candidate)
        } label: {
            VStack(spacing: 10) {
                CandidatePosterView(candidate: candidate, maxHeight: maxHeight)
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Ink.ink)
                            .frame(width: 18, height: 18)
                            .background(Ink.ground.opacity(0.85))
                            .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                            .padding(6)
                    }

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
        .accessibilityHint(String(localized: "Écarter ce film : c'est celui-ci qui te tente le moins", bundle: .app))
    }
}

#Preview("Élimination") {
    ZStack {
        Ink.ground.ignoresSafeArea()
        ScrollView {
            EliminationView(
                options: [
                    CandidateRow(id: 1, title: "Dune", overview: nil, posterPath: nil, voteAverage: 8, voteCount: 1000, popularity: 90, genreIds: [878], releaseDate: "2021-01-01", originCountry: ["US"]),
                    CandidateRow(id: 2, title: "La La Land", overview: nil, posterPath: nil, voteAverage: 8, voteCount: 1000, popularity: 80, genreIds: [10749], releaseDate: "2016-01-01", originCountry: ["US"]),
                    CandidateRow(id: 3, title: "Get Out", overview: nil, posterPath: nil, voteAverage: 7.5, voteCount: 900, popularity: 70, genreIds: [27, 53], releaseDate: "2017-01-01", originCountry: ["US"]),
                    CandidateRow(id: 4, title: "Amélie", overview: nil, posterPath: nil, voteAverage: 8, voteCount: 800, popularity: 60, genreIds: [35], releaseDate: "2001-01-01", originCountry: ["FR"]),
                ],
                onEliminate: { _ in }
            )
            .padding(Metrics.margin)
        }
    }
}
