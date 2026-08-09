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
        case .seen: String(localized: "VU", bundle: .app)
        case .notSeen: String(localized: "PAS VU", bundle: .app)
        case .watchlist: String(localized: "À VOIR", bundle: .app)
        }
    }

    /// Le verdict parle désormais la langue de la fiche film et des grilles :
    /// **plein = vu, creux = à voir, éteint = écarté**. L'écran employait un
    /// vert, un bleu et un gris pour ces trois mêmes états, soit un troisième
    /// vocabulaire de couleur pour la même information.
    var tint: Color {
        switch self {
        case .seen: Ink.light
        case .notSeen: Ink.ink3
        case .watchlist: Ink.light
        }
    }

    var isFilled: Bool {
        switch self {
        case .seen: true
        case .notSeen, .watchlist: false
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

    private let corner: CGFloat = Metrics.radius

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
                .strokeBorder(Ink.rule, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "\(card.title), \(card.displayYear), note \(card.voteAverageText) sur 10", bundle: .app))
        .accessibilityHint(String(localized: "Balayez à droite si vous l'avez vu, à gauche sinon, vers le haut pour l'ajouter à la watchlist", bundle: .app))
    }

    // MARK: - Habillage

    private var titleGradient: some View {
        LinearGradient(
            colors: [.clear, Ink.ground.opacity(0.45), Ink.ground.opacity(0.92)],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 190)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .allowsHitTesting(false)
    }

    private var infoFooter: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text(card.title)
                    .planTitle(25)
                    .foregroundStyle(Ink.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)

                Text(facts)
                    .planLabel()
                    .foregroundStyle(Ink.ink2)
            }

            Spacer(minLength: 0)

            if card.overview?.isEmpty == false {
                Text(isSynopsisOpen ? String(localized: "Fermer", bundle: .app) : String(localized: "Résumé", bundle: .app))
                    .planLabel()
                    .foregroundStyle(Ink.ink)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .overlay(
                        RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                            .strokeBorder(Ink.ink.opacity(0.4), lineWidth: 1)
                    )
            }
        }
        .padding(20)
        .opacity(isSynopsisOpen ? 0 : 1)
    }

    private var facts: String {
        var parts = [card.displayYear]
        if card.voteAverage != nil { parts.append(card.voteAverageText + " / 10") }
        return parts.joined(separator: " · ")
    }

    private var synopsisPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(card.title)
                .planTitle(19)
                .foregroundStyle(Ink.ink)
            Text(card.overview ?? "")
                .font(.system(size: 14))
                .foregroundStyle(Ink.ink2)
                .lineSpacing(3)
                .lineLimit(9)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .frame(height: 260)
        .background(Ink.ground.opacity(0.94))
        .overlay(alignment: .top) { PlanEdge(tint: Ink.ruleSet) }
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
            HStack(spacing: 9) {
                if verdict.isFilled {
                    PlanLight(tint: verdict.tint)
                } else {
                    PlanLightOutline(tint: verdict.tint)
                }
                Text(verdict.label)
                    .planLabel()
            }
            .foregroundStyle(verdict.tint)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Ink.ground.opacity(0.86),
                in: RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                    .strokeBorder(verdict.tint.opacity(0.6), lineWidth: 1)
            )
            .padding(20)
            .opacity(verdictIntensity)
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
