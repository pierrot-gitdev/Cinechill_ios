//
//  CinechillMark.swift
//  Cinechill_iOS
//

import SwiftUI

/// Le logo Cinechill en vectoriel, redessiné d'après le SVG de référence (espace 512 × 512).
///
/// Le PNG de l'icône système suffit pour Xcode, mais pas ici : le splash et le spinner animent
/// des *parties* du dessin — la lame de lumière qui entre, le liseré qui fait le tour du C, le
/// faisceau qui balaie la salle. Il faut donc des formes séparées et pilotables.
///
/// Le symbole est un plan de salle de cinéma vu du dessus : l'anneau est le mur, l'ouverture à
/// droite est la cabine de projection, l'arc lumineux à gauche est l'écran courbe, et les arcs
/// pointillés sont les rangées de fauteuils — chaque tiret est un siège.
enum CinechillMarkMetrics {
    static let canvas: CGFloat = 512
    static let center = CGPoint(x: 256, y: 256)
    static let outerRadius: CGFloat = 196
    static let innerRadius: CGFloat = 118

    /// L'ouverture est une tranche horizontale, pas un secteur radial : les deux faces coupées
    /// sont parallèles, ce qui fait lire « bloc taillé » plutôt que « lettre dessinée ».
    static let cutHalfHeight: CGFloat = 52

    /// Le mark est basculé pour se lire comme un objet posé, pas comme un schéma technique.
    static let tilt: Angle = .degrees(-10)

    /// La cabine, d'où part la projection. Juste à l'intérieur du mur.
    static let booth = CGPoint(x: 372, y: 256)

    /// Les rangées sont centrées sur l'écran et non sur la salle : elles s'incurvent donc
    /// autour de lui, comme dans une vraie salle.
    static let screenFocus = CGPoint(x: 144, y: 256)

    /// L'écran occupe la paroi opposée à la cabine.
    static let screenStart: Double = 152
    static let screenEnd: Double = 208
    static let screenRadius: CGFloat = 109
    static let screenThickness: CGFloat = 18

    static let seatRows: [(radius: CGFloat, halfSpan: Double)] = [
        (92, 34), (120, 34), (148, 32), (176, 29), (204, 25)
    ]

    /// Décalage de la face du mur par rapport à sa couche « arête », qui crée le biseau.
    /// C'est ce décalage qui rendait le bas du C invisible : la face y déborde sous l'arête,
    /// et c'est sa teinte la plus sombre qui formait le bord. Le liseré est tracé à part,
    /// précisément pour y échapper.
    static let bevelScale: CGFloat = 0.9875
    static let bevelOffset = CGSize(width: 3.16, height: 3.56)
}

// MARK: - Repère de dessin

/// Convertit l'espace de dessin 512 × 512 vers le rectangle réellement alloué à la vue.
struct CinechillMarkSpace {
    let origin: CGPoint
    let scale: CGFloat

    init(_ rect: CGRect) {
        let side = min(rect.width, rect.height)
        scale = side / CinechillMarkMetrics.canvas
        origin = CGPoint(x: rect.midX - side / 2, y: rect.midY - side / 2)
    }

    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: origin.x + x * scale, y: origin.y + y * scale)
    }

    func point(_ p: CGPoint) -> CGPoint { point(p.x, p.y) }

    /// Longueur exprimée en unités de dessin.
    func length(_ value: CGFloat) -> CGFloat { value * scale }

    var center: CGPoint { point(CinechillMarkMetrics.center) }
}

// MARK: - Formes

/// L'anneau du mur, en remplissage pair-impair (disque extérieur moins disque intérieur).
///
/// On passe par le pair-impair plutôt que par `Path.addArc` parce que le sens de balayage d'un
/// arc dépend du repère et se prête aux inversions silencieuses. L'ouverture est retirée
/// ensuite, par masque.
struct CinechillAnnulusShape: Shape {
    func path(in rect: CGRect) -> Path {
        let space = CinechillMarkSpace(rect)
        var path = Path()
        path.addEllipse(in: centeredRect(space, radius: CinechillMarkMetrics.outerRadius))
        path.addEllipse(in: centeredRect(space, radius: CinechillMarkMetrics.innerRadius))
        return path
    }

