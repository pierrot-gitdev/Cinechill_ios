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
            HStack(alignment: .top, spacing: 13) {
                PosterTile(
                    posterPath: pick.item.entry.posterPath,
                    title: pick.item.entry.title,
                    width: 64,
                    cornerRadius: 8
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text("CE SOIR")
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .kerning(1.4)
                        .foregroundStyle(.indigo)

                    Text(pick.item.entry.title)
                        .font(.system(size: 19, weight: .heavy, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)

                    Text(facts)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)

                    Text(pick.reason)
                        .font(.system(size: 11.5))
                        .italic()
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }

                Spacer(minLength: 0)
            }
            .padding(14)

            actions
        }
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }

    private var facts: String {
        [pick.item.runtimeText, platformName, ratingText]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private var ratingText: String? {
        guard let rating = pick.item.entry.voteAverage else { return nil }
        return "★ " + String(format: "%.1f", rating)
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button(action: onWatch) {
                Text("Je le regarde")
                    .font(.system(size: 12.5, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(.systemBackground))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.primary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(PressableScaleStyle(scale: 0.96))

            Button(action: onReject) {
                Text("Autre chose")
                    .font(.system(size: 12.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(PressableScaleStyle(scale: 0.94))

            if let trailer = pick.item.trailerURL {
                Button {
                    openURL(trailer)
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 38, height: 38)
                        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(PressableScaleStyle(scale: 0.94))
                .accessibilityLabel("Voir la bande-annonce")
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
    }
}
