//
//  SwipeGestureHints.swift
//  Cinechill_iOS
//

import SwiftUI

/// La légende des gestes, sous le deck.
///
/// Volontairement discrète et éphémère : elle sert les premiers swipes puis
/// s'efface définitivement, une fois le geste acquis (voir `SwipeDeckView`).
struct SwipeGestureHints: View {
    var opacity: Double

    var body: some View {
        HStack(spacing: 12) {
            hint(symbol: "arrow.left", label: "Pas vu", symbolLeading: true)
            separator
            hint(symbol: "arrow.up", label: "À voir", symbolLeading: true)
            separator
            hint(symbol: "arrow.right", label: "Vu", symbolLeading: false)
        }
        .font(.system(size: 12, weight: .medium, design: .rounded))
        .foregroundStyle(.secondary)
        .opacity(opacity)
        .accessibilityHidden(true)
    }

    private var separator: some View {
        Circle()
            .fill(Color.secondary)
            .frame(width: 2.5, height: 2.5)
            .opacity(0.5)
    }

    private func hint(symbol: String, label: String, symbolLeading: Bool) -> some View {
        HStack(spacing: 5) {
            if symbolLeading {
                Image(systemName: symbol).imageScale(.small)
                Text(label)
            } else {
                Text(label)
                Image(systemName: symbol).imageScale(.small)
            }
        }
    }
}

/// Les trois directions rappelées sur les bords de la carte, à l'ouverture de
/// l'onglet.
///
/// La légende du bas dit quoi faire, ces repères disent *où* : chaque action
/// est posée du côté vers lequel il faut balayer, dans la couleur de son
/// verdict — la même que celle du tampon qui s'allume pendant le geste, pour
/// que l'association se fasse toute seule.
struct SwipeDirectionCues: View {
    var body: some View {
        ZStack {
            cue(for: .watchlist, arrow: "arrow.up", arrowLeading: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, 20)

            cue(for: .notSeen, arrow: "arrow.left", arrowLeading: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(.leading, 14)

            cue(for: .seen, arrow: "arrow.right", arrowLeading: false)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .padding(.trailing, 14)
        }
        .accessibilityHidden(true)
    }

    private func cue(for verdict: SwipeVerdict, arrow: String, arrowLeading: Bool) -> some View {
        HStack(spacing: 6) {
            if arrowLeading {
                Image(systemName: arrow).font(.system(size: 11, weight: .bold))
                Text(verdict.label)
            } else {
                Text(verdict.label)
                Image(systemName: arrow).font(.system(size: 11, weight: .bold))
            }
        }
        .font(.system(size: 12, weight: .heavy, design: .rounded))
        .kerning(0.4)
        .foregroundStyle(verdict.tint)
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(verdict.tint.opacity(0.45), lineWidth: 1))
        .shadow(color: .black.opacity(0.2), radius: 10, y: 3)
    }
}

/// La célébration d'un palier — le seul moment où la feature se met en avant.
struct SwipeMilestoneOverlay: View {
    let count: Int

    var body: some View {
        VStack(spacing: 14) {
            Text("\(count)")
                .font(.system(size: 64, weight: .heavy, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.indigo, .pink],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text("films ajoutés")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
            Text("Votre galerie s'étoffe, et vos suggestions avec elle.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 34)
        .padding(.vertical, 30)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 30, y: 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(count) films ajoutés à votre galerie")
    }
}

#Preview {
    VStack(spacing: 40) {
        SwipeDirectionCues()
            .frame(width: 300, height: 450)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 26))
        SwipeGestureHints(opacity: 0.38)
        SwipeMilestoneOverlay(count: 25)
    }
}