    private func centeredRect(_ space: CinechillMarkSpace, radius: CGFloat) -> CGRect {
        let r = space.length(radius)
        return CGRect(x: space.center.x - r, y: space.center.y - r, width: r * 2, height: r * 2)
    }
}

/// Plein sauf l'ouverture de la cabine : sert de masque pour trancher le mur et le liseré.
struct CinechillCutMaskShape: Shape {
    func path(in rect: CGRect) -> Path {
        let space = CinechillMarkSpace(rect)
        let m = CinechillMarkMetrics.self
        var path = Path()
        path.addRect(rect)
        path.addRect(
            CGRect(
                x: space.point(246, 0).x,
                y: space.point(0, m.center.y - m.cutHalfHeight).y,
                width: space.length(300),
                height: space.length(m.cutHalfHeight * 2)
            )
        )
        return path
    }
}

/// Le faisceau de projection, de la cabine jusqu'à l'écran.
///
/// Le bord lointain est approché par une quadratique plutôt que par un arc : sur 56° l'écart
/// est invisible, et ça évite de dépendre du sens de balayage.
struct CinechillBeamShape: Shape {
    func path(in rect: CGRect) -> Path {
        let space = CinechillMarkSpace(rect)
        let m = CinechillMarkMetrics.self
        let r = m.screenRadius

        let near = space.point(m.booth)
        let top = polar(space, radius: r, degrees: m.screenEnd)
        let bottom = polar(space, radius: r, degrees: m.screenStart)
        // Intersection des tangentes : rayon / cos(demi-angle).
        let halfSpan = (m.screenEnd - m.screenStart) / 2
        let control = polar(space, radius: r / CGFloat(cos(halfSpan * .pi / 180)), degrees: 180)

        var path = Path()
        path.move(to: near)
        path.addLine(to: top)
        path.addQuadCurve(to: bottom, control: control)
        path.closeSubpath()
        return path
    }

    private func polar(_ space: CinechillMarkSpace, radius: CGFloat, degrees: Double) -> CGPoint {
        let a = degrees * .pi / 180
        return space.point(
            CinechillMarkMetrics.center.x + radius * CGFloat(cos(a)),
            CinechillMarkMetrics.center.y + radius * CGFloat(sin(a))
        )
    }
}

// MARK: - Palette

/// Les valeurs de la finition « Étain », identiques au SVG de référence et aux PNG de l'icône.
/// L'initialiseur `Color(hex:)` vient de `CinephileTier.swift` — un seul dans le projet.
enum CinechillPalette {
    static let night = Color(hex: 0x0A0F16)
    static let nightMid = Color(hex: 0x05080D)
    static let nightDeep = Color(hex: 0x010306)

    static let wallHigh = Color(hex: 0xC6D3DF)
    static let wallMid = Color(hex: 0x93A2B1)
    static let wallLow = Color(hex: 0x6B7885)
    static let wallDeep = Color(hex: 0x4E5A67)

    static let bevelHigh = Color(hex: 0xEAF2F8)
    static let bevelMid = Color(hex: 0xA7B5C2)
    static let bevelLow = Color(hex: 0x5C6874)

    static let rimHigh = Color(hex: 0xF2F9FF)
    static let rimMid = Color(hex: 0xBEE0F5)
    static let rimLow = Color(hex: 0x8CC4E4)
    static let rimDeep = Color(hex: 0x79B6DC)

    static let floor = Color(hex: 0x070C13)
    static let floorDeep = Color(hex: 0x010306)

    static let screen = Color(hex: 0xF4FDFF)
    static let light = Color(hex: 0x7FE3FF)
    static let lightPale = Color(hex: 0xE8FAFF)
    static let lightMid = Color(hex: 0x9EEBFF)

    static let seat = Color(hex: 0x02060B)
    static let seatRim = Color(hex: 0xBFF1FF)
    static let boothLight = Color(hex: 0xF2FCFF)
}

// MARK: - Le logo

