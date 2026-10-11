//
//  Haptics.swift
//  Cinechill_iOS
//

import UIKit

/// Retours haptiques, regroupés pour que le deck de swipe et la barre d'onglets
/// parlent le même langage tactile.
@MainActor
enum Haptics {
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle, intensity: CGFloat = 1) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred(intensity: intensity)
    }

    /// Réservé au geste : le tic du deck quand une carte tirée repasse sous
    /// son seuil. Un toucher n'en reçoit pas, l'écran y répond déjà ; Pierre a
    /// écarté la vibration à chaque appui (5 oct. puis 11 oct. 2026).
    static func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// Une saisie refusée. Une seule fois par soumission ratée, jamais une par
    /// champ : trois vibrations d'affilée se lisent comme une panne.
    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}
