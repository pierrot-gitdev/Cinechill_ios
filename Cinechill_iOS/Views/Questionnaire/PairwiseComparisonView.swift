//
//  PairwiseComparisonView.swift
//  Cinechill_iOS
//

import SwiftUI

/// Comparaison directe entre deux films réels du pool courant — le format d'interaction phare du
/// moteur de préférence actif (voir la spec). Choisis délibérément les plus différents l'un de
/// l'autre par `QuestionnaireViewModel` : comparer deux films quasi identiques n'apporterait aucun
/// signal. Le gagnant fait remonter les films qui lui ressemblent, le perdant les fait redescendre.
struct PairwiseComparisonView: View {
    let optionA: CandidateRow
    let optionB: CandidateRow
    let onPick: (_ winner: CandidateRow, _ loser: CandidateRow) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            HStack(spacing: 14) {
                posterCard(optionA)
                posterCard(optionB)
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
            Text("Plutôt ce soir…")
                .font(.system(size: 24, weight: .bold, design: .rounded))
            Text("Choisissez celui qui vous tente le plus — les deux comptent, il n'y a pas de mauvaise réponse.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func posterCard(_ candidate: CandidateRow) -> some View {
        Button {
            let loser = candidate.id == optionA.id ? optionB : optionA
            onPick(candidate, loser)
        } label: {
            VStack(spacing: 8) {
                ZStack {
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
                }
                .aspectRatio(2 / 3, contentMode: .fill)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
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
    PairwiseComparisonView(
        optionA: CandidateRow(
            id: 1, title: "Dune", overview: nil, posterPath: nil, voteAverage: 8,
            voteCount: 1000, popularity: 90, genreIds: [878], releaseDate: "2021-01-01", originCountry: ["US"]
        ),
        optionB: CandidateRow(
            id: 2, title: "La La Land", overview: nil, posterPath: nil, voteAverage: 8,
            voteCount: 1000, popularity: 80, genreIds: [10749], releaseDate: "2016-01-01", originCountry: ["US"]
        ),
        onPick: { _, _ in }
    )
    .padding()
}
