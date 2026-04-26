//
//  ContentCardView.swift
//  Cinechill_iOS
//

import SwiftUI

struct ContentCardView: View {
    let item: MediaItem
    var inGallery: Bool = false
    var inWatchlist: Bool = false

    private let corner: CGFloat = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                poster
                    .frame(maxWidth: .infinity)
                    .aspectRatio(2 / 3, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                    .overlay(alignment: .bottomTrailing) {
                        ratingBadge
                            .padding(8)
                    }

                badgeStack
                    .padding(8)
            }

            Text(item.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)

            HStack {
                Text(item.mediaType.singularLabel)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(item.displayYear)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        "\(item.title), \(item.mediaType.singularLabel), note TMDB \(item.voteAverageText) sur 10, année \(item.displayYear)"
            + (inGallery ? ", dans la galerie" : "")
            + (inWatchlist ? ", dans la watchlist" : "")
    }

    @ViewBuilder
    private var poster: some View {
        if let url = item.posterURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    placeholder
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .opacity(1)
                case .failure:
                    placeholder
                @unknown default:
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            Rectangle().fill(Color(.secondarySystemBackground))
            Image(systemName: "film")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
        }
    }

    private var ratingBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "star.fill")
                .font(.caption2)
                .foregroundStyle(.yellow)
            Text("\(item.voteAverageText)/10")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.65), in: Capsule())
    }

    @ViewBuilder
    private var badgeStack: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if inGallery {
                badge(icon: "checkmark.circle.fill", label: "Galerie", color: .green)
            }
            if inWatchlist {
                badge(icon: "bookmark.fill", label: "Watchlist", color: .blue)
            }
        }
    }

    private func badge(icon: String, label: String, color: Color) -> some View {
        Label(label, systemImage: icon)
            .labelStyle(.iconOnly)
            .font(.body)
            .foregroundStyle(color)
            .padding(6)
            .background(.ultraThinMaterial, in: Circle())
            .accessibilityLabel(label)
    }
}

#Preview {
    let item = MediaItem(
        tmdbId: 1,
        mediaType: .movie,
        title: "Exemple",
        posterPath: nil,
        overview: nil,
        voteAverage: 7.4,
        genreIds: [],
        releaseDate: "2024-01-01"
    )
    ContentCardView(item: item, inGallery: true, inWatchlist: false)
        .padding()
}
