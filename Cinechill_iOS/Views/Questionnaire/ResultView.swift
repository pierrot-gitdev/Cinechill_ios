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
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "popcorn.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(
                        LinearGradient(colors: [.indigo, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                Text("CINÉMATCH")
                    .font(.caption.weight(.bold))
                    .tracking(1.4)
                    .foregroundStyle(.secondary)
            }
            Text("Votre trio du soir")
                .font(.system(size: 32, weight: .bold, design: .rounded))
            Text("Classé selon vos réponses, du meilleur match au troisième.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 4)
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
    @Environment(\.openURL) private var openURL
    @State private var isAddingToWatchlist = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            NavigationLink(destination: ItemDetailView(item: result.item)) {
                VStack(alignment: .leading, spacing: 10) {
                    rankBadge
                    HStack(alignment: .top, spacing: 14) {
                        poster
                        VStack(alignment: .leading, spacing: 6) {
                            Text(result.item.title)
                                .font(.headline)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("\(result.item.mediaType.singularLabel) · \(result.item.displayYear)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            actions
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onChange(of: libraryStore.isInWatchlist(result.item)) { _, inWatchlist in
            if inWatchlist { isAddingToWatchlist = false }
        }
        .task(id: isAddingToWatchlist) {
            guard isAddingToWatchlist else { return }
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            if !Task.isCancelled { isAddingToWatchlist = false }
        }
    }

    private var rankBadge: some View {
        Text("CinéMatch n°\(rank)")
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(
                    LinearGradient(colors: [.indigo, .pink], startPoint: .leading, endPoint: .trailing)
                )
            )
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

    private var actions: some View {
        HStack(spacing: 10) {
            watchlistButton

            if result.trailerURL != nil {
                iconButton(systemImage: "play.rectangle.fill", action: openTrailer)
            }

            if result.watchWebURL != nil {
                iconButton(systemImage: "arrow.up.forward.app.fill", action: openStreamingApp)
            }
        }
    }

    private var watchlistButton: some View {
        let inWatchlist = libraryStore.isInWatchlist(result.item)
        return Button {
            isAddingToWatchlist = true
            libraryStore.addToWatchlist(result.item)
        } label: {
            Group {
                if isAddingToWatchlist && !inWatchlist {
                    ProgressView()
                        .tint(.white)
                } else {
                    Label(
                        inWatchlist ? "Dans la watchlist" : "Ajouter",
                        systemImage: inWatchlist ? "checkmark" : "bookmark"
                    )
                    .font(.caption.weight(.semibold))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .tint(.indigo)
        .disabled(inWatchlist || isAddingToWatchlist)
    }

    private func iconButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .frame(width: 20, height: 20)
                .padding(8)
        }
        .buttonStyle(.bordered)
        .tint(.indigo)
    }

    // MARK: - Actions

    private func openTrailer() {
        guard let appURL = result.trailerAppURL, let webURL = result.trailerURL else { return }
        if UIApplication.shared.canOpenURL(appURL) {
            UIApplication.shared.open(appURL)
        } else {
            openURL(webURL)
        }
    }

    /// Ouvre l'app native de la plateforme si elle est installée (ex. Netflix via `nflx://`),
    /// sinon retombe sur le site web du service.
    private func openStreamingApp() {
        for candidate in result.watchAppURLCandidates where UIApplication.shared.canOpenURL(candidate) {
            UIApplication.shared.open(candidate)
            return
        }
        guard let webURL = result.watchWebURL else { return }
        openURL(webURL)
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
                    reasons: ["SF / Fantastique", "2h+", "Disponible sur Netflix"],
                    trailerKey: "zSWdZVtXT7E",
                    providerIDs: [8]
                )
            ],
            onRestart: {}
        )
    }
    .environmentObject(LibraryStore())
}
