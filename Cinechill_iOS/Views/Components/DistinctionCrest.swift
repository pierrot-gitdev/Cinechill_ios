//
//  DistinctionCrest.swift
//  Cinechill_iOS
//

import SwiftUI

// MARK: - Le repère

/// La géométrie de l'écu, posée une fois dans un carré de 220 et rapportée
/// ensuite à la taille demandée. Tout le dessin y renvoie, si bien qu'aucune
/// pièce ne peut dériver par rapport aux autres.
private enum Wreath {
    static let box: CGFloat = 220
    static let center = CGPoint(x: 110, y: 106)
    static let radius: CGFloat = 74

    static let leafLength: CGFloat = 17
    static let leafWidth: CGFloat = 5.2
    /// Les feuilles poussent juste en dehors de la tige, comme sur une vraie
    /// branche. Ancrées dessus, elles couvraient le ruban au lieu d'en sortir.
    static let leafAnchorOffset: CGFloat = 2.5

    /// Le badge et l'emblème font désormais la même taille à quatre unités
    /// près. Le siège occupait 76 unités contre 46 à l'emblème : la couronne
    /// semblait décerner une distinction à un badge, au lieu de présenter les
    /// deux ensemble. Le bas du siège s'arrête où commence l'emblème.
    static let seatDiameter: CGFloat = 64
    static let emblemBox: CGFloat = 60
    static let emblemCenter = CGPoint(x: 110, y: 172)

    /// Les deux branches vont du pied vers la tête, et laissent quarante degrés
    /// d'ouverture au sommet. Une couronne fermée dirait que c'est fini.
    ///
    /// L'ouverture du pied est passée de quarante à soixante degrés pour loger
    /// l'emblème agrandi : les pointes des deux branches l'encadrent désormais
    /// au lieu de le serrer.
    static let leftStart: Double = 240
    static let leftEnd: Double = 110
    static let rightStart: Double = -60
    static let rightEnd: Double = 70

    /// Un point de l'arc, éventuellement décalé radialement : `offset` sert à
    /// épaissir les tiges vers l'extérieur ou l'intérieur.
    static func point(_ degrees: Double, offset: CGFloat = 0) -> CGPoint {
        let a = degrees * .pi / 180
        let r = radius + offset
        return CGPoint(
            x: center.x + r * cos(a),
            y: center.y - r * sin(a)
        )
    }

    /// L'angle de la i-ème feuille d'une branche, du pied vers la tête.
    static func leafAngle(index: Int, onLeft: Bool) -> Double {
        let fraction = Double(index) / Double(Distinction.leavesPerBranch - 1)
        return onLeft
            ? leftStart - fraction * (leftStart - leftEnd)
            : rightStart + fraction * (rightEnd - rightStart)
    }

    /// L'inclinaison d'une feuille : la direction de pousse le long de la
    /// branche, penchée vers l'extérieur pour que la couronne s'ouvre au lieu
    /// de se replier sur le badge.
    static func leafRotation(degrees: Double, onLeft: Bool) -> CGFloat {
        let a = degrees * .pi / 180
        let growth = onLeft
            ? CGPoint(x: sin(a), y: cos(a))
            : CGPoint(x: -sin(a), y: -cos(a))
        let outward = CGPoint(x: cos(a), y: -sin(a))
        return atan2(growth.y + 0.78 * outward.y, growth.x + 0.78 * outward.x)
    }

    /// La direction de la branche en un point, sans l'inclinaison vers
    /// l'extérieur qui, elle, ne concerne que les feuilles.
    static func tangent(degrees: Double, onLeft: Bool) -> CGFloat {
        let a = degrees * .pi / 180
        return onLeft
            ? atan2(cos(a), sin(a))
            : atan2(-cos(a), -sin(a))
    }

    /// Ramène le dessin de référence au rectangle réellement offert, centré et
    /// sans déformation.
    static func fit(_ rect: CGRect, reference: CGFloat = box) -> CGAffineTransform {
        let scale = min(rect.width, rect.height) / reference
        let side = reference * scale
        return CGAffineTransform(
            translationX: rect.minX + (rect.width - side) / 2,
            y: rect.minY + (rect.height - side) / 2
        ).scaledBy(x: scale, y: scale)
    }
}

