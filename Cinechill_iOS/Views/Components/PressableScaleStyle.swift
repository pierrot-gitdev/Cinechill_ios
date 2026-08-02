//
//  PressableScaleStyle.swift
//  Cinechill_iOS
//

import SwiftUI

/// Style de bouton générique : léger effet d'échelle au press, pour qu'un tap se sente
/// physique. Utilisé partout où un bouton a un fond personnalisé (pilule dégradée, chip…)
/// et ne peut donc pas passer par un `.buttonStyle` système.
struct PressableScaleStyle: ButtonStyle {
    var scale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
