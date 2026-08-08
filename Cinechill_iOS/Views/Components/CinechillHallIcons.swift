//
//  CinechillHallIcons.swift
//  Cinechill_iOS
//

import SwiftUI

/// Les icônes du Hall, dans l'écriture « La Gravure » de `CinechillNavIcons`.
///
/// Mêmes trois règles, sans exception : grille de 24 avec zone vive de 20 et
/// trait de 1,5 ; **une brèche unique sur l'arête haute**, qui rejoue la coupe
/// du logo ; **un seul élément plein**, le point de lumière logé dans cette
/// brèche, de rayon constant.
///
/// Le raccourci qui rend la famille évidente : le logo est une salle vue du
/// dessus, donc **un utilisateur est une salle**. Un anneau ouvert, c'est
/// quelqu'un ; deux anneaux, une relation ; et recommander un film, c'est
/// laisser sortir de sa salle le faisceau qui l'a projeté.
enum CinechillHallIcon: CaseIterable {
    /// La salle — un profil.
    case salle
    /// Le hall — deux salles qui se croisent. Abonnés et abonnements.
    case hall
    /// Le faisceau qui s'échappe par la brèche. Recommander.
    case recommander
    /// La salle devient la lentille — ni loupe générique, ni jumelles.
    case chercher
}

struct CinechillHallIconView: View {
    let icon: CinechillHallIcon
    var lineWidth: CGFloat = 1.5

    init(_ icon: CinechillHallIcon, lineWidth: CGFloat = 1.5) {
        self.icon = icon
        self.lineWidth = lineWidth
    }

    var body: some View {
        GeometryReader { proxy in
            let scale = min(proxy.size.width, proxy.size.height) / 24

            ZStack {
                CinechillHallIconStroke(icon: icon)
                    .stroke(
                        style: StrokeStyle(
                            lineWidth: lineWidth * scale,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                CinechillHallIconLight(icon: icon)
                    .fill()
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

// MARK: - Repère

/// L'espace de dessin 24 × 24, ramené au rectangle alloué. Identique à celui
/// de `CinechillNavIcons` — deux jeux d'icônes qui ne partagent pas leur
/// grille finiraient par ne plus se ressembler.
private struct HallIconSpace {
    let origin: CGPoint
    let scale: CGFloat

    init(_ rect: CGRect) {
        let side = min(rect.width, rect.height)
        scale = side / 24
        origin = CGPoint(x: rect.midX - side / 2, y: rect.midY - side / 2)
    }

    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: origin.x + x * scale, y: origin.y + y * scale)
    }

    func l(_ value: CGFloat) -> CGFloat { value * scale }
}

// MARK: - Le tracé

struct CinechillHallIconStroke: Shape {
    let icon: CinechillHallIcon

    func path(in rect: CGRect) -> Path {
        let s = HallIconSpace(rect)
        var path = Path()

        switch icon {
        case .salle:
            // L'anneau du logo, ouvert au sommet sur 30°.
            path.addArc(
                center: s.p(12, 12), radius: s.l(7.6),
                startAngle: .degrees(-75), endAngle: .degrees(255),
                clockwise: false
            )

        case .hall:
            // Deux salles décalées en diagonale : celle du fond ouverte au
            // sommet, celle du premier plan ouverte face à elle. Le
            // chevauchement dit la relation sans qu'aucune ne se ferme.
            path.addArc(
                center: s.p(9, 9.4), radius: s.l(5.4),
                startAngle: .degrees(-64), endAngle: .degrees(244),
                clockwise: false
            )
            path.addArc(
                center: s.p(15.4, 15), radius: s.l(5.4),
                startAngle: .degrees(116), endAngle: .degrees(64),
                clockwise: false
            )

        case .recommander:
            // La salle, plus petite pour laisser passer le faisceau, et le
            // trait de lumière qui s'en échappe par la brèche.
            path.addArc(
                center: s.p(10.6, 13.4), radius: s.l(6.4),
                startAngle: .degrees(-70), endAngle: .degrees(228),
                clockwise: false
            )
            path.move(to: s.p(14.6, 8.4))
            path.addLine(to: s.p(20.6, 3.6))
            // La pointe du faisceau, ouverte : une flèche pleine serait le
            // deuxième élément plein de l'icône.
            path.move(to: s.p(16.6, 3.4))
            path.addLine(to: s.p(20.9, 3.3))
            path.addLine(to: s.p(20.8, 7.6))

        case .chercher:
            // La lentille est une salle : même anneau, même brèche au sommet.
            // Le manche part du bas droit, à 45°.
            path.addArc(
                center: s.p(10.6, 10.6), radius: s.l(6.4),
                startAngle: .degrees(-74), endAngle: .degrees(254),
                clockwise: false
            )
            path.move(to: s.p(15.3, 15.3))
            path.addLine(to: s.p(20.4, 20.4))
        }

        return path
    }
}

// MARK: - Le point de lumière

/// L'unique élément plein de chaque icône, logé dans la brèche. Rayon
/// constant, comme dans la barre de navigation : c'est la même lumière d'une
/// icône à l'autre, seule sa position change.
struct CinechillHallIconLight: Shape {
    let icon: CinechillHallIcon

    private static let radius: CGFloat = 1.15

    func path(in rect: CGRect) -> Path {
        let s = HallIconSpace(rect)
        let center: CGPoint

        switch icon {
        case .salle:       center = s.p(12, 4.4)
        case .hall:        center = s.p(9, 4)
        case .recommander: center = s.p(12.8, 8.2)
        case .chercher:    center = s.p(10.6, 4.2)
        }

        let r = s.l(Self.radius)
        return Path(ellipseIn: CGRect(
            x: center.x - r, y: center.y - r, width: r * 2, height: r * 2
        ))
    }
}

#Preview("Icônes du Hall") {
    ZStack {
        LinearGradient(
            colors: [CinechillPalette.night, CinechillPalette.nightDeep],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        VStack(spacing: 30) {
            ForEach([48, 24, 17], id: \.self) { size in
                HStack(spacing: 24) {
                    ForEach(Array(CinechillHallIcon.allCases.enumerated()), id: \.offset) { pair in
                        CinechillHallIconView(pair.element)
                            .frame(width: CGFloat(size), height: CGFloat(size))
                    }
                }
            }
        }
        .foregroundStyle(Color(red: 0.82, green: 0.87, blue: 0.91))
    }
    .ignoresSafeArea()
}
