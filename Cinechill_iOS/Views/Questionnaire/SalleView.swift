//
//  SalleView.swift
//  Cinechill_iOS
//

import SwiftUI

/// La Salle : le décor de toute la séance, une fois la porte franchie.
///
/// La porte racontait le mérite ; la salle raconte la suite. C'est le rituel
/// d'avant la séance : on s'assied, les lumières sont allumées, et à chaque
/// réponse la salle s'assombrit d'un cran pendant que l'écran monte. Au verdict
/// la salle est noire et le film est projeté.
///
/// Deux conséquences, et ce sont elles qui font la refonte.
///
/// **La progression n'a plus besoin d'une barre : la lumière est la jauge.**
/// C'est la règle de l'application — une mesure se lit, elle ne se remplit pas —
/// enfin portée par le lieu au lieu d'être tracée à côté.
///
/// **Toute question est écrite sur la toile.** On ne parcourt jamais un
/// catalogue : on répond à ce que la salle projette. Choisir son film
/// indirectement cesse d'être une intention et devient la mécanique visible.
///
/// Le décor s'obtient par la géométrie et la valeur, jamais par un dégradé
/// décoratif : quatre plans, quatre rangées, dix veilleuses.
enum SalleGeometry {
    /// Le dessin est composé dans une boîte de 390 × 844 et étiré à la taille
    /// réelle. Les proportions bougent d'un appareil à l'autre, la perspective
    /// le supporte ; ce qui compte est que l'écran tombe toujours au même
    /// endroit relatif, puisque c'est lui qui porte le texte.
    static let width: CGFloat = 390
    static let height: CGFloat = 844

    /// La toile, au fond. C'est le seul rectangle dont la position est un
    /// contrat : `SalleStage` y pose la question.
    static let screen = CGRect(x: 78, y: 190, width: 234, height: 130)

    /// Où finit la dernière rangée de fauteuils.
    ///
    /// **Rien ne se pose au-dessus de cette ligne.** Ni les réponses, ni le
    /// voile : le décor doit rester lisible en entier, et une puce posée sur
    /// une rangée ne se lit ni comme une puce ni comme un fauteuil. Le bloc de
    /// sièges a été resserré en trois rangées pour que ce qui reste en dessous
    /// suffise à un écran de réponses complet, sans défilement.
    static let seatingBottom: CGFloat = 422

    /// Le repère commun de la scène : `SalleAnswers` s'en sert pour savoir où
    /// finit la toile, quelle que soit sa place dans la pile.
    static let space = "salle"

    static func scale(_ size: CGSize) -> CGSize {
        CGSize(width: size.width / width, height: size.height / height)
    }

    static func rect(_ r: CGRect, in size: CGSize) -> CGRect {
        let s = scale(size)
        return CGRect(
            x: r.minX * s.width, y: r.minY * s.height,
            width: r.width * s.width, height: r.height * s.height
        )
    }
}

// MARK: - Les paliers de lumière

/// Les paliers du rituel, de l'entrée à la projection.
///
/// Une seule règle : ça ne remonte jamais. Un écran plus sombre que le
/// précédent dit qu'on a avancé, et c'est le seul indicateur d'avancement de
/// toute la séance.
enum SalleLight {
    /// On entre. Salle éclairée.
    static let entry: Double = 1
    /// La durée de la soirée.
    static let frame: Double = 0.82
    static let genre: Double = 0.66
    static let origin: Double = 0.54
    static let mood: Double = 0.42
    static let searching: Double = 0.34
    /// Les questions, qui éteignent la salle une à une. Le plancher évite que
    /// le décor disparaisse avant le verdict, qui doit rester le seul noir.
    static func asking(question: Int) -> Double {
        max(0.12, 0.30 - 0.025 * Double(max(0, question - 1)))
    }
    static let enriching: Double = 0.08
    static let finalizing: Double = 0.04
    /// Noir complet. Le film est projeté.
    static let verdict: Double = 0
}

// MARK: - Le décor

