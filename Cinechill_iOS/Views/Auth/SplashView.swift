//
//  SplashView.swift
//  Cinechill_iOS
//

import SwiftUI

/// L'ouverture de l'app : le faisceau entre par la droite, allume la cabine, traverse la salle,
/// embrase l'écran — puis la lumière court tout autour du mur et dessine le C.
///
/// Ce n'est pas un indicateur de chargement : la séquence se joue **en entier**, même si Firebase
/// a déjà répondu. C'est un choix, pas un oubli — le splash est le seul moment où la marque a
/// l'écran pour elle. Les données, elles, se chargent en tâche de fond pendant ce temps (les
/// stores démarrent dans `Cinechill_iOSApp`), si bien que l'animation ne coûte du temps que
/// lorsqu'elle est plus lente que le réseau.
///
/// `onFinished` est appelé à la fin de la séquence ; c'est l'appelant qui décide de passer la
/// main, une fois que l'animation **et** l'auth sont prêtes.
struct SplashView: View {
    var onFinished: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var bladeOffset: CGFloat = 1
    @State private var bladeOpacity: Double = 0
    @State private var boothGlow: Double = 0
    @State private var lightReach: CGFloat = 0
    @State private var rimTrim: Double = 0
    @State private var wallReveal: Double = 0
    @State private var seatsOpacity: Double = 0
    @State private var markScale: CGFloat = 0.94
    @State private var titleOpacity: Double = 0
    @State private var titleOffset: CGFloat = 10

    private let markSize: CGFloat = 216

    var body: some View {
        ZStack {
            background

            VStack(spacing: 34) {
                ZStack {
                    halo
                    incomingBlade
                    CinechillMark(
                        wallReveal: wallReveal,
                        rimTrim: rimTrim,
                        lightReach: lightReach,
                        seatsOpacity: seatsOpacity,
                        boothGlow: boothGlow
                    )
                    .frame(width: markSize, height: markSize)
                }
                .frame(width: markSize, height: markSize)
                .scaleEffect(markScale)

                Text(verbatim: "Cinechill")
                    .font(.system(size: 27, weight: .light))
                    .kerning(-0.76)
                    .tracking(1.6)
                    .foregroundStyle(.white)
                    .opacity(titleOpacity)
                    .offset(y: titleOffset)
            }
        }
        .task { await run() }
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
                center: UnitPoint(x: 0.5, y: 0.42), startRadius: 20, endRadius: 420
            )
        }
        .ignoresSafeArea()
    }

    /// Lueur froide qui monte derrière le mark à mesure que la salle s'éclaire.
    private var halo: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [CinechillPalette.light.opacity(0.22), .clear],
                    center: .center, startRadius: 6, endRadius: markSize * 0.78
                )
            )
            .frame(width: markSize * 1.7, height: markSize * 1.7)
            .opacity(wallReveal)
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
        .opacity(bladeOpacity)
    }

    // MARK: Séquence

    private func run() async {
        guard !reduceMotion else {
            // Même destination, sans le voyage.
            withAnimation(.easeOut(duration: 0.3)) {
                boothGlow = 1; lightReach = 512; rimTrim = 1
                wallReveal = 1; seatsOpacity = 1; markScale = 1
                titleOpacity = 1; titleOffset = 0
            }
            await sleep(700)
            onFinished()
            return
        }

        // 1 — la lame arrive de la droite.
        withAnimation(.easeOut(duration: 0.16)) { bladeOpacity = 1 }
        withAnimation(.easeOut(duration: 0.46)) { bladeOffset = 0 }
        await sleep(430)

        // 2 — elle atteint la cabine, qui s'allume.
        withAnimation(.easeOut(duration: 0.20)) { boothGlow = 1 }
        withAnimation(.easeIn(duration: 0.35)) { bladeOpacity = 0.35 }
        await sleep(130)

        // 3 — la projection traverse la salle et embrase l'écran.
        withAnimation(.easeOut(duration: 0.55)) { lightReach = 340 }
        await sleep(300)

        // 4 — la lumière court autour du mur : c'est elle qui dessine le C.
        withAnimation(.easeInOut(duration: 0.70)) { rimTrim = 1 }
        withAnimation(.easeIn(duration: 0.75).delay(0.10)) { wallReveal = 1 }
        withAnimation(.easeOut(duration: 0.95)) { markScale = 1 }
        await sleep(540)

        // 5 — la salle se remplit.
        withAnimation(.easeOut(duration: 0.45)) { seatsOpacity = 1 }
        await sleep(230)

        // 6 — le nom.
        withAnimation(.easeOut(duration: 0.45)) {
            titleOpacity = 1
            titleOffset = 0
        }
        await sleep(430)

        onFinished()
    }

    private func sleep(_ milliseconds: UInt64) async {
        try? await Task.sleep(nanoseconds: milliseconds * 1_000_000)
    }
}

#Preview {
    SplashView()
}
