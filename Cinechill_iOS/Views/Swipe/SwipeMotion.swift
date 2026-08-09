//
//  SwipeMotion.swift
//  Cinechill_iOS
//

import Foundation
import SwiftUI

// MARK: - Les courbes

/// Le vocabulaire de mouvement de « Découvrir ».
///
/// Un deck ne se juge pas sur ses images fixes : ce qu'on en retient, c'est la
/// façon dont la carte suit le doigt, résiste au seuil, part, et laisse la
/// suivante arriver. Ces courbes sont ce vocabulaire — nommées par ce qu'elles
/// font, pour qu'aucun `response:` ne soit plus écrit à la main dans l'écran, et
/// que deux mouvements de même nature aient partout le même poids.
enum SwipeMotion {
    /// Le rappel au centre, geste abandonné. Il dépasse légèrement : c'est ce
    /// dépassement qui dit que la carte est tenue par un ressort et non posée.
    static let recenter = Animation.spring(response: 0.36, dampingFraction: 0.62)
    /// La pile qui remonte d'un cran. Amortie plus franchement que le rappel :
    /// le fond de l'écran ne doit pas osciller derrière la carte suivante.
    static let advance = Animation.spring(response: 0.34, dampingFraction: 0.78)
    /// Le verdict qui s'enclenche au seuil. Très court, peu amorti : on le sent
    /// plus qu'on ne le voit.
    static let lock = Animation.spring(response: 0.2, dampingFraction: 0.5)
    /// Le vol de la carte tranchée. Elle part vite et décélère — l'inertie du
    /// lâcher, pas une transition d'écran.
    static let flight = Animation.easeOut(duration: 0.3)
    /// Le dépliage de la plaque sur le synopsis. Le seul mouvement de mise en
    /// page de la carte, et il ne rebondit pas.
    static let unfold = Animation.spring(response: 0.34, dampingFraction: 0.88)
    /// Le sillage, une fois la carte partie.
    static let wake = Animation.easeOut(duration: 0.2)

    // MARK: Physique du geste

    /// Le déplacement, une fois le seuil franchi.
    ///
    /// Au-delà du seuil le doigt continue mais la carte résiste, en s'approchant
    /// d'une limite sans jamais l'atteindre. C'est ce qui donne du poids au
    /// geste, et surtout ce qui fait **sentir** le seuil : la main comprend
    /// qu'elle en a assez fait sans qu'on ait à l'écrire nulle part.
    static func resisted(_ value: CGFloat, threshold: CGFloat) -> CGFloat {
        let magnitude = abs(value)
        guard magnitude > threshold else { return value }
        let excess = Double(magnitude - threshold)
        // Course résiduelle maximale au-delà du seuil.
        let slack = 84.0
        let compressed = CGFloat(slack * (1 - exp(-excess / slack)))
        return (value < 0 ? -1 : 1) * (threshold + compressed)
    }

    /// L'angle de la carte pendant le geste, et son point d'appui.
    ///
    /// La carte pivote autour du bord **opposé** au doigt : prise par le haut
    /// elle bascule, prise par le bas elle se redresse. C'est le point d'appui,
    /// et non un angle constant, qui fait qu'une carte a du poids — un deck qui
    /// s'incline toujours dans le même sens se lit comme une image qui glisse.
    static func pivot(for translation: CGSize, grabbedHigh: Bool) -> (angle: Double, anchor: UnitPoint) {
        let angle = Double(translation.width) / 22 * (grabbedHigh ? 1 : -1)
        return (angle, UnitPoint(x: 0.5, y: grabbedHigh ? 1 : 0))
    }

    /// Le décalage de l'affiche sous la plaque pendant le geste.
    ///
    /// L'affiche traîne de quelques points derrière son cadre : la carte prend
    /// une épaisseur qu'un simple aplat n'a pas. Borné, sinon le cadre se vide
    /// par un bord.
    static func parallax(for translation: CGSize) -> CGSize {
        CGSize(
            width: min(9, max(-9, -translation.width * 0.05)),
            height: min(9, max(-9, -translation.height * 0.05))
        )
    }
}

// MARK: - Ce que dit une direction

extension SwipeDirection {
    var verdict: SwipeVerdict {
        switch self {
        case .right: .seen
        case .left: .notSeen
        case .up: .watchlist
        }
    }

    /// Là où le film se range. Le même mot dans la démonstration, dans le
    /// sillage d'un swipe et dans l'onglet d'arrivée : c'est cette égalité qui
    /// fait qu'on n'a le geste à apprendre qu'une fois.
    var destination: String {
        switch self {
        case .right: String(localized: "Galerie", bundle: .app)
        case .left: String(localized: "Jamais vu", bundle: .app)
        case .up: String(localized: "Watchlist", bundle: .app)
        }
    }

    /// Le refus est le seul repère qui reste en ardoise : ce qui n'est pas vu ne
    /// se range nulle part, et la valeur le dit avant le mot.
    var destinationTint: Color {
        switch self {
        case .right, .up: Ink.ink
        case .left: Ink.ink3
        }
    }