/// Le volume de la salle, en perspective à un point.
///
/// `Animatable` n'est pas une précaution : **un `Canvas` n'interpole pas la
/// lecture d'une variable**. SwiftUI anime des modificateurs, pas le corps
/// d'une vue ; sans `animatableData` le passage d'un palier à l'autre serait un
/// saut, quelle que soit l'animation posée par l'appelant.
struct SalleBackdrop: View, Animatable {
    /// 1 = salle éclairée, écran au plus bas. 0 = noir, la projection a
    /// commencé.
    var light: Double
    /// Le verdict éteint la toile : elle n'a plus de question à porter, et
    /// l'affiche du film prend sa place, entière. Sans ça, le plus grand aplat
    /// de l'application serait un rectangle blanc derrière elle.
    var showsScreen = true
    /// Les veilleuses s'éteignent aussi au verdict : cinq points de couleur
    /// autour d'une affiche, c'est cinq accents qui lui disputent le regard.
    /// Le film doit être la seule chose colorée de l'écran.
    var showsAisleLights = true

    var animatableData: Double {
        get { light }
        set { light = newValue }
    }

    /// Les quatre rangées, de plus en plus grandes vers nous. C'est la seule
    /// chose qui dit qu'on est assis quelque part, et non devant une image.
    private static let rows: [(y: CGFloat, h: CGFloat, r: CGFloat, x0: CGFloat, x1: CGFloat)] = [
        (336, 15, 4, 104, 286), (364, 19, 5, 84, 306), (398, 24, 6, 60, 330),
    ]

    /// Les cinq artéfacts devenus veilleuses d'allée : ce qui reste de la porte
    /// une fois qu'on l'a franchie, et le seul endroit où ces teintes survivent.
    private static let aisleKeys: [DoorArtifactKey] = [
        .memoire, .eventail, .coeur, .horizons, .promesse,
    ]

    /// L'ordonnée de la n-ième veilleuse, de la plus lointaine à la plus
    /// proche. Les cinq intervalles suivent une progression géométrique de
    /// raison 1,5 : c'est ce qui fait lire la profondeur sans que deux repères
    /// se touchent au fond ni ne se perdent au premier plan.
    private static func aisleY(_ index: Int) -> CGFloat {
        let ratio: CGFloat = 1.5
        var y: CGFloat = 336
        var step: CGFloat = 15.3
        for _ in 0 ..< index {
            y += step
            step *= ratio
        }
        return y
    }

