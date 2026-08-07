//
//  CinechillNavIcons.swift
//  Cinechill_iOS
//

import SwiftUI

/// Les cinq destinations de la barre de navigation.
enum CinechillIcon: CaseIterable {
    /// L'Arche — le seuil de la salle. Accueillir, c'est laisser entrer.
    case accueil
    /// La mise au point — le champ se resserre jusqu'à un seul film.
    case cinematch
    /// Le photogramme — on avance image par image, on tranche.
    case decouvrir
    /// La mosaïque — des tuiles d'aires inégales, la mise en page de la frise.
    case galerie
    /// Le billet — réservé, décidé, j'y vais.
    case watchlist
}

/// Les icônes de navigation, dans l'écriture « La Gravure ».
///
/// Trois règles tiennent tout le jeu :
/// 1. grille de 24, zone vive 20, trait de 1,5 aux extrémités arrondies ;
/// 2. **une brèche unique par icône**, toujours sur l'arête haute — c'est la coupe du logo,
///    qui n'est pas un C fermé non plus, transformée en signature de famille ;
/// 3. **un seul élément plein**, le point de lumière logé dans cette brèche.
///
/// Les métaphores ont été choisies contre les icônes génériques qu'elles remplacent : ni maison,
/// ni étoile « IA », ni médaille, ni marque-page — rien ici qui ne parle de cinéma.
struct CinechillNavIcon: View {
    let icon: CinechillIcon
    /// Épaisseur du trait, exprimée dans la grille de 24 : elle suit l'échelle de l'icône.
    var lineWidth: CGFloat = 1.5

    init(_ icon: CinechillIcon, lineWidth: CGFloat = 1.5) {
        self.icon = icon
        self.lineWidth = lineWidth
    }