// MARK: - Les feuilles

/// La couronne entière : les tiges, et les feuilles acquises ou restant à
/// gagner.
///
/// Deux passes séparées parce qu'une `Shape` n'a qu'un seul remplissage : les
/// feuilles acquises et les tiges sont pleines, celles qui restent à gagner sont
/// tracées au filet. C'est le remplissage, et non la teinte, qui porte la
/// différence entre acquis et à gagner — la règle de toute l'application.
struct LaurelLeaves: Shape {
    /// Feuilles acquises **par branche**.
    let acquired: Int
    /// `true` pour les feuilles déjà posées, `false` pour celles qui restent.
    let showsAcquired: Bool
    /// Ajoute les deux tiges au chemin. Elles voyagent avec les feuilles
    /// acquises, dont on sait qu'elles arrivent à l'écran.
    var includesStems: Bool = false

    /// Demi-épaisseur d'une tige au pied et à la tête, en unités du repère.
    private static let footHalfWidth: CGFloat = 1.3
    private static let headHalfWidth: CGFloat = 0.55

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let leaf = leafPath()

        if includesStems { addStems(to: &path) }

        for onLeft in [true, false] {
            for index in 0..<Distinction.leavesPerBranch {
                guard (index < acquired) == showsAcquired else { continue }
                let degrees = Wreath.leafAngle(index: index, onLeft: onLeft)
                let anchor = Wreath.point(degrees, offset: Wreath.leafAnchorOffset)
                let placement = CGAffineTransform(translationX: anchor.x, y: anchor.y)
                    .rotated(by: Wreath.leafRotation(degrees: degrees, onLeft: onLeft))
                path.addPath(leaf, transform: placement)
            }
        }
        return path.applying(Wreath.fit(rect))
    }

    /// Les deux branches nues, posées segment par segment.
    ///
    /// Elles ont d'abord vécu dans une `Shape` à part, `LaurelStems`, qui ne
    /// s'affichait pas sur l'appareil : ni en chemin ouvert tracé, ni en surface
    /// fermée remplie, ni une fois rapatriée dans ce type-ci. Trois échecs
    /// identiques pour trois géométries différentes innocentent le dessin.
    ///
    /// Ce qu'il restait de non partagé avec les feuilles, c'était la manière de
    /// remplir le chemin. Les feuilles passent par `addPath(_:transform:)` à
    /// partir d'un motif local, et elles arrivent à l'écran. Les tiges font
    /// désormais exactement pareil : un petit quadrilatère, répété le long de
    /// l'arc en se chevauchant, incliné sur la tangente. Aucun mécanisme neuf.
    private func addStems(to path: inout Path) {
        let steps = 44
        let span = Wreath.leftStart - Wreath.leftEnd
        // Un segment est plus long que le pas, pour que deux voisins se
        // recouvrent et que le ruban n'ait pas de dents.
        let pitch = Wreath.radius * (span / Double(steps)) * .pi / 180
        let segment = CGFloat(pitch) * 1.7

        for onLeft in [true, false] {
            let from = onLeft ? Wreath.leftStart : Wreath.rightStart
            let to = onLeft ? Wreath.leftEnd : Wreath.rightEnd

            for step in 0...steps {
                let fraction = Double(step) / Double(steps)
                let degrees = from + (to - from) * fraction
                let half = Self.footHalfWidth
                    + (Self.headHalfWidth - Self.footHalfWidth) * CGFloat(fraction)

                var brick = Path()
                brick.addRect(CGRect(
                    x: -segment / 2, y: -half,
                    width: segment, height: half * 2
                ))

                let anchor = Wreath.point(degrees)
                let placement = CGAffineTransform(translationX: anchor.x, y: anchor.y)
                    .rotated(by: Wreath.tangent(degrees: degrees, onLeft: onLeft))
                path.addPath(brick, transform: placement)
            }
        }
    }

    /// Une feuille pointant vers les x positifs, reprise telle quelle à chaque
    /// emplacement : deux quadratiques opposées, donc une amande.
    private func leafPath() -> Path {
        var leaf = Path()
        let length = Wreath.leafLength
        let width = Wreath.leafWidth
        leaf.move(to: .zero)
        leaf.addQuadCurve(
            to: CGPoint(x: length, y: 0),
            control: CGPoint(x: length * 0.46, y: -width)
        )
        leaf.addQuadCurve(
            to: .zero,
            control: CGPoint(x: length * 0.46, y: width)
        )
        return leaf
    }
}