    var body: some View {
        Canvas { context, size in
            let l = max(0, min(1, light))
            // Le décor s'éteint, l'écran monte : les deux sont liés, comme dans
            // une vraie salle où l'un ne baisse que pour que l'autre existe.
            //
            // La toile reste **sombre** et ce qui monte est sa lumière. Elle a
            // été un aplat clair, sur lequel la question s'écrivait en noir :
            // un écran de cinéma allumé n'est pas une feuille de papier, et le
            // texte projeté est toujours clair sur un fond profond.
            let screenLevel = 0.25 + 0.75 * (1 - l)

            let wallHigh = Color.salleMix(0x0B111A, 0x1B2634, l)
            let wallLow = Color.salleMix(0x070C13, 0x101823, l)
            let floorHigh = Color.salleMix(0x0A1019, 0x1A2230, l)
            let seatFill = Color.salleMix(0x04070C, 0x0C131C, l)
            let screenTint = Color.salleMix(0x0C1119, 0x1E2C3E, screenLevel)

            let s = SalleGeometry.scale(size)
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: x * s.width, y: y * s.height)
            }
            func quad(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) -> Path {
                var path = Path()
                path.move(to: a)
                path.addLine(to: b)
                path.addLine(to: c)
                path.addLine(to: d)
                path.closeSubpath()
                return path
            }

            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Ink.ground))

            // Le volume : plafond, murs, sol. Tout converge vers l'écran.
            context.fill(
                quad(p(-60, 60), p(450, 60), p(312, 190), p(78, 190)),
                with: .linearGradient(
                    Gradient(colors: [wallHigh, wallLow]),
                    startPoint: p(0, 60), endPoint: p(0, 190)
                )
            )
            context.fill(
                quad(p(-60, 60), p(78, 190), p(78, 320), p(-60, 700)),
                with: .linearGradient(
                    Gradient(colors: [wallLow, wallHigh]),
                    startPoint: p(-60, 0), endPoint: p(78, 0)
                )
            )
            context.fill(
                quad(p(450, 60), p(312, 190), p(312, 320), p(450, 700)),
                with: .linearGradient(
                    Gradient(colors: [wallLow, wallHigh]),
                    startPoint: p(450, 0), endPoint: p(312, 0)
                )
            )
            context.fill(
                quad(p(-60, 700), p(78, 320), p(312, 320), p(450, 700)),
                with: .linearGradient(
                    Gradient(colors: [floorHigh, CinechillPalette.nightMid]),
                    startPoint: p(0, 320), endPoint: p(0, 700)
                )
            )

            // Le faisceau, qui n'existe que quand la salle est presque noire.
            let beam = max(0, 1 - l * 2.2)
            if beam > 0.001 {
                context.fill(
                    quad(p(170, 720), p(220, 720), p(312, 190), p(78, 190)),
                    with: .linearGradient(
                        Gradient(colors: [
                            Color(hex: 0xE8F4FF).opacity(0),
                            Color(hex: 0xE8F4FF).opacity((0.05 + 0.09 * (1 - l)) * beam),
                        ]),
                        startPoint: p(0, 720), endPoint: p(0, 190)
                    )
                )
            }

            // Ce que l'écran éclaire autour de lui, puis l'écran.
            context.fill(
                Path(ellipseIn: SalleGeometry.rect(
                    CGRect(x: -5, y: 105, width: 400, height: 300), in: size
                )),
                with: .radialGradient(
                    Gradient(colors: [
                        Color(hex: 0xF4FDFF).opacity(0.05 + 0.3 * screenLevel),
                        Color(hex: 0xF4FDFF).opacity(0.02 + 0.09 * screenLevel),
                        Color(hex: 0xF4FDFF).opacity(0),
                    ]),
                    center: p(195, 255), startRadius: 0, endRadius: 200 * s.width
                )
            )
            if showsScreen {
                let screenRect = SalleGeometry.rect(SalleGeometry.screen, in: size)
                context.fill(Path(screenRect), with: .color(screenTint))
                // La lueur du projecteur au centre de la toile : c'est elle qui
                // dit que l'écran est allumé, et elle monte avec la séance.
                context.fill(
                    Path(screenRect),
                    with: .radialGradient(
                        Gradient(colors: [
                            Color(hex: 0xBFD9F0).opacity(0.10 + 0.30 * screenLevel),
                            Color(hex: 0x8FB4D8).opacity(0.03 + 0.10 * screenLevel),
                            Color(hex: 0x0C1119).opacity(0),
                        ]),
                        center: CGPoint(x: screenRect.midX, y: screenRect.midY),
                        startRadius: 0, endRadius: screenRect.width * 0.62
                    )
                )
                context.stroke(
                    Path(SalleGeometry.rect(
                        SalleGeometry.screen.insetBy(dx: -1.5, dy: -1.5), in: size
                    )),
                    with: .color(Color(hex: 0xC6D3DF).opacity(0.14 + 0.3 * screenLevel)),
                    lineWidth: 1
                )
            }

            // Un rectangle arrondi ne fait pas un siège. Chacun en porte trois :
            // le dossier, plus haut et plus étroit, l'assise qui déborde devant,
            // et deux accoudoirs qui l'encadrent. Le liseré clair du haut du
            // dossier attrape la lumière de l'écran, comme le velours d'une vraie
            // salle — c'est lui qui fait lire la rangée d'un coup d'œil.
            let seatCrest = Color.salleMix(0x121A24, 0x2C3A4C, l)
            for row in Self.rows {
                let gap: CGFloat = 4
                let w = (row.x1 - row.x0 - gap * 7) / 8
                for i in 0 ..< 8 {
                    let x = row.x0 + CGFloat(i) * (w + gap)
                    let arm = w * 0.13
                    let backH = row.h * 0.74

                    // L'assise, large, posée au sol de la rangée.
                    context.fill(
                        Path(roundedRect: SalleGeometry.rect(
                            CGRect(x: x, y: row.y + backH * 0.55,
                                   width: w, height: row.h - backH * 0.55),
                            in: size
                        ), cornerRadius: row.r * 0.5 * s.width),
                        with: .color(seatFill)
                    )
                    // Les accoudoirs, de part et d'autre.
                    for ax in [x, x + w - arm] {
                        context.fill(
                            Path(roundedRect: SalleGeometry.rect(
                                CGRect(x: ax, y: row.y + backH * 0.42,
                                       width: arm, height: row.h - backH * 0.42),
                                in: size
                            ), cornerRadius: row.r * 0.4 * s.width),
                            with: .color(seatCrest.opacity(0.55))
                        )
                    }
                    // Le dossier, plus étroit que l'assise, arrondi en haut.
                    let back = SalleGeometry.rect(
                        CGRect(x: x + arm * 0.7, y: row.y,
                               width: w - arm * 1.4, height: backH),
                        in: size
                    )
                    context.fill(
                        Path(roundedRect: back, cornerRadius: row.r * s.width),
                        with: .color(seatFill)
                    )
                    context.stroke(
                        Path(roundedRect: back, cornerRadius: row.r * s.width),
                        with: .color(seatCrest),
                        lineWidth: max(0.6, 0.9 * s.width)
                    )
                }
            }

            // Les veilleuses bordent les allées latérales, **en dehors du bloc
            // de fauteuils** : posées dessus, elles se lisaient comme des taches
            // sur les sièges au lieu de baliser un chemin. Elles suivent la même
            // fuite que les rangées, un cran plus large à chaque plan, et
            // s'allument à mesure que la salle s'éteint.
            if showsAisleLights {
            for (index, key) in Self.aisleKeys.enumerated() {
                // Les intervalles croissent d'un facteur constant vers nous,
                // pas selon un carré : le carré tassait les deux plus lointaines
                // à sept points l'une de l'autre pendant que la plus proche
                // partait à cinquante. Une raison de 1,5 donne la fuite sans
                // l'accident, et la largeur, le rayon et la lueur la suivent.
                let y = Self.aisleY(index)
                let half = 106 + (y - 336) * 0.62
                let r = 1.5 * pow(1.28, CGFloat(index))
                let tint = Color(hex: key.hue)
                for x in [195 - half, 195 + half] {
                    let halo = r * 3.4
                    context.fill(
                        Path(ellipseIn: SalleGeometry.rect(
                            CGRect(x: x - halo, y: y - halo, width: halo * 2, height: halo * 2),
                            in: size
                        )),
                        with: .color(tint.opacity(0.10 + 0.16 * (1 - l)))
                    )
                    context.fill(
                        Path(ellipseIn: SalleGeometry.rect(
                            CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2), in: size
                        )),
                        with: .color(tint.opacity(0.5 + 0.5 * (1 - l)))
                    )
                }
            }
            }
        }
        .accessibilityHidden(true)
    }
}

