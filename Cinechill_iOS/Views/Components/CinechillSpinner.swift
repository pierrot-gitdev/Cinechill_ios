//
//  CinechillSpinner.swift
//  Cinechill_iOS
//

import SwiftUI

/// Secteur de lumière partant du centre de la salle — le faisceau qui balaie les murs.
///
/// Le bord lointain est une quadratique plutôt qu'un arc : sur une cinquantaine de degrés
/// l'écart est invisible, et ça évite de dépendre du sens de balayage de `Path.addArc`.
struct CinechillSweepShape: Shape {
    var halfSpan: Double = 26
    var radius: CGFloat = CinechillMarkMetrics.innerRadius

    func path(in rect: CGRect) -> Path {
        let space = CinechillMarkSpace(rect)
        let c = CinechillMarkMetrics.center

        func polar(_ r: CGFloat, _ degrees: Double) -> CGPoint {
            let a = degrees * .pi / 180
            return space.point(c.x + r * CGFloat(cos(a)), c.y + r * CGFloat(sin(a)))
        }

        var path = Path()
        path.move(to: space.center)
        path.addLine(to: polar(radius, -halfSpan))
        path.addQuadCurve(
            to: polar(radius, halfSpan),
            control: polar(radius / CGFloat(cos(halfSpan * .pi / 180)), 0)
        )
        path.closeSubpath()
        return path
    }
}

/// L'indicateur de chargement de l'app : le logo réduit à ce qui survit à 14 px.
///
/// Tout ce qui demande de la place a sauté — l'écran, les fauteuils, le biseau. Il reste le mur
/// en C et le faisceau qui tourne dans la salle. C'est le même geste que le splash, à l'échelle
/// d'un bouton : le projecteur ne s'arrête pas tant que la donnée n'est pas là.
struct CinechillSpinner: View {
    /// Sur un fond de marque, ou posé sur un aplat coloré (bouton dégradé) où seul du blanc tient.
    enum Tint {
        case brand
        case onAccent
    }

    var size: CGFloat = 24
    var tint: Tint = .brand
    /// Un tour complet. Assez lent pour qu'on lise le geste, assez rapide pour dire « ça travaille ».
    var period: Double = 1.15

    @State private var sweep: Double = 0

    var body: some View {
        GeometryReader { geo in
            let space = CinechillMarkSpace(CGRect(origin: .zero, size: geo.size))
            let inner = space.length(CinechillMarkMetrics.innerRadius * 2)

            ZStack {
                CinechillSweepShape()
                    .fill(
                        RadialGradient(
                            colors: [beamCore, beamEdge],
                            center: .center,
                            startRadius: 0,
                            endRadius: space.length(CinechillMarkMetrics.innerRadius)
                        )
                    )
                    .rotationEffect(.degrees(sweep))
                    .mask {
                        Circle()
                            .frame(width: inner, height: inner)
                            .position(space.center)
                    }

                CinechillAnnulusShape()
                    .fill(wallStyle, style: FillStyle(eoFill: true))
                    .mask { CinechillCutMaskShape().fill(style: FillStyle(eoFill: true)) }
            }
            .rotationEffect(CinechillMarkMetrics.tilt)
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.linear(duration: period).repeatForever(autoreverses: false)) {
                sweep = 360
            }
        }
        .accessibilityLabel("Chargement")
    }

    private var wallStyle: LinearGradient {
        switch tint {
        case .brand:
            return LinearGradient(
                stops: [
                    .init(color: CinechillPalette.wallHigh, location: 0),
                    .init(color: CinechillPalette.wallMid, location: 0.35),
                    .init(color: CinechillPalette.wallLow, location: 1)
                ],
                startPoint: UnitPoint(x: 0.16, y: 0.08), endPoint: UnitPoint(x: 0.82, y: 0.94)
            )
        case .onAccent:
            return LinearGradient(
                colors: [.white, .white.opacity(0.55)],
                startPoint: UnitPoint(x: 0.16, y: 0.08), endPoint: UnitPoint(x: 0.82, y: 0.94)
            )
        }
    }

    private var beamCore: Color {
        tint == .brand ? CinechillPalette.lightPale.opacity(0.95) : .white.opacity(0.95)
    }

    private var beamEdge: Color {
        tint == .brand ? CinechillPalette.light.opacity(0.12) : .white.opacity(0.12)
    }
}

#Preview("Spinner") {
    ZStack {
        LinearGradient(
            colors: [CinechillPalette.night, CinechillPalette.nightDeep],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        HStack(spacing: 26) {
            CinechillSpinner(size: 14)
            CinechillSpinner(size: 22)
            CinechillSpinner(size: 36)
            CinechillSpinner(size: 56)
        }
    }
    .ignoresSafeArea()
}
