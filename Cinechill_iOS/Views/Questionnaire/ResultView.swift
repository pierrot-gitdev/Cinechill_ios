//
//  ResultView.swift
//  Cinechill_iOS
//

import SwiftUI

struct ResultView: View {
    let results: [RecommendationResult]
    let onRestart: () -> Void

    @EnvironmentObject private var libraryStore: LibraryStore
    @State private var appeared = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                    ResultCardView(rank: index + 1, result: result)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 24)
                        .animation(
                            .spring(response: 0.5, dampingFraction: 0.8).delay(Double(index) * 0.12),
                            value: appeared
                        )
                }
                restartButton
            }
            .padding()
        }
        .onAppear { appeared = true }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Votre trio du soir")
                .font(.system(size: 26, weight: .bold, design: .rounded))
            Text("Classé selon vos réponses — le pourcentage reflète la correspondance, pas une note du film.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var restartButton: some View {
        Button {
            appeared = false
            onRestart()
        } label: {
            Label("Refaire le quiz", systemImage: "arrow.counterclockwise")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.bordered)
        .tint(.indigo)
        .padding(.top, 4)
    }
}

private struct ResultCardView: View {
    let rank: Int
    let result: RecommendationResult

    @EnvironmentObject private var libraryStore: LibraryStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                poster
                VStack(alignment: .leading, spacing: 6) {
                    Text("#\(rank)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text(result.item.title)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(result.item.mediaType.singularLabel) · \(result.item.displayYear)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    reasonChips
                }
                Spacer(minLength: 0)
                ScoreRing(score: result.matchScore)
            }
            actions
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var poster: some View {
        AsyncImage(url: result.item.posterURL) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            default:
                ZStack {
                    Rectangle().fill(Color(.tertiarySystemBackground))
                    Image(systemName: "film")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 72, height: 104)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var reasonChips: some View {
        FlowLayout(spacing: 6) {
            ForEach(result.reasons, id: \.self) { reason in
                Text(reason)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.indigo)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.indigo.opacity(0.12), in: Capsule())
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button {
                libraryStore.addToWatchlist(result.item)
            } label: {
                Label(
                    libraryStore.isInWatchlist(result.item) ? "Dans la watchlist" : "Ajouter",
                    systemImage: libraryStore.isInWatchlist(result.item) ? "checkmark" : "bookmark"
                )
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(.indigo)
            .disabled(libraryStore.isInWatchlist(result.item))

            NavigationLink(destination: ItemDetailView(item: result.item)) {
                Text("Voir le détail")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.bordered)
        }
    }
}

/// Anneau de progression animé (0 → matchScore%) affiché sur chaque carte résultat.
private struct ScoreRing: View {
    let score: Int
    @State private var animatedProgress: CGFloat = 0

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.2), lineWidth: 5)
            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(
                    AngularGradient(colors: [.indigo, .pink], center: .center),
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            Text("\(score)%")
                .font(.caption2.weight(.bold))
                .contentTransition(.numericText())
        }
        .frame(width: 46, height: 46)
        .onAppear {
            withAnimation(.easeOut(duration: 0.9).delay(0.15)) {
                animatedProgress = CGFloat(score) / 100
            }
        }
    }
}

#Preview {
    NavigationStack {
        ResultView(
            results: [
                RecommendationResult(
                    item: MediaItem(
                        tmdbId: 1,
                        mediaType: .movie,
                        title: "Interstellar",
                        posterPath: nil,
                        overview: nil,
                        voteAverage: 8.3,
                        genreIds: [],
                        releaseDate: "2014-01-01"
                    ),
                    matchScore: 92,
                    reasons: ["SF / Fantastique", "2h+", "Disponible sur Netflix"]
                )
            ],
            onRestart: {}
        )
    }
    .environmentObject(LibraryStore())
}