// MARK: - Les cinq emblèmes

/// L'objet frappé au pied de la couronne, dans l'espace du nœud qui attache les
/// deux branches.
///
/// Gravés au trait, jamais remplis : ils se lisent à seize points comme à
/// quatre-vingt-seize, parce qu'aucun ne repose sur un détail plus fin qu'un
/// point. Ce sont des dessins originaux et non des reproductions : les
/// statuettes des grandes récompenses sont protégées, leurs noms seuls sont
/// employés.
struct DistinctionEmblem: Shape {
    let distinction: Distinction

    /// Les emblèmes sont dessinés dans un carré de 100, comme la famille
    /// d'icônes de l'application.
    private static let reference: CGFloat = 100

    func path(in rect: CGRect) -> Path {
        var path = Path()
        switch distinction {
        case .mention: drawRibbon(&path)
        case .interpretation: drawMask(&path)
        case .cesar: drawCompression(&path)
        case .palme: drawPalm(&path)
        case .oscar: drawStatuette(&path)
        }
        return path.applying(Wreath.fit(rect, reference: Self.reference))
    }

    /// La cocarde et ses deux pans. Un ruban se porte un soir, puis se range :
    /// c'est le degré où l'on est remarqué sans être récompensé.
    private func drawRibbon(_ path: inout Path) {
        path.addEllipse(in: CGRect(x: 36, y: 20, width: 28, height: 28))
        path.addEllipse(in: CGRect(x: 44, y: 28, width: 12, height: 12))

        path.move(to: CGPoint(x: 41, y: 46))
        path.addLine(to: CGPoint(x: 34, y: 78))
        path.addLine(to: CGPoint(x: 45, y: 71))
        path.addLine(to: CGPoint(x: 50, y: 80))

        path.move(to: CGPoint(x: 59, y: 46))
        path.addLine(to: CGPoint(x: 66, y: 78))
        path.addLine(to: CGPoint(x: 55, y: 71))
        path.addLine(to: CGPoint(x: 50, y: 80))
    }

    /// Le masque de scène : le prix d'interprétation récompense un visage
    /// emprunté, pas un film. Contour, deux yeux, une bouche — rien de plus, ou
    /// il cesse d'être lisible une fois réduit.
    private func drawMask(_ path: inout Path) {
        path.move(to: CGPoint(x: 50, y: 14))
        path.addCurve(
            to: CGPoint(x: 22, y: 45),
            control1: CGPoint(x: 30, y: 14), control2: CGPoint(x: 21, y: 29)
        )
        path.addCurve(
            to: CGPoint(x: 50, y: 87),
            control1: CGPoint(x: 23, y: 64), control2: CGPoint(x: 35, y: 82)
        )
        path.addCurve(
            to: CGPoint(x: 78, y: 45),
            control1: CGPoint(x: 65, y: 82), control2: CGPoint(x: 77, y: 64)
        )
        path.addCurve(
            to: CGPoint(x: 50, y: 14),
            control1: CGPoint(x: 79, y: 29), control2: CGPoint(x: 70, y: 14)
        )
        path.closeSubpath()

        path.addEllipse(in: CGRect(x: 31, y: 39, width: 15, height: 9))
        path.addEllipse(in: CGRect(x: 54, y: 39, width: 15, height: 9))

        path.move(to: CGPoint(x: 38, y: 65))
        path.addCurve(
            to: CGPoint(x: 62, y: 65),
            control1: CGPoint(x: 44, y: 73), control2: CGPoint(x: 56, y: 73)
        )
    }

