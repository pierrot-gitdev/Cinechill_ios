//
//  GradientSpinner.swift
//  Cinechill_iOS
//

import SwiftUI

/// Compatibilité — l'anneau dégradé a été remplacé par ``CinechillSpinner``, qui porte le logo.
///
/// Les appels du projet ont été migrés ; ce type ne reste que comme filet de sécurité au cas où
/// un appel aurait été manqué. `lineWidth` et `colors` ne sont plus lus : le spinner a désormais
/// ses propres couleurs de marque, c'est tout l'intérêt d'avoir un indicateur unique. Le fichier
/// peut être supprimé du projet une fois qu'on a vérifié qu'il ne sert plus.
struct GradientSpinner: View {
    var size: CGFloat = 20
    var lineWidth: CGFloat = 2.5
    var colors: [Color] = [.white, .white.opacity(0.05)]

    var body: some View {
        // Le blanc signalait un usage sur aplat coloré (bouton dégradé) : on garde ce contrat.
        CinechillSpinner(size: size + 2, tint: colors.first == .white ? .onAccent : .brand)
    }
}

#Preview {
    GradientSpinner(size: 32)
}