    var body: some View {
        GeometryReader { proxy in
            let scale = min(proxy.size.width, proxy.size.height) / 24

            ZStack {
                CinechillIconStroke(icon: icon)
                    .stroke(
                        style: StrokeStyle(
                            lineWidth: lineWidth * scale,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                CinechillIconLight(icon: icon)
                    .fill()
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

// MARK: - Repère

/// L'espace de dessin 24 × 24, ramené au rectangle alloué.
private struct IconSpace {
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

    func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
        CGRect(origin: p(x, y), size: CGSize(width: l(w), height: l(h)))
    }
}

// MARK: - Le tracé

/// La partie tracée de chaque icône. Les arcs de coin passent par `addArc(tangent1End:…)`
/// plutôt que par des arcs paramétrés : le sens de balayage n'entre alors pas en jeu, et
/// une inversion silencieuse devient impossible.
struct CinechillIconStroke: Shape {
    let icon: CinechillIcon

    func path(in rect: CGRect) -> Path {
        let s = IconSpace(rect)
        var path = Path()

        switch icon {
        case .accueil:
            // Deux jambages et un cintre de rayon 7,2 centré en (12, 11.4).
            // La brèche est au sommet, à l'endroit de la clé de voûte.
            path.move(to: s.p(4.8, 20.2))
            path.addLine(to: s.p(4.8, 11.4))
            path.addArc(center: s.p(12, 11.4), radius: s.l(7.2),
                        startAngle: .degrees(180), endAngle: .degrees(255), clockwise: false)
            path.move(to: s.p(13.86, 4.45))
            path.addArc(center: s.p(12, 11.4), radius: s.l(7.2),
                        startAngle: .degrees(285), endAngle: .degrees(360), clockwise: false)
            path.addLine(to: s.p(19.2, 20.2))

        case .cinematch:
            // Anneau ouvert en haut à droite — la forme du logo — et son noyau.
            path.addArc(center: s.p(12, 12), radius: s.l(7.6),
                        startAngle: .degrees(-28.3), endAngle: .degrees(309.7), clockwise: false)
            path.move(to: s.p(15.2, 12))
            path.addArc(center: s.p(12, 12), radius: s.l(3.2),
                        startAngle: .degrees(0), endAngle: .degrees(360), clockwise: false)

        case .decouvrir:
            // Photogramme avant au format 4:3, ouvert sur son arête haute.
            path.move(to: s.p(10.5, 7.6))
            path.addLine(to: s.p(4.2, 7.6))
            path.addArc(tangent1End: s.p(2.3, 7.6), tangent2End: s.p(2.3, 9.5), radius: s.l(1.9))
            path.addLine(to: s.p(2.3, 16.9))
            path.addArc(tangent1End: s.p(2.3, 18.8), tangent2End: s.p(4.2, 18.8), radius: s.l(1.9))
            path.addLine(to: s.p(15.4, 18.8))
            path.addArc(tangent1End: s.p(17.3, 18.8), tangent2End: s.p(17.3, 16.9), radius: s.l(1.9))
            path.addLine(to: s.p(17.3, 9.5))
            path.addArc(tangent1End: s.p(17.3, 7.6), tangent2End: s.p(15.4, 7.6), radius: s.l(1.9))
            path.addLine(to: s.p(13.7, 7.6))
            // L'angle du photogramme suivant, décalé : la bande avance.
            path.move(to: s.p(7.4, 4.6))
            path.addLine(to: s.p(18.6, 4.6))
            path.addArc(tangent1End: s.p(20.5, 4.6), tangent2End: s.p(20.5, 6.5), radius: s.l(1.9))
            path.addLine(to: s.p(20.5, 13.9))

        case .galerie:
            // Quatre tuiles d'aires inégales. Elles pavent — elles ne montent pas :
            // c'est ce qui sépare une collection d'une mesure.
            path.move(to: s.p(5.6, 3.4))
            path.addLine(to: s.p(3.2, 3.4))
            path.addLine(to: s.p(3.2, 13.6))
            path.addLine(to: s.p(11, 13.6))
            path.addLine(to: s.p(11, 3.4))
            path.addLine(to: s.p(8.6, 3.4))
            path.addRect(s.rect(12.6, 3.4, 8.2, 6.4))
            path.addRect(s.rect(12.6, 11.2, 8.2, 9.4))
            path.addRect(s.rect(3.2, 15, 7.8, 5.6))

        case .watchlist:
            // Billet à encoches latérales et talon détachable.
            path.move(to: s.p(10.4, 8))
            path.addLine(to: s.p(4.8, 8))
            path.addArc(tangent1End: s.p(3, 8), tangent2End: s.p(3, 9.8), radius: s.l(1.8))
            path.addLine(to: s.p(3, 10.4))
            // Encoche gauche : demi-cercle bombant vers l'intérieur.
            path.addArc(center: s.p(3, 12), radius: s.l(1.6),
                        startAngle: .degrees(270), endAngle: .degrees(450), clockwise: false)
            path.addLine(to: s.p(3, 14.2))
            path.addArc(tangent1End: s.p(3, 16), tangent2End: s.p(4.8, 16), radius: s.l(1.8))
            path.addLine(to: s.p(19.2, 16))
            path.addArc(tangent1End: s.p(21, 16), tangent2End: s.p(21, 14.2), radius: s.l(1.8))
            path.addLine(to: s.p(21, 13.6))
            path.addArc(center: s.p(21, 12), radius: s.l(1.6),
                        startAngle: .degrees(90), endAngle: .degrees(270), clockwise: false)
            path.addLine(to: s.p(21, 9.8))
            path.addArc(tangent1End: s.p(21, 8), tangent2End: s.p(19.2, 8), radius: s.l(1.8))
            path.addLine(to: s.p(13.6, 8))
            // La ligne de déchirure.
            path.move(to: s.p(8.6, 10.6))
            path.addLine(to: s.p(8.6, 11.9))
            path.move(to: s.p(8.6, 13.2))
            path.addLine(to: s.p(8.6, 14.5))
        }

        return path
    }
}

// MARK: - Le point de lumière

/// L'unique élément plein de chaque icône, logé dans la brèche. Rayon constant : c'est la
/// même lumière d'une icône à l'autre, seule sa position change.
struct CinechillIconLight: Shape {
    let icon: CinechillIcon

    private static let radius: CGFloat = 1.15

    func path(in rect: CGRect) -> Path {
        let s = IconSpace(rect)
        let center: CGPoint

        switch icon {
        case .accueil:   center = s.p(12, 4.05)
        case .cinematch: center = s.p(18.9, 6)
        case .decouvrir: center = s.p(12.1, 7.6)
        case .galerie:   center = s.p(7.1, 3.4)
        case .watchlist: center = s.p(12, 8)
        }

        let r = s.l(Self.radius)
        return Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
    }
}

#Preview("Icônes") {
    ZStack {
        LinearGradient(
            colors: [CinechillPalette.night, CinechillPalette.nightDeep],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        VStack(spacing: 26) {
            ForEach([44, 22, 16], id: \.self) { size in
                HStack(spacing: 22) {
                    ForEach(Array(CinechillIcon.allCases.enumerated()), id: \.offset) { pair in
                        CinechillNavIcon(pair.element)
                            .frame(width: CGFloat(size), height: CGFloat(size))
                    }
                }
            }
        }
        .foregroundStyle(Color(red: 0.82, green: 0.87, blue: 0.91))
    }
    .ignoresSafeArea()
}