extension Color {
    /// Interpolation de deux couleurs écrites en hexadécimal, dans l'espace
    /// sRGB. Le décor n'a besoin que de ça : sept dégradés pilotés par un
    /// unique curseur.
    static func salleMix(_ from: UInt, _ to: UInt, _ t: Double) -> Color {
        let k = max(0, min(1, t))
        func channel(_ shift: UInt) -> Double {
            let a = Double((from >> shift) & 0xFF)
            let b = Double((to >> shift) & 0xFF)
            return (a + (b - a) * k) / 255
        }
        return Color(.sRGB, red: channel(16), green: channel(8), blue: channel(0))
    }
}

// MARK: - La toile, et ce qui est écrit dessus

/// Ce qui se pose sur le décor : la question projetée, le voile, le contenu.
///
/// **Le décor n'est pas ici.** `SalleBackdrop` est posé une seule fois, au-dessus
/// de l'aiguillage des phases, et c'est ce qui permet à la lumière de descendre
/// d'un palier à l'autre au lieu de sauter : une vue remplacée ne s'anime pas,
/// une vue qui reste change de valeur et s'anime. La scène, elle, est refaite à
/// chaque écran, puisque c'est elle qui porte la question.
///
/// Le voile reprend le dispositif du mur d'affiches qu'il remplace : la salle
/// redevient matière sous le texte, sans quoi les réponses se liraient sur un
/// décor. Il ne commence qu'au bas de la toile, pour ne pas effacer la question
/// qu'on vient d'y écrire.
struct SalleStage<Content: View, Projection: View>: View {
    /// Écrite sur la toile, en encre sombre. Ce n'est plus un formulaire qui
    /// interroge, c'est la salle.
    var question: String?
    /// Le rang de la question, en niveau de service au-dessus d'elle.
    var eyebrow: String?
    /// Ce qui est projeté à la place du texte : au verdict, le film lui-même.
    /// L'écran cesse alors de poser une question pour donner la réponse.
    @ViewBuilder var projected: () -> Projection
    @ViewBuilder var content: () -> Content