    /// La compression : une masse aux plis irréguliers sur son socle. Les plis
    /// ondulent au lieu d'être parallèles, sans quoi le bloc se lirait comme une
    /// pile de briques.
    private func drawCompression(_ path: inout Path) {
        path.move(to: CGPoint(x: 33, y: 20))
        path.addLine(to: CGPoint(x: 66, y: 15))
        path.addLine(to: CGPoint(x: 70, y: 72))
        path.addLine(to: CGPoint(x: 30, y: 76))
        path.closeSubpath()

        path.move(to: CGPoint(x: 31.5, y: 34))
        path.addCurve(
            to: CGPoint(x: 67.5, y: 30),
            control1: CGPoint(x: 43, y: 37), control2: CGPoint(x: 55, y: 27)
        )
        path.move(to: CGPoint(x: 32, y: 48))
        path.addCurve(
            to: CGPoint(x: 68.5, y: 45),
            control1: CGPoint(x: 45, y: 44), control2: CGPoint(x: 56, y: 51)
        )
        path.move(to: CGPoint(x: 30.7, y: 62))
        path.addCurve(
            to: CGPoint(x: 69.3, y: 59),
            control1: CGPoint(x: 43, y: 65), control2: CGPoint(x: 57, y: 55)
        )

        path.addRect(CGRect(x: 26, y: 76, width: 48, height: 9))
    }

    /// La palme : une nervure centrale et ses folioles, plus longues au milieu
    /// qu'aux deux bouts. Elles sont calculées plutôt que tracées une à une,
    /// pour que leur progression soit régulière — c'est la même logique que les
    /// feuilles de la couronne, à l'échelle d'un seul objet.
    private func drawPalm(_ path: inout Path) {
        path.move(to: CGPoint(x: 50, y: 88))
        path.addCurve(
            to: CGPoint(x: 50, y: 12),
            control1: CGPoint(x: 47, y: 62), control2: CGPoint(x: 48, y: 32)
        )

        let count = 11
        for index in 0..<count {
            let t = Double(index) / Double(count - 1)
            let y = 82 - t * 62
            let length = 27 * sin(.pi * (0.14 + 0.74 * t))
            for side in [-1.0, 1.0] {
                path.move(to: CGPoint(x: 50 + side * 1.5, y: y))
                path.addQuadCurve(
                    to: CGPoint(x: 50 + side * length, y: y - length * 0.62),
                    control: CGPoint(x: 50 + side * length * 0.55, y: y - length * 0.06)
                )
            }
        }
    }

    /// La statuette : une silhouette debout, son glaive tenu devant elle, sur un
    /// socle à deux degrés. Elle ne se porte plus et ne se range plus : elle se
    /// pose, et se montre à qui entre.
    private func drawStatuette(_ path: inout Path) {
        path.addEllipse(in: CGRect(x: 44, y: 12, width: 12, height: 13))

        path.move(to: CGPoint(x: 40, y: 35))
        path.addCurve(
            to: CGPoint(x: 42, y: 64),
            control1: CGPoint(x: 39, y: 47), control2: CGPoint(x: 40, y: 57)
        )
        path.addLine(to: CGPoint(x: 58, y: 64))
        path.addCurve(
            to: CGPoint(x: 60, y: 35),
            control1: CGPoint(x: 60, y: 57), control2: CGPoint(x: 61, y: 47)
        )
        path.addCurve(
            to: CGPoint(x: 40, y: 35),
            control1: CGPoint(x: 59, y: 28), control2: CGPoint(x: 41, y: 28)
        )
        path.closeSubpath()

        path.move(to: CGPoint(x: 50, y: 33))
        path.addLine(to: CGPoint(x: 50, y: 64))

        path.addRect(CGRect(x: 41, y: 64, width: 18, height: 11))
        path.addRect(CGRect(x: 35, y: 75, width: 30, height: 9))
    }
}

// MARK: - L'écu

/// La distinction et le badge choisi, en une seule pièce.
///
/// Le badge reste au centre, intact, avec sa couleur et son illustration. La
/// distinction ne lui dispute rien : **elle le couronne**. Aucun recouvrement
/// n'est possible, puisque l'un est une image pleine et l'autre du trait sur le
/// pourtour. C'est là toute la complémentarité, et elle est littérale.
struct DistinctionCrest: View {
    let distinction: Distinction
    let galleryCount: Int
    let badge: Badge?
    var size: CGFloat = 200