/// Le logo complet, avec les leviers dont le splash a besoin. Fond transparent : c'est l'appelant
/// qui pose la nuit derrière, pour que le mark puisse aussi vivre sur d'autres surfaces.
struct CinechillMark: View {
    /// 0 — le mur est à peine deviné dans le noir ; 1 — pleinement éclairé.
    var wallReveal: Double = 1
    /// Fraction du pourtour déjà parcourue par le liseré. C'est la lumière qui « dessine » le C.
    var rimTrim: Double = 1
    /// Rayon atteint par la lumière depuis la cabine, en unités de dessin. Au-delà de ~320 la
    /// salle est entièrement éclairée.
    var lightReach: CGFloat = 512
    /// Présence des fauteuils, qui n'apparaissent qu'une fois la salle éclairée.
    var seatsOpacity: Double = 1
    var boothGlow: Double = 1

    var body: some View {
        GeometryReader { geo in
            let space = CinechillMarkSpace(CGRect(origin: .zero, size: geo.size))

            ZStack {
                room(space)
                wall(space)
                rim(space)
                booth(space)
            }
            .rotationEffect(CinechillMarkMetrics.tilt)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    // MARK: La salle

    private func room(_ space: CinechillMarkSpace) -> some View {
        let m = CinechillMarkMetrics.self

        return ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [CinechillPalette.floor, CinechillPalette.floorDeep],
                        center: .center, startRadius: 0, endRadius: space.length(m.innerRadius)
                    )
                )
                .frame(width: space.length(m.innerRadius * 2), height: space.length(m.innerRadius * 2))
                .position(space.center)

            lightedRoom(space)
        }
        .mask {
            Circle()
                .frame(width: space.length(m.innerRadius * 2), height: space.length(m.innerRadius * 2))
                .position(space.center)
        }
    }

    /// Tout ce que la lumière révèle : l'écran, le faisceau, les fauteuils. L'ensemble est masqué
    /// par un disque qui grandit depuis la cabine — c'est la lumière qui progresse dans la salle.
    private func lightedRoom(_ space: CinechillMarkSpace) -> some View {
        let m = CinechillMarkMetrics.self

        return ZStack {
            // Halo de l'écran, derrière tout le reste.
            trimmedArc(space, radius: m.screenRadius, from: m.screenStart, to: m.screenEnd)
                .stroke(CinechillPalette.light.opacity(0.38), lineWidth: space.length(40))
                .blur(radius: space.length(11))

            // L'écran courbe lui-même.
            trimmedArc(space, radius: m.screenRadius, from: m.screenStart, to: m.screenEnd)
                .stroke(CinechillPalette.screen, lineWidth: space.length(m.screenThickness))

            // Le faisceau, bords diffus.
            CinechillBeamShape()
                .fill(
                    RadialGradient(
                        colors: [
                            .white.opacity(0.92),
                            CinechillPalette.lightPale.opacity(0.46),
                            CinechillPalette.lightMid.opacity(0.22),
                            CinechillPalette.light.opacity(0.14)
                        ],
                        center: UnitPoint(x: m.booth.x / m.canvas, y: m.booth.y / m.canvas),
                        startRadius: 0, endRadius: space.length(240)
                    )
                )
                .blur(radius: space.length(4.5))

            seats(space)
        }
        .mask {
            Circle()
                .frame(width: space.length(lightReach * 2), height: space.length(lightReach * 2))
                .position(space.point(m.booth))
                .blur(radius: space.length(16))
        }
    }

    /// Les fauteuils : des tirets sombres découpés dans la lumière, avec un liseré clair sur le
    /// haut du dossier. Ils ne se voient que là où le faisceau tombe — comme dans une vraie salle.
    private func seats(_ space: CinechillMarkSpace) -> some View {
        let style = StrokeStyle(
            lineWidth: space.length(8),
            lineCap: .round,
            dash: [space.length(5), space.length(11)]
        )

        return ZStack {
            ForEach(CinechillMarkMetrics.seatRows.indices, id: \.self) { index in
                seatRow(space, row: CinechillMarkMetrics.seatRows[index])
                    .stroke(CinechillPalette.seatRim.opacity(0.16), style: style)
                    .offset(y: -space.length(2.5))
            }
            ForEach(CinechillMarkMetrics.seatRows.indices, id: \.self) { index in
                seatRow(space, row: CinechillMarkMetrics.seatRows[index])
                    .stroke(CinechillPalette.seat.opacity(0.72), style: style)
            }
        }
        .opacity(seatsOpacity)
    }

    private func seatRow(_ space: CinechillMarkSpace, row: (radius: CGFloat, halfSpan: Double)) -> some Shape {
        // Une rangée est un arc centré sur l'écran. On le construit par `trim` sur un cercle
        // puis rotation, plutôt que par `addArc` : le résultat ne dépend d'aucune convention
        // de sens de balayage.
        Circle()
            .trim(from: 0, to: row.halfSpan * 2 / 360)
            .rotation(.degrees(-row.halfSpan))
            .path(in: circleRect(space, center: CinechillMarkMetrics.screenFocus, radius: row.radius))
    }

    private func trimmedArc(
        _ space: CinechillMarkSpace, radius: CGFloat, from: Double, to: Double
    ) -> some Shape {
        Circle()
            .trim(from: from / 360, to: to / 360)
            .path(in: circleRect(space, center: CinechillMarkMetrics.center, radius: radius))
    }

    private func circleRect(_ space: CinechillMarkSpace, center: CGPoint, radius: CGFloat) -> CGRect {
        let c = space.point(center)
        let r = space.length(radius)
        return CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
    }

    // MARK: Le mur

    private func wall(_ space: CinechillMarkSpace) -> some View {
        let m = CinechillMarkMetrics.self

        return ZStack {
            CinechillAnnulusShape()
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: CinechillPalette.bevelHigh, location: 0),
                            .init(color: CinechillPalette.bevelMid, location: 0.40),
                            .init(color: CinechillPalette.bevelLow, location: 1)
                        ],
                        startPoint: UnitPoint(x: 0.12, y: 0), endPoint: UnitPoint(x: 0.70, y: 0.90)
                    ),
                    style: FillStyle(eoFill: true)
                )

            CinechillAnnulusShape()
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: CinechillPalette.wallHigh, location: 0),
                            .init(color: CinechillPalette.wallMid, location: 0.30),
                            .init(color: CinechillPalette.wallLow, location: 0.66),
                            .init(color: CinechillPalette.wallDeep, location: 1)
                        ],
                        startPoint: UnitPoint(x: 0.16, y: 0.08), endPoint: UnitPoint(x: 0.82, y: 0.94)
                    ),
                    style: FillStyle(eoFill: true)
                )
                .scaleEffect(m.bevelScale)
                .offset(x: space.length(m.bevelOffset.width), y: space.length(m.bevelOffset.height))

            cutFaces(space)
        }
        .mask { CinechillCutMaskShape().fill(style: FillStyle(eoFill: true)) }
        .opacity(0.10 + 0.90 * wallReveal)
    }

    /// Les deux faces tranchées de l'ouverture. Celle du bas regarde la lumière, celle du haut
    /// est dans l'ombre — c'est ce qu'une entaille dans un bloc éclairé d'en haut à gauche donne.
    private func cutFaces(_ space: CinechillMarkSpace) -> some View {
        ZStack {
            Rectangle()
                .fill(Color(hex: 0x6E93A8).opacity(0.4))
                .frame(width: space.length(85), height: space.length(4))
                .position(space.point(403.5, 202))

            Rectangle()
                .fill(CinechillPalette.lightPale.opacity(0.85))
                .frame(width: space.length(85), height: space.length(5))
                .position(space.point(403.5, 310.5))
        }
    }

    // MARK: Le liseré

    /// Le contour du C. Tracé indépendamment du biseau — sans lui, le bas de la lettre n'a
    /// aucun bord. `trim` part de 3 h, c'est-à-dire exactement de la cabine : au lancement, la
    /// lumière sort du projecteur et court tout autour de la salle.
    private func rim(_ space: CinechillMarkSpace) -> some View {
        let m = CinechillMarkMetrics.self

        return ZStack {
            Circle()
                .trim(from: 0, to: rimTrim)
                .stroke(
                    LinearGradient(
                        stops: [
                            .init(color: CinechillPalette.rimHigh, location: 0),
                            .init(color: CinechillPalette.rimMid, location: 0.28),
                            .init(color: CinechillPalette.rimLow, location: 0.60),
                            .init(color: CinechillPalette.rimDeep, location: 1)
                        ],
                        startPoint: UnitPoint(x: 0.14, y: 0.02), endPoint: UnitPoint(x: 0.80, y: 0.98)
                    ),
                    style: StrokeStyle(lineWidth: space.length(6), lineCap: .round)
                )
                .frame(width: space.length(m.outerRadius * 2), height: space.length(m.outerRadius * 2))
                .position(space.center)

            Circle()
                .trim(from: 0, to: rimTrim)
                .stroke(
                    LinearGradient(
                        stops: [
                            .init(color: CinechillPalette.rimLow.opacity(0.18), location: 0),
                            .init(color: CinechillPalette.rimLow.opacity(0.45), location: 0.45),
                            .init(color: Color(hex: 0xCFE8F8).opacity(0.85), location: 1)
                        ],
                        startPoint: UnitPoint(x: 0.14, y: 0.02), endPoint: UnitPoint(x: 0.80, y: 0.98)
                    ),
                    style: StrokeStyle(lineWidth: space.length(4), lineCap: .round)
                )
                .frame(width: space.length(m.innerRadius * 2), height: space.length(m.innerRadius * 2))
                .position(space.center)
        }
        .mask { CinechillCutMaskShape().fill(style: FillStyle(eoFill: true)) }
    }

    // MARK: La cabine

    private func booth(_ space: CinechillMarkSpace) -> some View {
        RoundedRectangle(cornerRadius: space.length(4), style: .continuous)
            .fill(CinechillPalette.boothLight)
            .frame(width: space.length(18), height: space.length(26))
            .position(space.point(371, 257))
            .shadow(color: CinechillPalette.light.opacity(0.9), radius: space.length(10))
            .shadow(color: CinechillPalette.light.opacity(0.5), radius: space.length(22))
            .opacity(boothGlow)
    }
}

