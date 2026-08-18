//
//  SwipeCompass.swift
//  Cinechill_iOS
//

import SwiftUI

/// Les trois issues d'une carte, et celle que le geste est en train de choisir.
///
/// **Un seul objet pour toute la direction.** La carte en portait trois qui
/// disaient la même chose : un bandeau au bord, un tampon dans un coin, et ces
/// repères-ci. Trois écritures, deux vocabulaires — le tampon annonçait « VU »
/// quand le repère annonçait « Galerie » — et un écran chargé au moment précis
/// où il faut décider vite. Ils sont réunis ici : le repère de la direction
/// engagée prend la teinte du verdict et s'enclenche au seuil, les deux autres
/// s'effacent. Le liseré de la carte reste, parce qu'il est d'un autre registre :
/// c'est la carte qui réagit, pas une quatrième étiquette.
///
/// Elle n'apparaît qu'au contact ou à l'arrivée sur l'écran, jamais en
/// permanence : la planche des gestes s'ouvre une fois dans une vie et le
/// cartouche de la visite guidée aussi, restait le trou entre les deux. Elle ne
/// demande aucun geste, ne recouvre pas la carte et part toute seule.
struct SwipeCompass: View {
    /// Le verdict que le geste en cours désigne, s'il y en a un.
    var engaged: SwipeVerdict?
    /// Avancement du geste vers son seuil, de 0 à 1.
    var intensity: Double = 0
    /// Le seuil est franchi : le verdict est acquis si le doigt se lève.
    var isArmed = false

    var body: some View {
        ZStack {
            marker(.up)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            marker(.left)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            marker(.right)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        }
        .padding(16)
        // Purement indicative : la carte porte déjà son indice d'accessibilité,
        // qui énonce les trois gestes.
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// La flèche est toujours du côté où le doigt doit partir : à gauche du mot
    /// pour un geste vers la gauche, à droite pour un geste vers la droite,
    /// au-dessus pour un geste vers le haut. C'est la position, avant la
    /// pointe, qui dit la direction.
    @ViewBuilder
    private func marker(_ direction: SwipeDirection) -> some View {
        let isEngaged = engaged == direction.verdict
        let glyph = SwipeArrowGlyph(direction: direction.arrow, side: 12)
        let word = Text(direction.destination).planLabel()

        Group {
            switch direction {
            case .up:
                VStack(spacing: 5) { glyph; word }
            case .left:
                HStack(spacing: 7) { glyph; word }
            case .right:
                HStack(spacing: 7) { word; glyph }
            }
        }
        .foregroundStyle(isEngaged ? direction.verdict.tint : direction.destinationTint)
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(
            Ink.ground.opacity(isEngaged ? 0.92 : 0.82),
            in: RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                .strokeBorder(borderTint(isEngaged: isEngaged, of: direction), lineWidth: 1)
        )
        // Le repère retenu grossit d'un cran au seuil : le doigt sent le déclic
        // en même temps que la vibration.
        .scaleEffect(isEngaged && isArmed ? 1.06 : 1)
        .animation(SwipeMotion.lock, value: isArmed)
        .opacity(presence(isEngaged: isEngaged))
    }

    private func borderTint(isEngaged: Bool, of direction: SwipeDirection) -> Color {
        guard isEngaged else { return Ink.rule }
        return direction.verdict.tint.opacity(isArmed ? 1 : 0.35 + 0.5 * intensity)
    }

    /// Les deux issues qu'on ne choisit pas s'effacent vite : passé le tiers du
    /// parcours, il ne reste que celle qu'on tient.
    private func presence(isEngaged: Bool) -> Double {
        guard engaged != nil else { return 1 }
        return isEngaged ? 1 : max(0, 1 - intensity / 0.4)
    }
}

#Preview("La boussole") {
    ZStack {
        Ink.ground.ignoresSafeArea()
        HStack(spacing: 20) {
            RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                .fill(Color(hex: 0x141C26))
                .overlay(SwipeCompass())
                .frame(width: 250, height: 400)

            RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                .fill(Color(hex: 0x141C26))
                .overlay(SwipeCompass(engaged: .seen, intensity: 1, isArmed: true))
                .frame(width: 250, height: 400)
        }
    }
}