    /// Le PNG d'un badge garde une marge transparente autour de sa monture,
    /// pour laisser respirer son ombre portée. Ce zoom rogne cette marge, pour
    /// que le badge remplisse son siège et non sa marge.
    ///
    /// La valeur est mesurée, pas choisie : sur les quinze planches, la monture
    /// occupe entre 69 % et 75 % du carré, et c'est la plus large qui commande.
    /// Au-delà de 1,33 le rognage mord sur la monture elle-même — l'ancien 1,55,
    /// hérité du puits carré, amputait les quinze badges d'un bon dixième.
    private static let badgeZoom: CGFloat = 1.33

    private var acquired: Int { distinction.acquiredLeaves(count: galleryCount) }
    private var seatSize: CGFloat { size * Wreath.seatDiameter / Wreath.box }
    private var emblemSize: CGFloat { size * Wreath.emblemBox / Wreath.box }

    var body: some View {
        ZStack {
            // Les feuilles à gagner sont plus appuyées qu'elles ne le paraissent
            // sur la planche de référence, et c'est délibéré : celle-ci présente
            // le dessin à 300 px sur un grand écran, l'app le tient dans 200
            // points sur un téléphone, et un filet proportionnellement identique
            // s'y évanouit.
            LaurelLeaves(acquired: acquired, showsAcquired: false)
                .stroke(distinction.accent.opacity(0.32), lineWidth: 0.85)
                .frame(width: size, height: size)

            // Les tiges voyagent avec les feuilles acquises : ta capture prouve
            // que cette passe-ci arrive à l'écran.
            LaurelLeaves(acquired: acquired, showsAcquired: true, includesStems: true)
                .fill(distinction.accent)
                .frame(width: size, height: size)

            DistinctionEmblem(distinction: distinction)
                .stroke(
                    distinction.accent,
                    style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)
                )
                .frame(width: emblemSize, height: emblemSize)
                .offset(y: size * (Wreath.emblemCenter.y - Wreath.box / 2) / Wreath.box)

            badgeSeat
                .offset(y: size * (Wreath.center.y - Wreath.box / 2) / Wreath.box)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    /// Un creux, pas un objet : le badge y est posé, et rien autour de lui n'a
    /// de matière propre.
    private var badgeSeat: some View {
        ZStack {
            Circle()
                .fill(Color(hex: 0x101720))
                .overlay(Circle().strokeBorder(Ink.rule, lineWidth: 1))

            if let badge {
                Image(badge.imageName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: seatSize * Self.badgeZoom, height: seatSize * Self.badgeZoom)
            } else {
                CinechillHallIconView(.salle)
                    .frame(width: seatSize * 0.3, height: seatSize * 0.3)
                    .foregroundStyle(Ink.ink3)
            }
        }
        // Le cadrage doit précéder le rognage, et non l'inverse. Posé après, il
        // ne rogne rien : la pile prenait la taille de l'image zoomée, le
        // disque de fond avec elle, et le badge sortait à 155 % de son siège en
        // recouvrant le haut de l'emblème. C'est la faute qui rendait le badge
        // énorme malgré le rééquilibrage.
        .frame(width: seatSize, height: seatSize)
        .clipShape(Circle())
    }

    private var accessibilityText: String {
        let base = String(localized: "\(distinction.label), \(galleryCount) films", bundle: .app)
        guard let badge else { return base }
        return String(localized: "\(base). Badge en vitrine : \(badge.name)", bundle: .app)
    }
}

#Preview("Les cinq degrés") {
    ZStack {
        Ink.ground.ignoresSafeArea()
        ScrollView {
            VStack(spacing: 26) {
                ForEach(Distinction.allCases, id: \.rawValue) { distinction in
                    VStack(spacing: 10) {
                        DistinctionCrest(
                            distinction: distinction,
                            galleryCount: distinction.lowerBound + 30,
                            badge: BadgeCatalog.all.first,
                            size: 200
                        )
                        Text(distinction.label)
                            .planLabel()
                            .foregroundStyle(distinction.accent)
                    }
                }
            }
            .padding(.vertical, 30)
        }
    }
}
