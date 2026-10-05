//
//  PressableScaleStyle.swift
//  Cinechill_iOS
//

import SwiftUI

/// Style de bouton générique : léger effet d'échelle au press, pour qu'un tap se sente
/// physique. Utilisé partout où un bouton a un fond personnalisé (pilule dégradée, chip…)
/// et ne peut donc pas passer par un `.buttonStyle` système.
///
/// Ressort critiquement amorti : un tap n'a aucun élan à restituer, le rebond
/// d'autrefois (amortissement 0,6) se lisait comme une animation plutôt que
/// comme un retour. Avec « Réduire les animations », l'échelle cède la place à
/// une atténuation : le retour reste, le mouvement part.
struct PressableScaleStyle: ButtonStyle {
    var scale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        PressedLabel(configuration: configuration, scale: scale)
    }

    private struct PressedLabel: View {
        let configuration: ButtonStyleConfiguration
        let scale: CGFloat
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            let pressed = configuration.isPressed
            configuration.label
                .scaleEffect(pressed && !reduceMotion ? scale : 1)
                .opacity(pressed && reduceMotion ? 0.7 : 1)
                .animation(.spring(response: 0.2, dampingFraction: 1), value: pressed)
        }
    }
}
