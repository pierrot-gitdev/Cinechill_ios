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
    static let center = CGPoint(x: 110, y: 112)
    static let radius: CGFloat = 74

    static let leafLength: CGFloat = 17
    static let leafWidth: CGFloat = 5.2

    /// Le siège du badge, au centre. Son bas s'arrête juste où commence
    /// l'emblème : les deux se touchent sans jamais se recouvrir.
    static let seatDiameter: CGFloat = 76
    static let emblemBox: CGFloat = 46
    static let emblemCenter = CGPoint(x: 110, y: 174)

    /// Les deux branches vont du pied vers la tête, et laissent quarante degrés
    /// d'ouverture au sommet. Une couronne fermée dirait que c'est fini.
    static let leftStart: Double = 250
    static let leftEnd: Double = 110
    static let rightStart: Double = -70
    static let rightEnd: Double = 70

    static func point(_ degrees: Double) -> CGPoint {
        let a = degrees * .pi / 180
        return CGPoint(
            x: center.x + radius * cos(a),
            y: center.y - radius * sin(a)
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

// MARK: - Les tiges

/// Les deux branches nues, sans leurs feuilles.
///
/// Tracées par échantillonnage plutôt qu'avec un arc : le sens de rotation d'un
/// `addArc` dépend de l'orientation de l'axe vertical, et une polyligne de
/// vingt-quatre points ne laisse aucune place au doute pour un coût nul.
struct LaurelStems: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for onLeft in [true, false] {
            let from = onLeft ? Wreath.leftStart : Wreath.rightStart
            let to = onLeft ? Wreath.leftEnd : Wreath.rightEnd
            let steps = 24
            for step in 0...steps {
                let degrees = from + (to - from) * Double(step) / Double(steps)
                let point = Wreath.point(degrees)
                if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
        }
        return path.applying(Wreath.fit(rect))
    }
}

// MARK: - Les feuilles

/// Les feuilles de la couronne, acquises ou restant à gagner.
///
/// Deux passes séparées parce qu'une `Shape` n'a qu'un seul remplissage : les
/// acquises sont pleines, les autres sont tracées au filet. C'est le
/// remplissage, et non la teinte, qui porte la différence — la règle de toute
/// l'application.
struct LaurelLeaves: Shape {
    /// Feuilles acquises **par branche**.
    let acquired: Int
    /// `true` pour les feuilles déjà posées, `false` pour celles qui restent.
    let showsAcquired: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let leaf = leafPath()

        for onLeft in [true, false] {
            for index in 0..<Distinction.leavesPerBranch {
                guard (index < acquired) == showsAcquired else { continue }
                let degrees = Wreath.leafAngle(index: index, onLeft: onLeft)
                let anchor = Wreath.point(degrees)
                let placement = CGAffineTransform(translationX: anchor.x, y: anchor.y)
                    .rotated(by: Wreath.leafRotation(degrees: degrees, onLeft: onLeft))
                path.addPath(leaf, transform: placement)
            }
        }
        return path.applying(Wreath.fit(rect))
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
/// point. Aucun n'emprunte sa silhouette à une récompense existante.
struct DistinctionEmblem: Shape {
    let distinction: Distinction

    /// Les emblèmes sont dessinés dans un carré de 100, comme la famille
    /// d'icônes de l'application.
    private static let reference: CGFloat = 100

    func path(in rect: CGRect) -> Path {
        var path = Path()
        switch distinction {
        case .selection: drawLaurelKnot(&path)
        case .mention: drawRibbon(&path)
        case .prix: drawMedal(&path)
        case .grandPrix: drawStatuette(&path)
        case .hommage: drawStar(&path)
        }
        return path.applying(Wreath.fit(rect, reference: Self.reference))
    }

    /// Le nœud des deux branches. Rien de plus : à ce degré on est retenu, on
    /// n'est pas récompensé, et le vide au centre est le propos.
    private func drawLaurelKnot(_ path: inout Path) {
        path.move(to: CGPoint(x: 40, y: 38))
        path.addCurve(
            to: CGPoint(x: 60, y: 38),
            control1: CGPoint(x: 46, y: 46), control2: CGPoint(x: 54, y: 46)
        )
        path.move(to: CGPoint(x: 42, y: 46))
        path.addCurve(
            to: CGPoint(x: 58, y: 46),
            control1: CGPoint(x: 47, y: 52), control2: CGPoint(x: 53, y: 52)
        )
    }

    /// La cocarde et ses deux pans. Un ruban se porte un soir, puis se range.
    private func drawRibbon(_ path: inout Path) {
        path.addEllipse(in: CGRect(x: 39, y: 29, width: 22, height: 22))
        path.addEllipse(in: CGRect(x: 45, y: 35, width: 10, height: 10))

        path.move(to: CGPoint(x: 43, y: 49))
        path.addLine(to: CGPoint(x: 38, y: 68))
        path.addLine(to: CGPoint(x: 46, y: 63))
        path.addLine(to: CGPoint(x: 50, y: 70))

        path.move(to: CGPoint(x: 57, y: 49))
        path.addLine(to: CGPoint(x: 62, y: 68))
        path.addLine(to: CGPoint(x: 54, y: 63))
        path.addLine(to: CGPoint(x: 50, y: 70))
    }

    /// Le disque frappé, sa bélière, et le grènetis de la tranche : douze crans,
    /// comme sur une médaille réellement frappée.
    private func drawMedal(_ path: inout Path) {
        path.move(to: CGPoint(x: 42, y: 24))
        path.addLine(to: CGPoint(x: 46, y: 36))
        path.move(to: CGPoint(x: 58, y: 24))
        path.addLine(to: CGPoint(x: 54, y: 36))

        path.addEllipse(in: CGRect(x: 33, y: 35, width: 34, height: 34))
        path.addEllipse(in: CGRect(x: 39, y: 41, width: 22, height: 22))

        let center = CGPoint(x: 50, y: 52)
        for notch in 0..<12 {
            let a = Double(notch) / 12 * 2 * .pi
            path.move(to: CGPoint(x: center.x + 17 * cos(a), y: center.y + 17 * sin(a)))
            path.addLine(to: CGPoint(x: center.x + 20 * cos(a), y: center.y + 20 * sin(a)))
        }
    }

    /// Une silhouette effilée sur un socle à deux degrés. Elle ne se porte plus :
    /// elle se pose, et se montre à qui entre.
    private func drawStatuette(_ path: inout Path) {
        path.move(to: CGPoint(x: 50, y: 18))
        path.addCurve(
            to: CGPoint(x: 44, y: 54),
            control1: CGPoint(x: 44, y: 28), control2: CGPoint(x: 42, y: 40)
        )
        path.addLine(to: CGPoint(x: 56, y: 54))
        path.addCurve(
            to: CGPoint(x: 50, y: 18),
            control1: CGPoint(x: 58, y: 40), control2: CGPoint(x: 56, y: 28)
        )
        path.closeSubpath()

        path.move(to: CGPoint(x: 50, y: 26))
        path.addLine(to: CGPoint(x: 50, y: 54))

        path.addRect(CGRect(x: 41, y: 54, width: 18, height: 12))
        path.addRect(CGRect(x: 37, y: 66, width: 26, height: 8))
    }

    /// L'étoile inscrite dans sa dalle et son listel. Scellée au sol, publique,
    /// et jamais reprise.
    private func drawStar(_ path: inout Path) {
        path.addRoundedRect(
            in: CGRect(x: 24, y: 24, width: 52, height: 52),
            cornerSize: CGSize(width: 3, height: 3)
        )
        path.addRoundedRect(
            in: CGRect(x: 29, y: 29, width: 42, height: 42),
            cornerSize: CGSize(width: 2, height: 2)
        )

        let center = CGPoint(x: 50, y: 50)
        for corner in 0..<10 {
            let radius: CGFloat = corner.isMultiple(of: 2) ? 16 : 6.6
            let a = -Double.pi / 2 + Double(corner) * .pi / 5
            let point = CGPoint(x: center.x + radius * cos(a), y: center.y + radius * sin(a))
            if corner == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
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
    var size: CGFloat = 190

    /// Le PNG d'un badge garde une marge transparente autour de sa monture,
    /// pour laisser respirer son ombre portée. Ce zoom rogne cette marge en
    /// cercle, pour que le badge remplisse son siège et non sa marge.
    private static let badgeZoom: CGFloat = 1.55

    private var acquired: Int { distinction.acquiredLeaves(count: galleryCount) }
    private var seatSize: CGFloat { size * Wreath.seatDiameter / Wreath.box }
    private var emblemSize: CGFloat { size * Wreath.emblemBox / Wreath.box }

    var body: some View {
        ZStack {
            LaurelStems()
                .stroke(distinction.accent.opacity(0.42), style: StrokeStyle(lineWidth: 1, lineCap: .round))

            LaurelLeaves(acquired: acquired, showsAcquired: false)
                .stroke(distinction.accent.opacity(0.26), lineWidth: 0.7)

            LaurelLeaves(acquired: acquired, showsAcquired: true)
                .fill(distinction.accent)

            DistinctionEmblem(distinction: distinction)
                .stroke(
                    distinction.accent,
                    style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round)
                )
                .frame(width: emblemSize, height: emblemSize)
                .offset(y: size * (Wreath.emblemCenter.y - Wreath.box / 2) / Wreath.box)

            badgeSeat
                .frame(width: seatSize, height: seatSize)
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
                            size: 190
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