    init(
        question: String? = nil,
        eyebrow: String? = nil,
        @ViewBuilder projected: @escaping () -> Projection,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.question = question
        self.eyebrow = eyebrow
        self.projected = projected
        self.content = content
    }

    var body: some View {
        GeometryReader { proxy in
            // Le décor est dessiné plein cadre, zones sûres comprises ; la
            // scène, elle, vit dedans. Sans cette reconstitution, la toile
            // serait située des dizaines de points trop haut.
            let full = CGSize(
                width: proxy.size.width
                    + proxy.safeAreaInsets.leading + proxy.safeAreaInsets.trailing,
                height: proxy.size.height
                    + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom
            )
            // Ce n'est pas le bas de la toile qui borne les réponses mais le
            // bas de la dernière rangée : entre les deux, il y a des fauteuils.
            let floorTop = SalleGeometry.seatingBottom
                * SalleGeometry.scale(full).height - proxy.safeAreaInsets.top

            stack(veilTop: floorTop)
                .environment(\.salleScreenBottom, floorTop)
                .coordinateSpace(name: SalleGeometry.space)
        }
    }

    private func stack(veilTop: CGFloat) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                screenLayer

                // Le voile ne monte plus jusqu'aux fauteuils : il commence là où
                // ils s'arrêtent, sinon il lavait la seule chose qui dit qu'on
                // est assis quelque part.
                LinearGradient(
                    colors: [
                        Ink.ground.opacity(0), Ink.ground.opacity(0.55),
                        Ink.ground.opacity(0.93), Ink.ground,
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: max(0, proxy.size.height - veilTop)
                    + proxy.safeAreaInsets.bottom)
                .allowsHitTesting(false)
                .ignoresSafeArea(edges: .bottom)

                content()
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    /// Ce qui occupe la toile : une image projetée, ou la question écrite
    /// dessus. Jamais les deux — l'écran dit une chose à la fois.
    @ViewBuilder
    private var screenLayer: some View {
        if Projection.self != EmptyView.self {
            GeometryReader { proxy in
                let frame = SalleGeometry.rect(SalleGeometry.screen, in: proxy.size)
                projected()
                    .frame(width: frame.width, height: frame.height)
                    .clipped()
                    .position(x: frame.midX, y: frame.midY)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        } else if question != nil || eyebrow != nil {
            GeometryReader { proxy in
                let frame = SalleGeometry.rect(
                    SalleGeometry.screen.insetBy(dx: 8, dy: 10),
                    in: proxy.size
                )
                VStack(spacing: 8) {
                    if let eyebrow {
                        Text(eyebrow)
                            .planLabel()
                            .foregroundStyle(Color(hex: 0xC6D3DF).opacity(0.55))
                    }
                    if let question {
                        // Empattements, chasse ouverte, et une lueur derrière
                        // les lettres : la question est projetée sur une toile,
                        // pas tapée dans un formulaire.
                        Text(question)
                            .font(.system(size: 19, weight: .regular, design: .serif))
                            .kerning(0.5)
                            .lineSpacing(4)
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.7)
                            .foregroundStyle(Color(hex: 0xF2F7FB))
                            .shadow(color: Color(hex: 0x9FCDF2).opacity(0.35), radius: 9)
                    }
                }
                .padding(.horizontal, 6)
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)
                .transition(.opacity)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(question ?? "")
        }
    }
}

/// L'attente, projetée : une **amorce de projection**.
///
/// Le message tombait sur les rangées de fauteuils, au seul endroit de l'écran
/// où l'on s'était promis de ne rien poser. Il est maintenant sur la toile, à
/// la place de la question — c'est la salle qui dit qu'elle cherche.
///
/// L'amorce est le cercle à croix de visée que les projectionnistes voient
/// défiler avant chaque bobine : un secteur y tourne pour marquer les dernières
/// secondes. C'est, littéralement, le premier indicateur d'attente du cinéma,
/// et il a l'avantage de ne rien promettre — on ne sait pas combien de temps la
/// recherche prendra, et une barre qui se remplit l'aurait prétendu.
struct SalleLeader: View {
    let message: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweep: Double = 0

    private var tint: Color { Color(hex: 0xF2F7FB) }