// MARK: - Le tracé

/// Le contour du logo, en un seul chemin fermé — deux arcs et deux droites
/// parallèles, exactement la géométrie du mark plein.
///
/// C'est la version de l'authentification, où l'identité passe par le dessin et
/// non par la lumière : le même fichier sert de signature à 20 pt et de plan à
/// 550 pt, sans que le trait n'épaississe jamais, puisque c'est l'appelant qui
/// choisit l'épaisseur du tracé.
///
/// Les arcs sont échantillonnés plutôt que confiés à `addArc` : le sens de
/// balayage d'un arc SwiftUI dépend d'une convention qui s'inverse selon le
/// repère, et une inversion silencieuse retournerait le C. Ici la trajectoire
/// est écrite en toutes lettres, et le chemin reste continu — donc joignable
/// sans raccord visible.
struct CinechillOutline: Shape {
    /// Demi-ouverture des arcs, en degrés : `asin(52 / rayon)`.
    private static let outerHalf: Double = 15.3846   // asin(52 / 196)
    private static let innerHalf: Double = 26.1478   // asin(52 / 118)

    func path(in rect: CGRect) -> Path {
        let space = CinechillMarkSpace(rect)
        let m = CinechillMarkMetrics.self
        var path = Path()

        // Le mur extérieur, de la lèvre haute de l'ouverture à la lèvre basse,
        // par le long chemin — celui qui fait le C.
        Self.sweep(
            &path, space,
            center: m.center, radius: m.outerRadius,
            from: -Self.outerHalf, to: -(360 - Self.outerHalf),
            starting: true
        )
        // La droite du bas ferme l'ouverture, puis le mur intérieur revient.
        Self.sweep(
            &path, space,
            center: m.center, radius: m.innerRadius,
            from: Self.innerHalf, to: 360 - Self.innerHalf,
            starting: false
        )
        // `close` trace la droite du haut : les deux faces de l'ouverture sont
        // ainsi parallèles par construction, jamais par réglage.
        path.closeSubpath()
        return path
    }

