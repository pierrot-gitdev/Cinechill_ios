//
//  CineMatchGateView.swift
//  Cinechill_iOS
//

import SwiftUI

/// La porte de CinéMatch — l'écran verrouillé aux cinq artéfacts.
///
/// Une porte monumentale garde l'onglet tant que le profil n'est pas prêt. Son
/// montant central est une serrure sertie de cinq médaillons ; chacun est lié à
/// une condition mesurée par le serveur, s'allume quand elle est remplie, et un
/// conduit de lumière monte de médaillon en médaillon comme une jauge à cinq
/// crans. Le cinquième posé, la clé de voûte — le C de la Salle — s'embrase et
/// la porte s'ouvre.
///
/// **La DA rompt ici avec « Le Plan », volontairement.** La porte reprend la
/// grammaire des badges du profil : montures d'or biseautées, champs émaillés,
/// halos, état éteint dérivé en désaturant comme un badge verrouillé. C'est la
/// seule zone colorée de l'écran — le chrome autour (en-tête, boutons,
/// typographie) reste strictement « Le Plan », et les teintes des artéfacts
/// sont des couleurs de données qui ne sortent jamais de la porte.
///
/// Le texte est réduit au strict mystère : un sur-titre, la jauge, une phrase,
/// le CTA. Tout le reste se découvre en touchant les artéfacts.
///
/// Ce que cet écran ne fait **pas** : annoncer un artéfact gagné. Un artéfact
/// se gagne ailleurs — un balayage dans Découvrir, un cœur posé depuis la
/// galerie — et l'annonce doit tomber là où l'on est, pas à la prochaine
/// visite. Elle vit donc à la racine (`DoorCelebrationOverlay`), pilotée par
/// `DoorStore` ; ici on ne fait que peindre l'état et ouvrir les battants.
struct CineMatchGateView: View {
    let door: DoorState
    /// La porte affichée vient-elle du serveur ? Tant que non — cache local ou
    /// état initial — rien ne se fête et rien ne se consomme : seule une
    /// mesure réelle a le droit d'écrire l'histoire des célébrations.
    let isMeasured: Bool
    /// Les cœurs déjà posés, montrés en direct dans la feuille du Cœur : le
    /// serveur recompte à la prochaine ouverture, mais l'écran n'attend pas.
    let lovedCount: Int
    let onProfileTap: () -> Void
    /// Vers Découvrir — là où la galerie se remplit.
    let onDiscover: () -> Void
    /// Vers la planche des coups de cœur.
    let onLovePicker: () -> Void
    /// La porte est ouverte et le seuil franchi : l'entrée peut prendre place.
    let onEnter: () -> Void
    /// Une célébration d'artéfact occupe l'écran : la porte attend son tour
    /// plutôt que de jouer son ouverture derrière une planche.
    var isCelebrating = false
    /// Le raccourci d'essai, branché sur le banc du `DoorStore`. Un appui long
    /// sur le sur-titre allume un artéfact de plus ; au sixième on revient au
    /// réel. Sans effet en production, où le banc est vide.
    var onDebugAdvance: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var detailArtifact: DoorArtifactKey?
    /// L'action demandée depuis la feuille, jouée à sa fermeture complète :
    /// ouvrir une feuille — ou changer d'onglet — pendant qu'une autre s'anime
    /// en sortie échoue silencieusement de temps en temps sur iOS.
    @State private var pendingDetailAction: DoorArtifactKey?
    /// 0 = fermée, 1 = grande ouverte. C'est la seule valeur animée de l'écran.
    @State private var openProgress: Double = 0
    /// Les battants sont en mouvement : l'écran ne répond plus, et le bas se
    /// tait. On ne franchit un seuil qu'une fois, autant le regarder.
    @State private var isOpening = false
    @State private var hasPlayedOpening = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Ink.ground.ignoresSafeArea()