    var body: some View {
        VStack(spacing: 12) {
            leader
                .frame(width: 46, height: 46)

            Text(message)
                .font(.system(size: 13.5, weight: .regular, design: .serif))
                .kerning(0.4)
                .lineSpacing(3)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.75)
                .foregroundStyle(tint)
                .shadow(color: Color(hex: 0x9FCDF2).opacity(0.35), radius: 8)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var leader: some View {
        ZStack {
            // Le secteur qui tourne. Réduit au repos quand le système demande
            // moins de mouvement : l'amorce reste lisible à l'arrêt.
            LeaderWedge()
                .fill(tint.opacity(0.16))
                .rotationEffect(.degrees(sweep))

            Circle()
                .strokeBorder(tint.opacity(0.5), lineWidth: 1)

            // La croix de visée, qui traverse le cercle de part en part.
            Path { path in
                path.move(to: CGPoint(x: 23, y: 0))
                path.addLine(to: CGPoint(x: 23, y: 46))
                path.move(to: CGPoint(x: 0, y: 23))
                path.addLine(to: CGPoint(x: 46, y: 23))
            }
            .stroke(tint.opacity(0.34), lineWidth: 1)

            Circle()
                .fill(tint.opacity(0.7))
                .frame(width: 3, height: 3)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) {
                sweep = 360
            }
        }
    }
}

/// Le secteur de l'amorce : un quart de tour, pointe au centre.
private struct LeaderWedge: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        path.move(to: center)
        path.addArc(
            center: center, radius: rect.width / 2,
            startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

/// Les réponses, posées sur le parterre : le vide devant la première rangée.
///
/// **Rien ne se pose sur la salle.** Un bloc trop haut se mettait à défiler
/// par-dessus la toile et les fauteuils, et recouvrait la question qu'on venait
/// d'y projeter. La marge de tête réserve tout le décor — écran et rangées
/// comprises — et c'est dans ce qui reste, devant les sièges, que les réponses
/// vivent. Le bloc de sièges a été resserré exprès pour que ce « reste »
/// suffise à un écran complet sans défilement.
struct SalleAnswers<Content: View>: View {
    @Environment(\.salleScreenBottom) private var screenBottom
    @ViewBuilder var content: () -> Content

    /// Ce qui sépare la dernière rangée du premier mot de réponse.
    private static var clearance: CGFloat { 18 }

    var body: some View {
        GeometryReader { proxy in
            let top = max(
                0,
                screenBottom - proxy.frame(in: .named(SalleGeometry.space)).minY
                    + Self.clearance
            )
            ScrollView {
                content()
                    // Centrées et non plaquées en bas : trois puces se
                    // retrouvaient collées au bouton, à la limite du pouce, avec
                    // tout le vide au-dessus d'elles. Un bloc long remplit et
                    // défile comme avant.
                    .frame(
                        maxWidth: .infinity,
                        minHeight: max(0, proxy.size.height - top),
                        alignment: .center
                    )
                    .padding(.top, top)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

private struct SalleScreenBottomKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    /// L'ordonnée du bas de la toile, dans l'espace de coordonnées de la scène.
    var salleScreenBottom: CGFloat {
        get { self[SalleScreenBottomKey.self] }
        set { self[SalleScreenBottomKey.self] = newValue }
    }
}

extension SalleStage where Projection == EmptyView {
    /// Le cas courant : la toile porte une question, pas une image.
    init(
        question: String? = nil,
        eyebrow: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(
            question: question, eyebrow: eyebrow,
            projected: { EmptyView() }, content: content
        )
    }
}

#Preview("La Salle") {
    struct Harness: View {
        @State private var light: Double = 1

        var body: some View {
            ZStack {
                SalleBackdrop(light: light)
                    .ignoresSafeArea()
                    .animation(.easeInOut(duration: 0.7), value: light)

                SalleStage(question: "Vous êtes combien ?") {
                    VStack(spacing: 16) {
                        Spacer()
                        Slider(value: $light, in: 0 ... 1)
                            .tint(Ink.light)
                        Text(verbatim: String(format: "lumière %.0f %%", light * 100))
                            .planLabel()
                            .foregroundStyle(Ink.ink2)
                    }
                    .padding(Metrics.margin)
                }
            }
        }
    }
    return Harness()
}
