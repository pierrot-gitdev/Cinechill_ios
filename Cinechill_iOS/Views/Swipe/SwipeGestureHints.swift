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
        HStack(spacing: 14) {
            hint(.left, label: "Pas vu", glyphLeading: true)
            separator
            hint(.up, label: "À voir", glyphLeading: true)
            separator
            hint(.right, label: "Vu", glyphLeading: false)
        }
        .foregroundStyle(Ink.ink3)
        .opacity(opacity)
        .accessibilityHidden(true)
    }

    private var separator: some View {
        Rectangle()
            .fill(Ink.ruleSet)
            .frame(width: 1, height: 9)
    }

    private func hint(_ direction: SwipeArrow.Direction, label: String, glyphLeading: Bool) -> some View {
        HStack(spacing: 6) {
            if glyphLeading { arrow(direction) }
            Text(label).planLabel()
            if !glyphLeading { arrow(direction) }
        }
    }

    private func arrow(_ direction: SwipeArrow.Direction) -> some View {
        SwipeArrow(direction: direction)
            .stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            .frame(width: 11, height: 11)
    }
}

/// Les trois directions rappelées sur les bords de la carte, à l'ouverture de
/// l'onglet.
///
/// La légende du bas dit quoi faire, ces repères disent *où* : chaque action est
/// posée du côté vers lequel il faut balayer, avec le signe de son verdict — le
/// même que celui du tampon qui s'allume pendant le geste, pour que
/// l'association se fasse toute seule.
struct SwipeDirectionCues: View {
    var body: some View {
        ZStack {
            cue(for: .watchlist, direction: .up, glyphLeading: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, 20)

            cue(for: .notSeen, direction: .left, glyphLeading: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(.leading, 14)

            cue(for: .seen, direction: .right, glyphLeading: false)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .padding(.trailing, 14)
        }
        .accessibilityHidden(true)
    }

    private func cue(
        for verdict: SwipeVerdict, direction: SwipeArrow.Direction, glyphLeading: Bool
    ) -> some View {
        HStack(spacing: 7) {
            if glyphLeading { arrow(direction) }
            Text(verdict.label).planLabel()
            if !glyphLeading { arrow(direction) }
        }
        .foregroundStyle(verdict.tint)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Ink.ground.opacity(0.86),
            in: RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                .strokeBorder(verdict.tint.opacity(0.5), lineWidth: 1)
        )
    }

    private func arrow(_ direction: SwipeArrow.Direction) -> some View {
        SwipeArrow(direction: direction)
            .stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            .frame(width: 12, height: 12)
    }
}

/// La célébration d'un palier — le seul moment où la feature se met en avant.
///
/// Elle n'a plus de carte : un chiffre en graisse 200, une ligne, et le voile de
/// la nuit. Le dégradé indigo→rose sur un nombre de 64 pt était l'effet le plus
/// appuyé de l'application, et il ne disait rien que le chiffre ne disait déjà.
struct SwipeMilestoneOverlay: View {
    let count: Int

    var body: some View {
        VStack(spacing: 0) {
            Text("\(count)")
                .planTitle(64)
                .monospacedDigit()
                .foregroundStyle(Ink.ink)

            Text("films ajoutés")
                .planLabel()
                .foregroundStyle(Ink.light)
                .padding(.top, 10)

            Text("Votre galerie s'étoffe, et vos suggestions avec elle.")
                .font(.system(size: 13))
                .foregroundStyle(Ink.ink2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 16)
        }
        .padding(.horizontal, 34)
        .padding(.vertical, 32)
        .frame(maxWidth: 300)
        .background(
            Ink.ground.opacity(0.94),
            in: RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                .strokeBorder(Ink.ruleSet, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(count) films ajoutés à votre galerie")
    }
}

/// Les trois flèches du deck, dans l'écriture « La Gravure » : grille de 24,
/// trait de 1,5, extrémités rondes. Elles remplacent `arrow.left` / `arrow.up` /
/// `arrow.right`, derniers symboles système d'un écran par ailleurs entièrement
/// dessiné.
struct SwipeArrow: Shape {
    enum Direction { case left, up, right }

    let direction: Direction

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * scale, y: rect.minY + y * scale)
        }

        var path = Path()
        switch direction {
        case .left:
            path.move(to: p(20, 12))
            path.addLine(to: p(4, 12))
            path.move(to: p(10, 6))
            path.addLine(to: p(4, 12))
            path.addLine(to: p(10, 18))
        case .right:
            path.move(to: p(4, 12))
            path.addLine(to: p(20, 12))
            path.move(to: p(14, 6))
            path.addLine(to: p(20, 12))
            path.addLine(to: p(14, 18))
        case .up:
            path.move(to: p(12, 20))
            path.addLine(to: p(12, 4))
            path.move(to: p(6, 10))
            path.addLine(to: p(12, 4))
            path.addLine(to: p(18, 10))
        }
        return path
    }
}

#Preview {
    ZStack {
        Ink.ground.ignoresSafeArea()
        VStack(spacing: 40) {
            SwipeDirectionCues()
                .frame(width: 280, height: 420)
                .overlay(
                    RoundedRectangle(cornerRadius: Metrics.radius)
                        .strokeBorder(Ink.rule, lineWidth: 1)
                )
            SwipeGestureHints(opacity: 0.5)
            SwipeMilestoneOverlay(count: 25)
        }
    }
}
