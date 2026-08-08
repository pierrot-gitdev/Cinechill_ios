//
//  SwipeMilestoneOverlay.swift
//  Cinechill_iOS
//

import SwiftUI

/// La célébration d'un palier — le seul moment où la feature se met en avant.
///
/// Elle n'a plus de carte : un chiffre en graisse 200, une ligne, et le voile de
/// la nuit. Le dégradé indigo→rose sur un nombre de 64 pt était l'effet le plus
/// appuyé de l'application, et il ne disait rien que le chiffre ne disait déjà.
struct SwipeMilestoneOverlay: View {
    let count: Int

    var body: some View {
        VStack(spacing: 0) {
            Text("\(count)")
                .planTitle(64)
                .monospacedDigit()
                .foregroundStyle(Ink.ink)

            Text("films ajoutés")
                .planLabel()
                .foregroundStyle(Ink.light)
                .padding(.top, 10)

            Text("Votre galerie s'étoffe, et vos suggestions avec elle.")
                .font(.system(size: 13))
                .foregroundStyle(Ink.ink2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 16)
        }
        .padding(.horizontal, 34)
        .padding(.vertical, 32)
        .frame(maxWidth: 300)
        .background(
            Ink.ground.opacity(0.94),
            in: RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                .strokeBorder(Ink.ruleSet, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(count) films ajoutés à votre galerie")
    }
}

#Preview {
    ZStack {
        Ink.ground.ignoresSafeArea()
        SwipeMilestoneOverlay(count: 25)
    }
}