            doorLayer
            veil
            content
        }
        .overlay(alignment: .top) {
            AppHeaderView(
                title: String(localized: "CinéMatch", bundle: .app),
                onProfileTap: onProfileTap
            )
        }
        .sheet(
            item: $detailArtifact,
            onDismiss: {
                guard let key = pendingDetailAction else { return }
                pendingDetailAction = nil
                if key == .coeur { onLovePicker() } else { onDiscover() }
            }
        ) { key in
            DoorArtifactSheet(
                artifactKey: key,
                door: door,
                lovedCount: lovedCount,
                onAction: {
                    pendingDetailAction = key
                    detailArtifact = nil
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        // Rien ne répond pendant que les battants tournent : c'est la seule
        // fois où l'écran prend la main sur l'utilisateur, et il la rend.
        .allowsHitTesting(!isOpening)
        .task(id: openingTrigger) { await playOpeningIfNeeded() }
    }

    // MARK: - L'ouverture

    /// La course des battants. Assez lente pour qu'on la regarde : c'est le
    /// seul moment de cérémonie de l'application, il ne se rejoue pas.
    private static let openingDuration: Double = 4
    /// Le temps que la porte close, gagnée, se laisse regarder avant de céder.
    private static let openingLeadIn: Double = 1.5
    /// Le flottement, grande ouverte, avant que le seuil ne se propose.
    private static let openingHold: Double = 1.5

    /// Ce qui peut relancer la séquence : la porte qui se gagne, ou la planche
    /// de célébration qui se retire.
    private var openingTrigger: String {
        "\(door.unlocked)-\(isCelebrating)"
    }

    /// Les battants s'écartent, puis le seuil se propose.
    ///
    /// L'animation ne se joue qu'une fois par montage : revenir sur l'onglet
    /// après coup retrouve la porte déjà ouverte, sans rejouer la cérémonie.
    private func playOpeningIfNeeded() async {
        guard door.unlocked else {
            // Le serveur a refermé la porte — un film retiré de la galerie
            // suffit. L'écran le suit sans discuter.
            openProgress = 0
            isOpening = false
            hasPlayedOpening = false
            return
        }
        guard !isCelebrating, !hasPlayedOpening else { return }
        hasPlayedOpening = true

        guard !reduceMotion else {
            openProgress = 1
            return
        }

        isOpening = true
        // Un temps avant : la porte close, gagnée, se laisse regarder. Sans
        // lui l'ouverture démarre dans le même souffle que l'annonce qui la
        // précède, et les deux se mangent.
        try? await Task.sleep(for: .seconds(Self.openingLeadIn))
        guard !Task.isCancelled else { return }
        Haptics.success()
        withAnimation(.easeInOut(duration: Self.openingDuration)) { openProgress = 1 }
        // Puis le flottement, grande ouverte, avant de rendre la main.
        try? await Task.sleep(for: .seconds(Self.openingDuration + Self.openingHold))
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.4)) { isOpening = false }
    }

    // MARK: - La porte

    private var doorLayer: some View {
        VStack(spacing: 0) {
            DoorSceneView(
                door: door,
                isOpen: door.unlocked,
                openProgress: openProgress,
                onArtifactTap: { key in
                    Haptics.impact(.light, intensity: 0.7)
                    detailArtifact = key
                }
            )
            .aspectRatio(390 / 404, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .padding(.top, 104)

            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// Le voile de lisibilité du bas — le rôle documenté de `PlanScrim`.
    private var veil: some View {
        LinearGradient(
            stops: [
                .init(color: Ink.ground.opacity(0), location: 0),
                .init(color: Ink.ground.opacity(0.6), location: 0.35),
                .init(color: Ink.ground.opacity(0.96), location: 0.66),
                .init(color: Ink.ground, location: 1),
            ],
            startPoint: .top, endPoint: .bottom
        )
        .frame(height: 380)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - Le contenu

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Le cercle des cinéphiles", bundle: .app)
                .planLabel()
                .foregroundStyle(Ink.ink2)
                // Le raccourci d'essai. Invisible et sans conséquence pour qui
                // ne le cherche pas : un sur-titre ne se presse pas longuement
                // par accident.
                .contentShape(Rectangle())
                .onLongPressGesture(minimumDuration: 1.2) {
                    Haptics.impact(.medium)
                    onDebugAdvance?()
                }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: "\(door.litCount)")
                    .planTitle(26)
                    .monospacedDigit()
                    .foregroundStyle(Ink.ink)
                // Deux clés distinctes plutôt qu'un ternaire dans `Text` : un
                // ternaire produit une `String` et sortirait du catalogue.
                Group {
                    if door.litCount == 1 {
                        Text("artéfact sur 5", bundle: .app)
                    } else {
                        Text("artéfacts sur 5", bundle: .app)
                    }
                }
                .planLabel()
                .foregroundStyle(Ink.ink3)
            }
            .padding(.top, 8)

            gauge
                .padding(.top, 8)

            Group {
                if door.unlocked {
                    Text("La porte s'ouvre.", bundle: .app)
                } else {
                    Text("CinéMatch se mérite.", bundle: .app)
                }
            }
            .planTitle(26)
            .foregroundStyle(Ink.ink)
            .padding(.top, 16)

            PlanButton(
                title: door.unlocked
                    ? String(localized: "Entrer dans CinéMatch", bundle: .app)
                    : String(localized: "Compléter ma galerie", bundle: .app),
                action: door.unlocked ? onEnter : onDiscover
            )
            .padding(.top, 20)
        }
        .padding(.horizontal, Metrics.margin)
        .padding(.bottom, Metrics.margin)
        .opacity(isOpening ? 0 : 1)
        .animation(Metrics.shift, value: door.litCount)
        .animation(.easeOut(duration: 0.35), value: isOpening)
        .accessibilityElement(children: .contain)
    }

    /// La jauge à cinq crans, dans les cinq teintes : le seul endroit du bas
    /// d'écran où la couleur des artéfacts descend, cran par cran. Chaque
    /// cellule suit **son** artéfact, pas un compte : rien n'impose que la
    /// porte s'allume dans l'ordre.
    private var gauge: some View {
        HStack(spacing: 6) {
            ForEach(DoorArtifactKey.allCases, id: \.self) { key in
                Rectangle()
                    .fill(
                        door.artifact(key)?.done == true
                            ? Color(hex: key.hue)
                            : Color(hex: 0xC6D3DF).opacity(0.13)
                    )
                    .frame(height: 3)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - La scène

/// La porte elle-même : chambranle de bronze riveté, fronton en gradins,
/// vantaux émaillés à filets d'or, poignées et gonds, et le montant-serrure aux
/// cinq médaillons. Tout le trait est dessiné dans un repère de 390 × 404 puis
/// mis à l'échelle de la largeur disponible.
private struct DoorSceneView: View {
    let door: DoorState
    let isOpen: Bool
    /// 0 = fermée, 1 = grande ouverte sur la Salle.
    let openProgress: Double
    let onArtifactTap: (DoorArtifactKey) -> Void

    /// Le repère de conception, hérité des maquettes.
    private static let design = CGSize(width: 390, height: 404)

    /// Centre vertical et rayon de monture de chaque médaillon, de bas en haut.
    private static let seats: [(key: DoorArtifactKey, y: CGFloat, r: CGFloat)] = [
        (.memoire, 324, 24),
        (.eventail, 262, 20),
        (.coeur, 202, 20),
        (.horizons, 142, 20),
        (.promesse, 86, 17),
    ]

    /// Les segments du conduit, de bas en haut : un par artéfact, puis la
    /// couronne vers la clé de voûte.
    private static let conduits: [(y: CGFloat, h: CGFloat)] = [
        (350, 22), (284, 14), (224, 16), (164, 16), (105, 15), (44, 23),
    ]

    var body: some View {
        GeometryReader { proxy in
            let s = proxy.size.width / Self.design.width

            ZStack(alignment: .topLeading) {
                DoorCanvas(door: door, isOpen: isOpen, openProgress: openProgress)

                // Les médaillons s'effacent avant que les vantaux ne bougent :
                // la serrure n'a plus de raison d'être une fois la porte
                // gagnée, et les laisser voler avec les battants ferait lire
                // la scène comme un décor qui se démonte.
                ForEach(Array(Self.seats.enumerated()), id: \.element.key) { index, seat in
                    medallion(seat, index: index, scale: s)
                }
                .opacity(1 - min(1, openProgress * 2.5))
                .allowsHitTesting(openProgress == 0)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "La porte de CinéMatch, \(door.litCount) artéfacts sur 5", bundle: .app))
    }

    /// Le prochain à viser : le premier médaillon éteint en montant. C'est un
    /// index d'artéfact, jamais un compte — rien n'impose l'ordre d'allumage.
    private var nextIndex: Int? {
        Self.seats.firstIndex { door.artifact($0.key)?.done != true }
    }

    private func medallion(
        _ seat: (key: DoorArtifactKey, y: CGFloat, r: CGFloat), index: Int, scale s: CGFloat
    ) -> some View {
        let lit = door.artifact(seat.key)?.done == true
        let isNext = !isOpen && index == nextIndex
        // La monture occupe 70 % du PNG : l'image déborde du rayon voulu.
        let side = seat.r * 2.9 * s

        return Button {
            onArtifactTap(seat.key)
        } label: {
            Image(seat.key.assetName)
                .resizable()
                .scaledToFit()
                .frame(width: side, height: side)
                // La grammaire des badges verrouillés : même silhouette,
                // désaturée et assombrie en pierre tant que la condition tient.
                .saturation(lit ? 1 : 0)
                .brightness(lit ? 0 : -0.42)
                .shadow(color: Color(hex: seat.key.halo).opacity(lit ? 0.45 : 0), radius: seat.r * 0.55 * s)
                .overlay(alignment: .bottom) {
                    if isNext {
                        // Le prochain à viser : le point de lumière, seul emploi
                        // de l'accent sur cet écran, au sens « à faire » qu'il a
                        // partout ailleurs.
                        Rectangle()
                            .fill(Ink.light)
                            .frame(width: 4, height: 4)
                            .offset(y: 9 * s)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(PressableScaleStyle(scale: 0.92))
        .position(x: 195 * s, y: seat.y * s)
        .accessibilityLabel(seat.key.displayName)
        .accessibilityValue(
            lit
                ? String(localized: "allumé", bundle: .app)
                : String(localized: "éteint", bundle: .app)
        )
        .accessibilityHint(String(localized: "Toucher pour voir comment le gagner", bundle: .app))
    }
}

/// Le trait de la porte, hors médaillons : tout ce qui ne change qu'avec la
/// jauge est dessiné d'un seul tenant.
private struct DoorCanvas: View, Animatable {
    let door: DoorState
    let isOpen: Bool
    /// L'avancement de l'ouverture, **interpolé image par image**.
    ///
    /// C'est la raison d'être de la conformité à `Animatable` : un `Canvas` ne
    /// s'anime pas tout seul. SwiftUI interpole les modificateurs animables —
    /// opacité, décalage, échelle — mais jamais la lecture d'une variable dans
    /// un corps de vue : le dessin se referait une seule fois, à l'arrivée, et
    /// la porte sauterait ouverte sans qu'on voie rien. Déclarer la valeur
    /// animable fait rejouer le corps à chaque image, avec la valeur
    /// intermédiaire — et les battants tournent pour de bon.
    var openProgress: Double

    var animatableData: Double {
        get { openProgress }
        set { openProgress = newValue }
    }

    /// Le segment sous chaque médaillon suit **son** artéfact, la couronne ne
    /// vient qu'avec l'ouverture : la lumière du conduit raconte exactement ce
    /// que racontent les médaillons juste au-dessus, quel que soit l'ordre.
    private var litSegments: [Bool] {
        DoorArtifactKey.allCases.map { door.artifact($0)?.done == true } + [isOpen]
    }

    var body: some View {
        Canvas { context, size in
            let s = size.width / 390

            func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, r: CGFloat = 0) -> Path {
                Path(
                    roundedRect: CGRect(x: x * s, y: y * s, width: w * s, height: h * s),
                    cornerRadius: r * s
                )
            }
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: x * s, y: y * s)
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
            func lerp(_ a: CGPoint, _ b: CGPoint, _ t: Double) -> CGPoint {
                CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
            }

            let bronze = Gradient(colors: [
                Color(hex: 0xD7AC6C), Color(hex: 0xA97C44),
                Color(hex: 0x6E4E26), Color(hex: 0x4A3418),
            ])
            let bronzeDeep = Gradient(colors: [
                Color(hex: 0x8A6437), Color(hex: 0x5E4223), Color(hex: 0x3B2A14),
            ])
            let gold = Gradient(colors: [
                Color(hex: 0xF6EACB), Color(hex: 0xE3C070),
                Color(hex: 0xA87C36), Color(hex: 0x6B4E1F),
            ])
            let enamel = Gradient(colors: [Color(hex: 0x17202C), Color(hex: 0x0B1119)])
            let filet = Color(hex: 0xE0B24A)

            func fillBronze(_ path: Path, deep: Bool = false, from: CGPoint, to: CGPoint) {
                context.fill(
                    path,
                    with: .linearGradient(deep ? bronzeDeep : bronze, startPoint: from, endPoint: to)
                )
            }

            // L'ambiance : une lueur de nuit derrière la porte, rien de plus.
            context.fill(
                Path(ellipseIn: CGRect(x: -20 * s, y: 20 * s, width: 430 * s, height: 500 * s)),
                with: .radialGradient(
                    Gradient(colors: [Color(hex: 0x18222E).opacity(0.5), Ink.ground.opacity(0)]),
                    center: point(195, 214), startRadius: 0, endRadius: 250 * s
                )
            )

            // Le fronton en gradins.
            fillBronze(rect(142, 20, 106, 9), deep: true, from: point(142, 20), to: point(142, 29))
            fillBronze(rect(116, 29, 158, 9), deep: true, from: point(116, 29), to: point(116, 38))
            fillBronze(rect(94, 38, 202, 12), from: point(94, 38), to: point(296, 50))

            // Le chambranle et son liseré.
            fillBronze(rect(86, 50, 218, 334, r: 2), from: point(86, 50), to: point(304, 384))
            context.fill(rect(98, 62, 194, 314), with: .color(Color(hex: 0x070C12)))
            context.stroke(
                rect(99.5, 63.5, 191, 311),
                with: .color(Color(hex: 0xF6EACB).opacity(0.28)), lineWidth: 1 * s
            )

            // La Salle, au-delà du seuil. Dessinée avant les vantaux : c'est
            // eux qui la découvrent en s'écartant, elle n'apparaît pas.
            let p = max(0, min(1, openProgress))
            if p > 0.001 {
                context.fill(
                    rect(100, 62, 190, 314),
                    with: .linearGradient(
                        Gradient(colors: [Color(hex: 0x0B1322), Color(hex: 0x05080D)]),
                        startPoint: point(100, 62), endPoint: point(100, 376)
                    )
                )
                // L'écran, au fond, et sa lueur.
                context.fill(
                    Path(ellipseIn: CGRect(x: 100 * s, y: 88 * s, width: 190 * s, height: 132 * s)),
                    with: .radialGradient(
                        Gradient(colors: [
                            Color(hex: 0xF4FDFF).opacity(0.30), Color(hex: 0xF4FDFF).opacity(0),
                        ]),
                        center: point(195, 154), startRadius: 0, endRadius: 95 * s
                    )
                )
                context.fill(rect(157, 134, 76, 34), with: .color(Color(hex: 0xF4FDFF)))
                var floor = Path()
                floor.move(to: point(100, 226))
                floor.addLine(to: point(290, 226))
                context.stroke(floor, with: .color(Color(hex: 0xC6D3DF).opacity(0.10)), lineWidth: 1 * s)

                // L'allée centrale et les rangées de fauteuils.
                context.fill(
                    quad(point(176, 236), point(214, 236), point(240, 376), point(150, 376)),
                    with: .linearGradient(
                        Gradient(colors: [
                            Color(hex: 0x22304A).opacity(0.9), Color(hex: 0x0C1119),
                        ]),
                        startPoint: point(176, 236), endPoint: point(176, 376)
                    )
                )
                let rows: [(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)] = [
                    (106, 244, 63, 7, 221), (106, 264, 60, 9, 224),
                    (106, 289, 55, 11, 229), (106, 319, 50, 13, 234),
                    (106, 352, 44, 15, 240),
                ]
                for (x, y, w, h, rx) in rows {
                    context.fill(rect(x, y, w, h), with: .color(Color(hex: 0x04070C)))
                    context.fill(rect(rx, y, w, h), with: .color(Color(hex: 0x04070C)))
                }

                // Les cinq artéfacts devenus lumières d'allée : la porte garde
                // ses teintes une fois franchie.
                let aisle: [(CGFloat, DoorArtifactKey)] = [
                    (366, .memoire), (336, .eventail), (306, .coeur),
                    (279, .horizons), (254, .promesse),
                ]
                for (y, key) in aisle {
                    let tint = Color(hex: key.hue)
                    context.fill(
                        Path(ellipseIn: CGRect(x: 188 * s, y: (y - 7) * s, width: 14 * s, height: 14 * s)),
                        with: .color(tint.opacity(0.28))
                    )
                    context.fill(
                        Path(ellipseIn: CGRect(x: 192.8 * s, y: (y - 2.2) * s, width: 4.4 * s, height: 4.4 * s)),
                        with: .color(tint)
                    )
                }
            }

            // Les deux vantaux émaillés. Fermés, deux rectangles ; ouverts,
            // deux trapèzes vus de biais — c'est l'interpolation entre les deux
            // qui fait le battant, sans transformation 3D.
            let leftTR = lerp(point(193, 62), point(122, 74), p)
            let leftBR = lerp(point(193, 376), point(122, 366), p)
            let rightTL = lerp(point(197, 62), point(268, 74), p)
            let rightBL = lerp(point(197, 376), point(268, 366), p)
            let leftLeaf = quad(point(98, 62), leftTR, leftBR, point(98, 376))
            let rightLeaf = quad(rightTL, point(292, 62), point(292, 376), rightBL)

            context.fill(
                leftLeaf,
                with: .linearGradient(enamel, startPoint: point(98, 62), endPoint: point(98, 376))
            )
            context.fill(
                rightLeaf,
                with: .linearGradient(enamel, startPoint: point(197, 62), endPoint: point(197, 376))
            )
            if p < 0.02 {
                context.fill(rect(193, 62, 4, 314), with: .color(Color(hex: 0x05080D)))
            }
            // Le liseré d'or suit le battant : tracé sur le trapèze courant, il
            // reste juste à toutes les étapes de l'ouverture.
            context.stroke(leftLeaf, with: .color(filet.opacity(0.28)), lineWidth: 1 * s)
            context.stroke(rightLeaf, with: .color(filet.opacity(0.28)), lineWidth: 1 * s)

            // Les filets intérieurs et les carrés d'angle, propres à la porte
            // fermée : ils s'effacent dès qu'elle bouge plutôt que de glisser
            // de travers sur un battant en train de tourner.
            let stillShut = 1 - min(1, p * 2.5)
            for x in [104.0, 203.0] where stillShut > 0.01 {
                context.stroke(rect(x, 68, 83, 302), with: .color(filet.opacity(0.28 * stillShut)), lineWidth: 1 * s)
                context.stroke(rect(x + 6, 74, 71, 290), with: .color(filet.opacity(0.13 * stillShut)), lineWidth: 1 * s)
                for (cx, cy) in [(x - 1.5, 66.5), (x + 80.5, 66.5), (x - 1.5, 368.5), (x + 80.5, 368.5)] {
                    context.fill(rect(cx, cy, 3, 3), with: .color(filet.opacity(0.55 * stillShut)))
                }
            }

            // La lumière du seuil, à l'instant qui précède l'ouverture.
            if isOpen, p < 0.02 {
                context.fill(
                    rect(190, 62, 10, 314),
                    with: .linearGradient(
                        Gradient(stops: [
                            .init(color: Color(hex: 0xF7EFD9).opacity(0), location: 0),
                            .init(color: Color(hex: 0xF7EFD9).opacity(0.9), location: 0.5),
                            .init(color: Color(hex: 0xF7EFD9).opacity(0), location: 1),
                        ]),
                        startPoint: point(190, 219), endPoint: point(200, 219)
                    )
                )
            }

            // Les poignées, une par vantail, et les gonds côté chambranle :
            // c'est ce qui dit les deux battants.
            for x in [153.2, 229.2] where stillShut > 0.01 {
                for cy in [218.0, 290.0] {
                    let rosette = Path(ellipseIn: CGRect(
                        x: (x + 3.8 - 4.5) * s, y: (cy - 4.5) * s, width: 9 * s, height: 9 * s
                    ))
                    fillBronze(rosette, from: point(x - 1, cy - 5), to: point(x + 8, cy + 5))
                }
                let bar = rect(x, 214, 7.6, 80, r: 3.8)
                context.fill(bar, with: .linearGradient(gold, startPoint: point(x, 214), endPoint: point(x + 8, 294)))
                context.stroke(bar, with: .color(Color(hex: 0x05080D).opacity(0.8)), lineWidth: 0.8 * s)
                var highlight = Path()
                highlight.move(to: point(x + 2.2, 220))
                highlight.addLine(to: point(x + 2.2, 288))
                context.stroke(highlight, with: .color(Color(hex: 0xF6EACB).opacity(0.5)), lineWidth: 1 * s)
            }
            for x in [98.0, 285.0] {
                for y in [100.0, 211.0, 322.0] {
                    let hinge = rect(x, y, 7, 16, r: 1)
                    fillBronze(hinge, from: point(x, y), to: point(x + 7, y + 16))
                }
            }

            // Les rivets du chambranle.
            for y in stride(from: 76.0, through: 364.0, by: 36) {
                for x in [92.0, 298.0] {
                    context.fill(
                        Path(ellipseIn: CGRect(x: (x - 1.6) * s, y: (y - 1.6) * s, width: 3.2 * s, height: 3.2 * s)),
                        with: .color(Color(hex: 0xD7AC6C))
                    )
                }
            }
            for x in [112.0, 144.0, 246.0, 278.0] {
                context.fill(
                    Path(ellipseIn: CGRect(x: (x - 1.6) * s, y: 54.4 * s, width: 3.2 * s, height: 3.2 * s)),
                    with: .color(Color(hex: 0xD7AC6C))
                )
            }

            // Le montant central, la serrure. Elle disparaît avec l'ouverture :
            // une serrure n'a plus de sens sur une porte qu'on a gagnée.
            if stillShut > 0.01 {
                context.drawLayer { inner in
                    inner.opacity = stillShut
                    inner.fill(
                        rect(175, 12, 40, 364),
                        with: .linearGradient(
                            bronzeDeep, startPoint: point(175, 12), endPoint: point(175, 376)
                        )
                    )
                    inner.stroke(
                        rect(176, 13, 38, 362),
                        with: .color(Color(hex: 0xF6EACB).opacity(0.2)), lineWidth: 1 * s
                    )
                    inner.fill(rect(191, 16, 8, 356), with: .color(Color(hex: 0x070C12)))

                    // Le conduit, segment par segment.
                    let lit = litSegments
                    for (index, segment) in DoorSceneView.conduitSegments.enumerated()
                    where index < lit.count && lit[index] {
                        inner.fill(
                            rect(192.7, segment.y, 4.6, segment.h),
                            with: .color(Color(hex: 0xF2E6C4).opacity(0.9))
                        )
                    }
                }
            }

            // La clé de voûte : le C de la Salle, embrasé au cinquième.
            if isOpen {
                context.fill(
                    Path(ellipseIn: CGRect(x: 180 * s, y: 20 * s, width: 30 * s, height: 30 * s)),
                    with: .radialGradient(
                        Gradient(colors: [Color(hex: 0xFFD98A).opacity(0.55), Color(hex: 0xFFD98A).opacity(0)]),
                        center: point(195, 35), startRadius: 0, endRadius: 15 * s
                    )
                )
            }
            var crown = Path()
            crown.addArc(
                center: point(195, 35), radius: 6.8 * s,
                startAngle: .degrees(-42), endAngle: .degrees(42), clockwise: true
            )
            context.stroke(
                crown,
                with: .color(isOpen ? Color(hex: 0xF6EACB) : Color(hex: 0xD7AC6C).opacity(0.55)),
                style: StrokeStyle(lineWidth: 1.8 * s, lineCap: .round)
            )

            // Le sol : la plinthe, le jour sous la porte, l'ombre portée.
            fillBronze(rect(86, 376, 218, 8), deep: true, from: point(86, 376), to: point(86, 384))
            if door.litCount > 0 {
                context.fill(
                    rect(100, 385, 190, 4),
                    with: .linearGradient(
                        Gradient(colors: [
                            Color(hex: 0xF7EFD9).opacity(0.16 + 0.12 * Double(door.litCount)),
                            Color(hex: 0xF7EFD9).opacity(0),
                        ]),
                        startPoint: point(100, 385), endPoint: point(100, 389)
                    )
                )
            }
            context.fill(
                Path(ellipseIn: CGRect(x: 45 * s, y: 385 * s, width: 300 * s, height: 14 * s)),
                with: .color(Color(hex: 0x05080D).opacity(0.8))
            )

            // La lumière qui déborde sur le sol, une fois le seuil franchi.
            if p > 0.01 {
                context.fill(
                    quad(point(108, 384), point(282, 384), point(322, 460), point(68, 460)),
                    with: .linearGradient(
                        Gradient(colors: [
                            Color(hex: 0xE8F4FF).opacity(0.28 * p),
                            Color(hex: 0xE8F4FF).opacity(0),
                        ]),
                        startPoint: point(195, 384), endPoint: point(195, 460)
                    )
                )
            }
        }
    }
}

private extension DoorSceneView {
    /// Exposés au canvas, qui ne voit pas les membres privés de la scène.
    static var conduitSegments: [(y: CGFloat, h: CGFloat)] { conduits }
}

// MARK: - La feuille de détail

/// Ce qu'un artéfact demande, et où le gagner. Toucher un médaillon ouvre sa
/// feuille : la condition, la progression réelle, une phrase qui dit la
/// conséquence, et un bouton qui renvoie exactement là où le manque se comble.
private struct DoorArtifactSheet: View {
    let artifactKey: DoorArtifactKey
    let door: DoorState
    let lovedCount: Int
    let onAction: () -> Void

    private var artifact: DoorArtifact? { door.artifact(artifactKey) }

    /// Le compte montré : pour le Cœur, la bibliothèque locale est plus
    /// fraîche que la dernière réponse du serveur.
    private var current: Int {
        artifactKey == .coeur
            ? max(lovedCount, artifact?.current ?? 0)
            : artifact?.current ?? 0
    }

    private var target: Int { artifact?.target ?? 0 }
    private var isDone: Bool { artifact?.done == true || (target > 0 && current >= target) }

    private var rank: Int {
        (DoorArtifactKey.allCases.firstIndex(of: artifactKey) ?? 0) + 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 16) {
                Image(artifactKey.assetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)
                    .saturation(isDone ? 1 : 0)
                    .brightness(isDone ? 0 : -0.42)
                    .shadow(color: Color(hex: artifactKey.halo).opacity(isDone ? 0.45 : 0), radius: 10)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Artéfact \(rank) sur 5", bundle: .app)
                        .planLabel()
                        .foregroundStyle(Color(hex: artifactKey.hue))
                    Text(artifactKey.displayName)
                        .planTitle(22)
                        .foregroundStyle(Ink.ink)
                }

                Spacer(minLength: 0)
            }

            Text(artifactKey.condition(in: door))
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Ink.ink)
                .padding(.top, 22)

            HStack(spacing: 12) {
                tintedRule
                Text(progressText)
                    .planLabel()
                    .monospacedDigit()
                    .foregroundStyle(Ink.ink3)
            }
            .padding(.top, 12)

            Text(artifactKey.consequence)
                .font(.system(size: 13.5))
                .foregroundStyle(Ink.ink2)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)

            Spacer(minLength: 16)

            PlanButton(title: artifactKey.actionTitle, action: onAction)
        }
        .padding(.horizontal, Metrics.margin)
        .padding(.top, 22)
        .padding(.bottom, Metrics.margin)
        .presentationBackground(Color(hex: 0x0D141D))
    }

    /// La jauge tracée de l'app, dans la teinte de l'artéfact : la mesure se
    /// lit, elle ne se remplit pas — seule la couleur de données change.
    private var tintedRule: some View {
        let fraction = target > 0 ? min(1, max(0, Double(current) / Double(target))) : 0
        let tint = Color(hex: artifactKey.hue)

        return GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Ink.rule)
                    .frame(height: 1)
                Rectangle()
                    .fill(tint)
                    .frame(width: max(1, proxy.size.width * fraction), height: 1)
                if fraction > 0, fraction < 1 {
                    Rectangle()
                        .fill(tint)
                        .frame(width: 1, height: 5)
                        .offset(x: max(0, proxy.size.width * fraction - 0.5))
                }
            }
            .frame(height: 5)
        }
        .frame(height: 5)
        .accessibilityHidden(true)
    }

    private var progressText: String {
        if artifactKey == .horizons {
            let h = door.horizons
            return String(
                localized: "\(min(h.decades, h.decadesTarget)) sur \(h.decadesTarget) · \(min(h.countries, h.countriesTarget)) sur \(h.countriesTarget)",
                bundle: .app
            )
        }
        return String(localized: "\(min(current, target)) sur \(target)", bundle: .app)
    }
}

