//
//  TonightCardView.swift
//  Cinechill_iOS
//

import SwiftUI

/// La proposition du soir : un seul film, une seule raison, deux issues.
///
/// C'est la pièce qui empêche la watchlist de pourrir. Une liste ne demande
/// jamais rien ; cette carte, si — et « Je le regarde » la fait se vider.
struct TonightCardView: View {
    let pick: TonightPick
    let platformName: String?
    let onWatch: () -> Void
    let onReject: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 0) {
            PlanEdge(tint: Ink.ruleSet)

            HStack(alignment: .top, spacing: 14) {
                PosterTile(
                    posterPath: pick.item.entry.posterPath,
                    title: pick.item.entry.title,
                    width: 64
                )

                VStack(alignment: .leading, spacing: 5) {
                    // La lumière, pas l'indigo : c'est la seule proposition que
                    // l'app vous fasse d'elle-même, donc son accent.
                    HStack(spacing: 8) {
                        PlanLight()
                        Text("Ce soir")
                            .planLabel()
                            .foregroundStyle(Ink.light)
                    }

                    Text(pick.item.entry.title)
                        .planTitle(20)
                        .foregroundStyle(Ink.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .padding(.top, 3)

                    Text(facts)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Ink.ink2)

                    Text(pick.reason)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Ink.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 3)
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 16)

            actions

            PlanEdge()
        }
        .accessibilityElement(children: .contain)
    }

    private var facts: String {
        [pick.item.runtimeText, platformName, ratingText]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    /// La note perd son étoile, comme sur la fiche film : c'est la même donnée,
    /// elle ne peut pas s'écrire de deux façons dans la même application.
    private var ratingText: String? {
        guard let rating = pick.item.entry.voteAverage, rating > 0 else { return nil }
        return String(format: "%.1f", rating).replacingOccurrences(of: ".", with: ",") + " / 10"
    }

    private var actions: some View {
        HStack(spacing: Metrics.gutter) {
            PlanButton(title: "Je le regarde", height: Metrics.control, action: onWatch)

            PlanSecondaryButton(title: "Autre chose", height: Metrics.control, action: onReject)
                .frame(width: 118)

            if let trailer = pick.item.trailerURL {
                Button {
                    openURL(trailer)
                } label: {
                    TonightPlayGlyph()
                        .stroke(style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                        .foregroundStyle(Ink.ink)
                        .frame(width: 16, height: 16)
                        .frame(width: 44, height: Metrics.control)
                        .overlay(
                            RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                                .strokeBorder(Ink.ruleSet, lineWidth: 1)
                        )
                }
                .buttonStyle(PressableScaleStyle(scale: 0.94))
                .accessibilityLabel("Voir la bande-annonce")
            }
        }
        .padding(.bottom, 18)
    }
}

/// La pointe de lecture, ouverte — une flèche pleine serait un second élément
/// plein, ce que la famille d'icônes n'admet pas.
private struct TonightPlayGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
