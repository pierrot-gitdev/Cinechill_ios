//
//  SplashView.swift
//  Cinechill_iOS
//

import SwiftUI

/// L'ouverture de l'app : le faisceau entre par la droite, allume la cabine, traverse la salle
/// **rang par rang**, embrase l'écran, puis la lumière court tout autour du mur et dessine le C.
/// Le C se redresse enfin, descend, et prend la tête du mot.
///
/// Deux choses commandent la séquence, et rien d'autre ne doit les contredire.
///
/// La première est l'ordre. Les fauteuils apparaissaient autrefois en dernier, après le liseré,
/// et ne pouvaient donc pas se lire comme éclairés par quoi que ce soit. Ils sont maintenant
/// révélés par `lightReach` lui-même : `CinechillMark` compare la progression du front à la
/// distance de chaque rang à la cabine, si bien que l'écart entre deux rangs n'est écrit nulle
/// part. Ralentir la traversée les écarte d'elle-même.
///
/// La seconde est que le mark et le mot ne sont pas deux vues empilées mais **un seul
/// verrouillage**. La ligne finale est composée dès la première image, lettres comprises,
/// simplement invisibles ; le logo est dessiné dans la case du C, à qui un `GeometryReader` dit
/// où se trouve le centre de l'écran. Il n'y a donc aucune position à mesurer ni à corriger :
/// le C atterrit exactement sur sa case parce qu'il n'en est jamais sorti.
///
/// Ce n'est pas un indicateur de chargement : la séquence se joue **en entier**, même si Firebase
/// a déjà répondu. C'est un choix, pas un oubli — le splash est le seul moment où la marque a
/// l'écran pour elle. Les données, elles, se chargent en tâche de fond pendant ce temps
/// (`RootView` précharge l'accueil), si bien que l'animation ne coûte du temps que lorsqu'elle
/// est plus lente que le réseau. À 5,00 s, elle l'est encore : c'est assumé.
///
/// Ces 5 s sont un budget, pas une conséquence. Si la séquence doit encore raccourcir, on prend
/// sur l'entrée et sur la queue, jamais sur la traversée : c'est elle qui montre la salle.
///
/// `onFinished` est appelé à la fin de la séquence ; c'est l'appelant qui décide de passer la
/// main, une fois que l'animation **et** l'auth sont prêtes.
struct SplashView: View {
    var onFinished: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // La lame qui entre.
    @State private var bladeOffset: CGFloat = 1
    @State private var bladeOpacity: Double = 0

    // La salle.
    @State private var boothGlow: Double = 0
    @State private var lightReach: CGFloat = 0
    @State private var screenFlare: Double = 0
    @State private var bloom: Double = 0

    // Le C.
    @State private var rimTrim: Double = 0
    @State private var wallReveal: Double = 0
    @State private var markScale: CGFloat = 0.94

    // Le débordement hors du cercle.
    @State private var coneSpread: CGFloat = 0.06
    @State private var coneOpacity: Double = 0

    // La marquise.
    @State private var descended = false
    @State private var handedOver = false
    @State private var lettersIn = [Bool](repeating: false, count: 8)
    @State private var glintProgress: CGFloat = 0
    @State private var glintOpacity: Double = 0

    /// La hauteur à laquelle le logo joue sa séquence, avant de descendre au centre.
    private static let markHeight: CGFloat = 0.36
    private static let space = "splash"
    /// Le mot moins son C, qui vient du logo.
    private static let rest = Array("INECHILL")

    private let markSize: CGFloat = 216
    private let nameSize: CGFloat = 32

    /// L'interlettre de la marquise, 0,34 em. Portée par l'espacement du `HStack` plutôt que
    /// par `.tracking` : le tracking ajoute aussi une chasse après la dernière lettre, qui
    /// décentre le mot d'une demi-interlettre.
    private var nameTracking: CGFloat { nameSize * 0.34 }
    /// La hauteur de capitale de SF, et donc le diamètre du C dans la ligne.
    private var capHeight: CGFloat { nameSize * 0.70 }
    /// L'espace entre le C et la première lettre.
    private var capGap: CGFloat { nameSize * 0.30 }
    /// Le cadre à donner au tracé pour que son C fasse exactement une hauteur de capitale :
    /// le cercle extérieur occupe 392 des 512 unités du dessin.
    private var outlineSize: CGFloat { capHeight / Self.circleShare }
    /// Ce qui reste du logo une fois réduit à la taille d'une lettre.
    private var shrunkScale: CGFloat { capHeight / (Self.circleShare * markSize) }

