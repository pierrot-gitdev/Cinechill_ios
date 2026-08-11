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
    /// Un repère qui s'allume ou s'éteint — les destinations de la
    /// démonstration. Une valeur qui change, pas un objet qui se déplace.
    static let reveal = Animation.easeOut(duration: 0.22)

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

    /// Là où le film se range, en un mot — celui de la démonstration et celui de
    /// l'onglet d'arrivée. C'est cette égalité qui fait qu'on n'a le geste à
    /// apprendre qu'une fois.
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

    /// Ce que le toast annonce, au possessif : c'est la galerie *de
    /// l'utilisateur* que le film vient de rejoindre.
    ///
    /// `nil` pour le refus, et c'est le fond de l'affaire : un film écarté n'est
    /// rangé nulle part, il n'y a donc rien à accuser réception. Confirmer les
    /// trois gestes ferait du toast un commentaire du geste plutôt que de son
    /// résultat.
    var confirmation: String? {
        switch self {
        case .right: String(localized: "Ajouté à ta galerie", bundle: .app)
        case .up: String(localized: "Ajouté à ta watchlist", bundle: .app)
        case .left: nil
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

// MARK: - L'aide

/// Le point d'interrogation qui rouvre la planche des gestes, dans la même
/// écriture que les flèches : grille de 24, trait de 1,5, extrémités rondes.
///
/// L'anse est tracée et le point est plein — c'est ainsi qu'un « ? » se dessine.
/// `questionmark` du système n'aurait ni la même graisse ni les mêmes extrémités
/// que les trois flèches qu'il côtoie sur cet écran, et ça se voit à 17 pt.
struct SwipeHelpGlyph: View {
    var side: CGFloat = 17

    var body: some View {
        ZStack(alignment: .topLeading) {
            SwipeHelpHook()
                .stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                .frame(width: side, height: side)

            Circle()
                .frame(width: side / 24 * 2.1, height: side / 24 * 2.1)
                .offset(x: side / 24 * 10.95, y: side / 24 * 17.2)
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}

private struct SwipeHelpHook: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * scale, y: rect.minY + y * scale)
        }

        var path = Path()
        path.move(to: p(7.8, 9))
        path.addQuadCurve(to: p(16.2, 9), control: p(12, 3.4))
        path.addQuadCurve(to: p(12, 14.4), control: p(16.2, 12.4))
        path.addLine(to: p(12, 15.8))
        return path
    }
}