    var arrow: SwipeArrow.Direction {
        switch self {
        case .right: .right
        case .left: .left
        case .up: .up
        }
    }
}

// MARK: - Le sillage

/// Ce qui reste d'un geste une demi-seconde après qu'il a été fait.
///
/// La carte est partie ; au bord par lequel elle est sortie, un filet se tire
/// vers l'extérieur et la destination se lit une fois avant de s'éteindre. C'est
/// la seule chose qui ferme le geste : sans elle, un swipe se termine sur un
/// vide, et rien ne dit où le film vient d'aller.
///
/// Deux règles la tiennent discrète : **rien ne s'ajoute au vocabulaire** — le
/// filet et le libellé de service sont ceux de tout l'écran — et **elle ne
/// dure pas** ; à la seconde carte elle est déjà oubliée, ce qui est exactement
/// ce qu'on demande à un accusé de réception.
struct SwipeWake: View {
    let direction: SwipeDirection
    /// Le sillage connaît sa propre durée : c'est lui qui dit au deck quand le
    /// retirer, comme la carte en vol le fait déjà.
    var onFinished: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var draw: CGFloat = 0
    @State private var travel: CGFloat = 0
    @State private var opacity: Double = 1

    /// Longueur du filet, et distance dont le repère s'éloigne en s'éteignant.
    private static let ruleLength: CGFloat = 26
    private static let departure: CGFloat = 14

    var body: some View {
        mark
            .foregroundStyle(direction.destinationTint)
            .opacity(opacity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .task { await play() }
    }

    @ViewBuilder
    private var mark: some View {
        switch direction {
        case .right:
            lateral(alignment: .trailing, sign: 1)
        case .left:
            lateral(alignment: .leading, sign: -1)
        case .up:
            vertical
        }
    }

    /// Les deux sorties latérales : le libellé au bord, le filet qui prolonge le
    /// geste vers l'extérieur du cadre.
    private func lateral(alignment: Alignment, sign: CGFloat) -> some View {
        HStack(spacing: 9) {
            if sign < 0 { rule(horizontal: true, anchor: .trailing) }
            Text(direction.destination)
                .planLabel()
                .fixedSize()
            if sign > 0 { rule(horizontal: true, anchor: .leading) }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
        .offset(x: sign * travel)
    }

    /// La watchlist sort par le haut : le filet monte, le libellé le suit.
    private var vertical: some View {
        VStack(spacing: 9) {
            rule(horizontal: false, anchor: .bottom)
            Text(direction.destination)
                .planLabel()
                .fixedSize()
        }
        // De quoi s'éloigner sans monter dans le bandeau de séance : les deux
        // sorties latérales, elles, peuvent franchir le bord — c'est ce qu'on
        // leur demande.
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .offset(y: -travel)
    }

    private func rule(horizontal: Bool, anchor: UnitPoint) -> some View {
        Rectangle()
            .fill(direction.destinationTint)
            .frame(
                width: horizontal ? Self.ruleLength : 1,
                height: horizontal ? 1 : Self.ruleLength
            )
            .scaleEffect(
                x: horizontal ? draw : 1,
                y: horizontal ? 1 : draw,
                anchor: anchor
            )
    }

    private func play() async {
        guard !reduceMotion else {
            draw = 1
            withAnimation(.easeIn(duration: 0.32)) { opacity = 0 }
            try? await Task.sleep(for: .milliseconds(360))
            guard !Task.isCancelled else { return }
            onFinished()
            return
        }

        withAnimation(SwipeMotion.wake) {
            draw = 1
            travel = Self.departure
        }
        withAnimation(.easeIn(duration: 0.26).delay(0.16)) { opacity = 0 }

        try? await Task.sleep(for: .milliseconds(460))
        guard !Task.isCancelled else { return }
        onFinished()
    }
}

// MARK: - La flèche

/// Les flèches du deck, dans l'écriture « La Gravure » : grille de 24, trait de
/// 1,5, extrémités rondes. Elles remplacent `arrow.left` / `arrow.up` /
/// `chevron.down`, derniers symboles système d'un écran par ailleurs
/// entièrement dessiné.
struct SwipeArrow: Shape {
    enum Direction { case left, up, right, down }

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
        case .down:
            path.move(to: p(12, 4))
            path.addLine(to: p(12, 20))
            path.move(to: p(6, 14))
            path.addLine(to: p(12, 20))
            path.addLine(to: p(18, 14))
        }
        return path
    }
}

/// La flèche à la taille du niveau de service — celle qui accompagne un libellé
/// en capitales.
struct SwipeArrowGlyph: View {
    let direction: SwipeArrow.Direction
    var side: CGFloat = 12

    var body: some View {
        SwipeArrow(direction: direction)
            .stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            .frame(width: side, height: side)
    }
}

#Preview("Le sillage") {
    ZStack {
        Ink.ground.ignoresSafeArea()
        VStack(spacing: 34) {
            ForEach([SwipeDirection.right, .left, .up], id: \.destination) { direction in
                SwipeWake(direction: direction)
                    .frame(height: 88)
                    .overlay(alignment: .bottom) { PlanEdge() }
            }
        }
        .padding(Metrics.margin)
    }
}
