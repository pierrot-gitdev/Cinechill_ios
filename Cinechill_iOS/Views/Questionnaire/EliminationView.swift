//
//  EliminationView.swift
//  Cinechill_iOS
//

import SwiftUI

/// Élimination parmi quatre films réels du pool courant — un signal de rejet plus large qu'un
/// duel (voir `PairwiseComparisonView`) : on écarte le film le moins tentant plutôt que de désigner
/// un favori parmi deux.
struct EliminationView: View {
    let options: [CandidateRow]
    let onEliminate: (_ loser: CandidateRow) -> Void

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(options) { candidate in
                    posterCard(candidate)
                }
            }
        }
        .padding(22)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.08), radius: 20, y: 10)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.5), .white.opacity(0.05)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(QuestionStep.elimination.title)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle = QuestionStep.elimination.subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func posterCard(_ candidate: CandidateRow) -> some View {
        Button {
            onEliminate(candidate)
        } label: {
            VStack(spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    if let url = candidate.posterURL {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().scaledToFill()
                            default:
                                posterPlaceholder
                            }
                        }
                    } else {
                        posterPlaceholder
                    }
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.white, .black.opacity(0.5))
                        .padding(6)
                }
                .aspectRatio(2 / 3, contentMode: .fill)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.gray.opacity(0.2), lineWidth: 1)
                )

                Text(candidate.title ?? "Sans titre")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(PressableScaleStyle(scale: 0.95))
    }

    private var posterPlaceholder: some View {
        ZStack {
            Rectangle().fill(Color(.secondarySystemBackground))
            Image(systemName: "film")
                .font(.title)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    EliminationView(
        options: [
            CandidateRow(id: 1, title: "Dune", overview: nil, posterPath: nil, voteAverage: 8, voteCount: 1000, popularity: 90, genreIds: [878], releaseDate: "2021-01-01", originCountry: ["US"]),
            CandidateRow(id: 2, title: "La La Land", overview: nil, posterPath: nil, voteAverage: 8, voteCount: 1000, popularity: 80, genreIds: [10749], releaseDate: "2016-01-01", originCountry: ["US"]),
            CandidateRow(id: 3, title: "Get Out", overview: nil, posterPath: nil, voteAverage: 7.5, voteCount: 900, popularity: 70, genreIds: [27, 53], releaseDate: "2017-01-01", originCountry: ["US"]),
            CandidateRow(id: 4, title: "Amélie", overview: nil, posterPath: nil, voteAverage: 8, voteCount: 800, popularity: 60, genreIds: [35], releaseDate: "2001-01-01", originCountry: ["FR"]),
        ],
        onEliminate: { _ in }
    )
    .padding()
}