    fileprivate static func sweep(
        _ path: inout Path,
        _ space: CinechillMarkSpace,
        center: CGPoint,
        radius: CGFloat,
        from: Double,
        to: Double,
        starting: Bool
    ) {
        // Un segment tous les deux degrés : sous 1,5 pt d'épaisseur, la corde
        // reste très en deçà du pixel, même à 600 pt de côté.
        let steps = max(12, Int(abs(to - from) / 2))
        for step in 0...steps {
            let degrees = from + (to - from) * Double(step) / Double(steps)
            let radians = degrees * .pi / 180
            let point = space.point(
                center.x + radius * CGFloat(cos(radians)),
                center.y + radius * CGFloat(sin(radians))
            )
            if step == 0 && starting {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
    }
}

/// L'écran courbe et deux rangées de fauteuils, sans le mur.
///
/// Réservé au grand format : à 20 pt ces trois arcs se referment en une tache.
/// Les rangées sont centrées sur l'écran, comme dans le mark plein.
struct CinechillOutlineRoom: Shape {
    func path(in rect: CGRect) -> Path {
        let space = CinechillMarkSpace(rect)
        let m = CinechillMarkMetrics.self
        var path = Path()

        CinechillOutline.sweep(
            &path, space,
            center: m.center, radius: m.screenRadius,
            from: m.screenStart, to: m.screenEnd, starting: true
        )
        for row in [m.seatRows[1], m.seatRows[3]] {
            CinechillOutline.sweep(
                &path, space,
                center: m.screenFocus, radius: row.radius,
                from: -row.halfSpan, to: row.halfSpan, starting: true
            )
        }
        return path
    }
}

/// La signature : le contour, plus le point de lumière logé dans l'ouverture.
///
/// C'est la règle de la famille d'icônes appliquée au logo lui-même — un seul
/// élément plein, dans la brèche.
struct CinechillMarkOutline: View {
    var lineWidth: CGFloat = 1.4
    /// Le point plein. On le coupe aux très petites tailles, où il devient une
    /// bavure plutôt qu'un signe.
    var showsLight: Bool = true

    var body: some View {
        GeometryReader { geo in
            let space = CinechillMarkSpace(CGRect(origin: .zero, size: geo.size))
            let side = space.length(36)

            ZStack {
                CinechillOutline()
                    .stroke(style: StrokeStyle(lineWidth: lineWidth, lineJoin: .round))

                if showsLight {
                    Rectangle()
                        .frame(width: side, height: side)
                        .position(space.point(404, 256))
                }
            }
            .rotationEffect(CinechillMarkMetrics.tilt)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// Le plan : le contour et la salle, au même trait.
struct CinechillPlanOutline: View {
    var lineWidth: CGFloat = 1

    var body: some View {
        ZStack {
            CinechillOutline()
                .stroke(style: StrokeStyle(lineWidth: lineWidth, lineJoin: .round))
            CinechillOutlineRoom()
                .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        }
        .rotationEffect(CinechillMarkMetrics.tilt)
        .aspectRatio(1, contentMode: .fit)
    }
}

#Preview("Logo") {
    ZStack {
        LinearGradient(
            colors: [CinechillPalette.night, CinechillPalette.nightDeep],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        CinechillMark()
            .frame(width: 240, height: 240)
    }
    .ignoresSafeArea()
}

#Preview("Tracé") {
    ZStack {
        CinechillPalette.night
        VStack(spacing: 48) {
            CinechillPlanOutline()
                .foregroundStyle(.white.opacity(0.45))
                .frame(width: 260, height: 260)

            HStack(alignment: .bottom, spacing: 24) {
                CinechillMarkOutline().frame(width: 20, height: 20)
                CinechillMarkOutline().frame(width: 44, height: 44)
                CinechillMarkOutline().frame(width: 88, height: 88)
            }
            .foregroundStyle(Color(hex: 0xEDF1F5))
        }
    }
    .ignoresSafeArea()
}