// MARK: - Ce que chaque artéfact raconte

extension DoorArtifactKey: Identifiable {
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .memoire: String(localized: "La Mémoire", bundle: .app)
        case .eventail: String(localized: "L'Éventail", bundle: .app)
        case .coeur: String(localized: "Le Cœur", bundle: .app)
        case .horizons: String(localized: "Les Horizons", bundle: .app)
        case .promesse: String(localized: "La Promesse", bundle: .app)
        }
    }

    /// La condition, avec les seuils que le serveur mesure vraiment.
    func condition(in door: DoorState) -> String {
        let target = door.artifact(self)?.target ?? 0
        switch self {
        case .memoire:
            return String(localized: "\(target) films dans ta galerie", bundle: .app)
        case .eventail:
            return String(localized: "\(target) genres explorés", bundle: .app)
        case .coeur:
            return String(localized: "Aimer \(target) films de ta galerie", bundle: .app)
        case .horizons:
            return String(
                localized: "\(door.horizons.decadesTarget) décennies, \(door.horizons.countriesTarget) pays",
                bundle: .app
            )
        case .promesse:
            return String(localized: "\(target) films dans ta watchlist", bundle: .app)
        }
    }

    /// La conséquence — jamais le mécanisme.
    var consequence: String {
        switch self {
        case .memoire:
            String(localized: "La base de ton profil : chaque film vu le précise. Sous ce plancher, on devinerait au lieu de savoir.", bundle: .app)
        case .eventail:
            String(localized: "Ton goût se lit par contraste : plusieurs familles vues, et on sait aussi ce que tu fuis.", bundle: .app)
        case .coeur:
            String(localized: "Tes films aimés nous disent ce que tu veux revivre, pas seulement ce que tu as vu. C'est par eux qu'on choisira des films qui te ressemblent.", bundle: .app)
        case .horizons:
            String(localized: "Un profil qui a voyagé nous permet d'oser au-delà du récent et d'Hollywood.", bundle: .app)
        case .promesse:
            String(localized: "Tes envies comptent : ta watchlist devient candidate, en priorité quand on s'en approche.", bundle: .app)
        }
    }

    /// Là où le manque se comble.
    var actionTitle: String {
        switch self {
        case .coeur: String(localized: "Aimer des films de ma galerie", bundle: .app)
        default: String(localized: "Ouvrir Découvrir", bundle: .app)
        }
    }
}

#Preview("La porte") {
    ZStack {
        Ink.ground.ignoresSafeArea()
        CineMatchGateView(
            door: .initial,
            isMeasured: false,
            lovedCount: 0,
            onProfileTap: {},
            onDiscover: {},
            onLovePicker: {},
            onEnter: {}
        )
    }
    .environmentObject(UserProfileStore())
    .environmentObject(SocialStore())
}