    private static let circleShare: CGFloat =
        CinechillMarkMetrics.outerRadius * 2 / CinechillMarkMetrics.canvas

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                background
                bloomLight(proxy)
                spill(proxy)
                marquee(proxy)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .coordinateSpace(.named(Self.space))
        }
        .ignoresSafeArea()
        .task { await run() }
    }

    // MARK: Le verrouillage

    /// Le mot entier, C compris. Il est composé dès le départ, à sa place définitive : ce sont
    /// les lettres qui sont invisibles, pas la ligne qui n'existerait pas encore.
    private func marquee(_ proxy: GeometryProxy) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: capGap) {
            capSlot(proxy)
                // Le bas de la case sur la ligne de base : la case *est* alors la hauteur de
                // capitale, et le C s'aligne sur les lettres sans réglage optique.
                .alignmentGuide(.lastTextBaseline) { $0.height }

            letters
        }
        .overlay { glint(proxy) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "Cinechill"))
    }

    /// La case du C. Vide en mise en page, elle ne sert qu'à réserver la place ; le logo est
    /// dessiné par-dessus, sans jamais peser sur la ligne quelle que soit sa taille du moment.
    private func capSlot(_ proxy: GeometryProxy) -> some View {
        Color.clear
            .frame(width: capHeight, height: capHeight)
            .overlay {
                GeometryReader { slot in
                    let box = slot.frame(in: .named(Self.space))
                    travellingMark(
                        slot: slot.size,
                        // Le centre de l'écran, dit dans le repère de la case.
                        resting: CGPoint(
                            x: proxy.size.width / 2 - box.minX,
                            y: proxy.size.height * Self.markHeight - box.minY
                        )
                    )
                }
            }
    }

    /// Le logo pendant tout son voyage, du plein cadre à la lettre.
    ///
    /// La bascule de `-10°` est ce qui le fait lire comme un objet posé ; l'annuler est
    /// exactement ce qui en fait une lettre, puisque l'ouverture de la cabine pointe alors
    /// droit à droite. Il n'y a rien d'autre à dessiner pour obtenir le C.
    private func travellingMark(slot: CGSize, resting: CGPoint) -> some View {
        ZStack {
            ZStack {
                halo
                CinechillMark(
                    wallReveal: wallReveal,
                    rimTrim: rimTrim,
                    lightReach: lightReach,
                    screenFlare: screenFlare,
                    boothGlow: boothGlow
                )
                .frame(width: markSize, height: markSize)
                incomingBlade
            }
            .scaleEffect(markScale * (descended ? shrunkScale : 1))
            .rotationEffect(.degrees(descended ? 10 : 0))
            .opacity(handedOver ? 0 : 1)

            // Le relais. À hauteur de capitale, la salle du mark plein n'est plus qu'une
            // bouillie ; le tracé, lui, a été dessiné pour cette taille. Même géométrie de
            // part et d'autre, donc aucun décalage au passage.
            CinechillMarkOutline(lineWidth: 1.4)
                .foregroundStyle(Color(hex: 0xEDF1F5))
                .frame(width: outlineSize, height: outlineSize)
                .rotationEffect(.degrees(10))
                .opacity(handedOver ? 1 : 0)
        }
        .position(
            x: descended ? slot.width / 2 : resting.x,
            y: descended ? slot.height / 2 : resting.y
        )
    }

    private var letters: some View {
        HStack(spacing: nameTracking) {
            ForEach(Array(Self.rest.enumerated()), id: \.offset) { index, character in
                Text(verbatim: String(character))
                    .font(.system(size: nameSize, weight: .ultraLight))
                    .foregroundStyle(Color(hex: 0xEDF1F5))
                    .opacity(lettersIn[index] ? 0.94 : 0)
                    .offset(x: lettersIn[index] ? 0 : -14)
                    .blur(radius: lettersIn[index] ? 0 : 4)
            }
        }
    }

    /// L'éclat qui traverse la ligne entière, C compris : c'est le même faisceau qui balaie
    /// le mur, pas un effet posé sur du texte.
    private func glint(_ proxy: GeometryProxy) -> some View {
        LinearGradient(
            colors: [.clear, CinechillPalette.lightPale.opacity(0.85), .clear],
            startPoint: .leading, endPoint: .trailing
        )
        .frame(width: 120, height: nameSize * 2.6)
        .blur(radius: 8)
        .blendMode(.screen)
        .opacity(glintOpacity)
        .offset(x: -proxy.size.width * 0.55 + glintProgress * proxy.size.width * 1.3)
        .allowsHitTesting(false)
    }

    // MARK: Décor

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [CinechillPalette.night, CinechillPalette.nightMid, CinechillPalette.nightDeep],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [CinechillPalette.light.opacity(0.10 * wallReveal), .clear],
                center: UnitPoint(x: 0.5, y: Self.markHeight), startRadius: 20, endRadius: 420
            )
        }
        .ignoresSafeArea()
    }

    /// Lueur froide qui monte derrière le mark à mesure que la salle s'éclaire, et qui s'éteint
    /// quand le C s'en détache pour rejoindre le mot.
    private var halo: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [CinechillPalette.light.opacity(0.22), .clear],
                    center: .center, startRadius: 6, endRadius: markSize * 0.78
                )
            )
            .frame(width: markSize * 1.7, height: markSize * 1.7)
            .opacity(descended ? 0 : wallReveal)
    }

    /// La lame de lumière qui arrive de la droite et vient se loger dans la cabine. Elle porte la
    /// même inclinaison que le mark, pour entrer exactement dans l'ouverture.
    private var incomingBlade: some View {
        let unit = markSize / CinechillMarkMetrics.canvas

        return ZStack {
            LinearGradient(
                colors: [
                    .clear,
                    CinechillPalette.light.opacity(0.45),
                    CinechillPalette.lightPale,
                    CinechillPalette.lightPale.opacity(0)
                ],
                startPoint: .trailing, endPoint: .leading
            )
            .frame(width: 440 * unit, height: 24 * unit)
            .blur(radius: 5 * unit)
            .position(x: 566 * unit, y: 256 * unit)
        }
        .frame(width: markSize, height: markSize)
        .rotationEffect(CinechillMarkMetrics.tilt)
        .offset(x: bladeOffset * markSize)
        .opacity(descended ? 0 : bladeOpacity)
    }

    /// L'embrasement de l'écran déborde du logo. Sans cette couche, le pic reste enfermé dans
    /// le cercle intérieur, qui le masque, et le moment le plus lumineux de la séquence ne se
    /// voit pas. Centrée sur l'écran du plan, pas sur le logo.
    private func bloomLight(_ proxy: GeometryProxy) -> some View {
        RadialGradient(
            colors: [
                CinechillPalette.lightPale.opacity(0.50),
                CinechillPalette.light.opacity(0.12),
                .clear
            ],
            center: .center, startRadius: 0, endRadius: 250
        )
        .frame(width: 520, height: 520)
        .position(
            x: proxy.size.width / 2 + screenOffset.width,
            y: proxy.size.height * Self.markHeight + screenOffset.height
        )
        .opacity(bloom)
        .blendMode(.screen)
        .allowsHitTesting(false)
    }

    /// Le cône qui sort du cercle : la projection cesse d'être contenue par le logo et vient
    /// laver le bas de l'écran. Sommet à la cabine, base hors du cadre, même bascule que le mark.
    private func spill(_ proxy: GeometryProxy) -> some View {
        let width = proxy.size.width * 1.9

        return SpillCone()
            .fill(
                LinearGradient(
                    colors: [
                        CinechillPalette.lightPale.opacity(0.50),
                        CinechillPalette.light.opacity(0.16),
                        .clear
                    ],
                    startPoint: .trailing, endPoint: .leading
                )
            )
            .frame(width: width, height: proxy.size.height * 1.2)
            .blur(radius: 18)
            .scaleEffect(x: coneSpread, anchor: .trailing)
            .rotationEffect(CinechillMarkMetrics.tilt, anchor: .trailing)
            // `.position` place le centre du cadre : on recule d'une demi-largeur pour que ce
            // soit le sommet, et non le milieu, qui tombe sur la cabine.
            .position(
                x: proxy.size.width / 2 + boothOffset.width - width / 2,
                y: proxy.size.height * Self.markHeight + boothOffset.height
            )
            .opacity(coneOpacity)
            .blendMode(.screen)
            .allowsHitTesting(false)
    }

    // MARK: Repères

    /// La cabine et l'écran, ramenés du repère du dessin à un décalage en points depuis le
    /// centre du mark, bascule comprise.
    private var boothOffset: CGSize { markOffset(of: CinechillMarkMetrics.booth) }

    private var screenOffset: CGSize {
        markOffset(of: CGPoint(
            x: CinechillMarkMetrics.center.x - CinechillMarkMetrics.screenRadius,
            y: CinechillMarkMetrics.center.y
        ))
    }

    private func markOffset(of point: CGPoint) -> CGSize {
        let unit = markSize / CinechillMarkMetrics.canvas
        let dx = (point.x - CinechillMarkMetrics.center.x) * unit
        let dy = (point.y - CinechillMarkMetrics.center.y) * unit
        let angle = CinechillMarkMetrics.tilt.radians
        return CGSize(
            width: dx * cos(angle) - dy * sin(angle),
            height: dx * sin(angle) + dy * cos(angle)
        )
    }

    // MARK: Séquence

    private func run() async {
        guard !reduceMotion else {
            // Même destination, sans le voyage.
            withAnimation(.easeOut(duration: 0.3)) {
                boothGlow = 1
                lightReach = 512
                screenFlare = 0.34
                rimTrim = 1
                wallReveal = 1
                markScale = 1
                coneSpread = 1
                coneOpacity = 0.85
                bladeOffset = 0
                bladeOpacity = 0.22
                descended = true
                handedOver = true
                lettersIn = lettersIn.map { _ in true }
            }
            await sleep(900)
            onFinished()
            return
        }

        // 1 — la lame arrive de la droite.
        withAnimation(.easeOut(duration: 0.15)) { bladeOpacity = 1 }
        withAnimation(.timingCurve(0.2, 0.7, 0.25, 1, duration: 0.72)) { bladeOffset = 0 }
        withAnimation(.timingCurve(0.2, 0.8, 0.25, 1, duration: 1.10)) { markScale = 1 }
        await sleep(580)

        // 2 — elle atteint la cabine, qui s'allume.
        withAnimation(.easeOut(duration: 0.32)) { boothGlow = 1 }
        withAnimation(.easeIn(duration: 0.40)) { bladeOpacity = 0.22 }
        await sleep(220)

        // 3 — la projection traverse la salle.
        //
        // La courbe est presque droite, et c'est tout l'enjeu : à vitesse constante, l'œil
        // comprend qu'il regarde un espace traversé. Les cinq rangs s'allument au passage du
        // front, à 0,92 s, 1,07 s, 1,22 s, 1,36 s et 1,51 s — non pas parce que ces instants
        // sont écrits ici, mais parce que c'est là que la lumière les atteint. Changer la
        // durée ci-dessous les réécarte donc toute seule, dans les mêmes proportions.
        //
        // C'est la phase qu'on protège quand il faut raccourcir : les quatorze centièmes qui
        // séparent deux rangs sont le minimum pour qu'on lise une salle traversée plutôt que
        // cinq arcs qui s'allument ensemble.
        withAnimation(.timingCurve(0.35, 0.15, 0.55, 0.92, duration: 1.35)) {
            lightReach = 260
        }
        await sleep(1130)

        // 4 — le front atteint la paroi opposée : l'écran s'embrase, et déborde.
        withAnimation(.easeOut(duration: 0.20)) {
            screenFlare = 0.95
            bloom = 0.80
        }
        await sleep(200)
        withAnimation(.easeOut(duration: 0.48)) {
            screenFlare = 0.34
            bloom = 0
        }
        await sleep(170)

        // 5 — la lumière court autour du mur : c'est elle qui dessine le C.
        withAnimation(.timingCurve(0.5, 0, 0.2, 1, duration: 1.05)) { rimTrim = 1 }
        await sleep(150)
        withAnimation(.easeIn(duration: 1.00)) { wallReveal = 1 }
        await sleep(350)

        // 6 — la projection sort du cercle et lave le bas de l'écran.
        withAnimation(.easeOut(duration: 0.70)) { coneOpacity = 0.85 }
        withAnimation(.timingCurve(0.2, 0.7, 0.25, 1, duration: 1.20)) { coneSpread = 1 }
        await sleep(550)

        // 7 — le C se redresse, rétrécit, et descend prendre la tête du mot.
        withAnimation(.timingCurve(0.55, 0.02, 0.2, 1, duration: 0.80)) { descended = true }
        await sleep(550)

        // 8 — le relais vers le tracé, pendant que le mouvement finit.
        withAnimation(.easeInOut(duration: 0.28)) { handedOver = true }
        await sleep(100)

        // 9 — les lettres sortent de derrière le C et s'écartent jusqu'à leur interlettre.
        for index in lettersIn.indices {
            withAnimation(
                .timingCurve(0.2, 0.75, 0.3, 1, duration: 0.55)
                .delay(Double(index) * 0.05)
            ) {
                lettersIn[index] = true
            }
        }
        await sleep(200)

        // 10 — l'éclat traverse la ligne entière.
        withAnimation(.easeOut(duration: 0.15)) { glintOpacity = 1 }
        withAnimation(.timingCurve(0.4, 0.05, 0.3, 1, duration: 0.80)) { glintProgress = 1 }
        await sleep(650)
        withAnimation(.easeIn(duration: 0.15)) { glintOpacity = 0 }
        await sleep(150)

        onFinished()
    }

    private func sleep(_ milliseconds: UInt64) async {
        try? await Task.sleep(nanoseconds: milliseconds * 1_000_000)
    }
}

/// Le cône de projection hors du logo : sommet à droite, base hors cadre à gauche.
private struct SpillCone: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

#Preview {
    SplashView()
}
