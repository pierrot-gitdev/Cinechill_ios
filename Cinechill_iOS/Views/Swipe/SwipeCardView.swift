//
//  SwipeCardView.swift
//  Cinechill_iOS
//

import SwiftUI

/// Le verdict en cours de composition pendant un drag.
enum SwipeVerdict {
    case seen
    case notSeen
    case watchlist

    var label: String {
        switch self {
        case .seen: "VU"
        case .notSeen: "PAS VU"
        case .watchlist: "À VOIR"
        }
    }

    var icon: String {
        switch self {
        case .seen: "checkmark"
        case .notSeen: "xmark"
        case .watchlist: "bookmark.fill"
        }
    }

    var tint: Color {
        switch self {
        case .seen: .green
        case .notSeen: Color(.systemGray)
        case .watchlist: .blue
        }
    }

    var alignment: Alignment {
        switch self {
        // Le tampon apparaît du côté d'où vient la carte, comme dans tous les
        // decks de swipe : c'est le repère que les gens ont déjà.
        case .seen: .topLeading
        case .notSeen: .topTrailing
        case .watchlist: .bottom
        }
    }
}

struct SwipeCardView: View {
    let card: SwipeCard
    /// Verdict en cours et son intensité (0 au repos, 1 au seuil de validation).
    var verdict: SwipeVerdict?
    var verdictIntensity: Double = 0
    /// Le synopsis est ouvert — géré par le deck pour se refermer au swipe.
    var isSynopsisOpen = false
    var onTap: () -> Void = {}

    private let corner: CGFloat = 26

    var body: some View {
        ZStack(alignment: .bottom) {
            PosterImageView(url: card.posterURL)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

            titleGradient
            infoFooter

            if isSynopsisOpen {
                synopsisPanel
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .aspectRatio(2 / 3, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay(verdictBorder)
        .overlay(alignment: verdict?.alignment ?? .top) { verdictStamp }
        .overlay(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.22), radius: 22, y: 12)
        .contentShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(card.title), \(card.displayYear), note \(card.voteAverageText) sur 10")
        .accessibilityHint("Balayez à droite si vous l'avez vu, à gauche sinon, vers le haut pour l'ajouter à la watchlist")
    }

    // MARK: - Habillage

    private var titleGradient: some View {
        LinearGradient(
            colors: [.clear, .black.opacity(0.35), .black.opacity(0.82)],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 190)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .allowsHitTesting(false)
    }

    private var infoFooter: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(card.title)
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)

                HStack(spacing: 8) {
                    Text(card.displayYear)
                    if card.voteAverage != nil {
                        Text("·")
                        Label(card.voteAverageText, systemImage: "star.fill")
                            .labelStyle(.titleAndIcon)
                            .imageScale(.small)
                    }
                }
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.82))
            }

            Spacer(minLength: 0)

            if card.overview?.isEmpty == false {
                Image(systemName: isSynopsisOpen ? "chevron.down" : "info")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(.white.opacity(0.16), in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.22), lineWidth: 1))
            }
        }
        .padding(20)
        .opacity(isSynopsisOpen ? 0 : 1)
    }

    private var synopsisPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(card.title)
                .font(.system(size: 19, weight: .bold, design: .rounded))
            Text(card.overview ?? "")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(9)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .frame(height: 260)
        .background(.ultraThinMaterial)
    }

    // MARK: - Verdict

    @ViewBuilder
    private var verdictBorder: some View {
        if let verdict {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(verdict.tint, lineWidth: 3)
                .opacity(verdictIntensity)
        }
    }

    @ViewBuilder
    private var verdictStamp: some View {
        if let verdict {
            HStack(spacing: 7) {
                Image(systemName: verdict.icon)
                    .font(.system(size: 13, weight: .heavy))
                Text(verdict.label)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .kerning(0.5)
            }
            .foregroundStyle(verdict.tint)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(verdict.tint.opacity(0.55), lineWidth: 1.5))
            .padding(22)
            .opacity(verdictIntensity)
            .scaleEffect(0.85 + 0.15 * verdictIntensity)
            .allowsHitTesting(false)
        }
    }
}

#Preview {
    SwipeCardView(
        card: SwipeCard(
            tmdbId: 157336,
            title: "Interstellar",
            posterPath: nil,
            overview: "Dans un futur proche, la Terre se meurt.",
            voteAverage: 8.4,
            voteCount: 34000,
            genreIds: [12, 18, 878],
            releaseDate: "2014-11-05",
            source: "pillars"
        ),
        verdict: .seen,
        verdictIntensity: 0.8
    )
    .padding(24)
}
