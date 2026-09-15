//
//  OnboardingCartouche.swift
//  Cinechill_iOS
//

import SwiftUI

/// Le cartouche — **le seul objet neuf de la prise en main**.
///
/// Sur un plan d'architecte, le cartouche est le bloc en bas de la planche : il
/// nomme le dessin. Ici il nomme l'écran présenté et dit à quoi il sert.
///
/// Il ne se pose plus sur l'écran : `MainTabView` réduit l'application en
/// vignette au-dessus de lui, et il occupe la place libérée, sur le fond de la
/// page. La rupture vient de cet écart, pas d'une carte ni d'un voile.
///
/// Le texte change par fondu, sans déplacement : une voix remplace une voix.
/// La hauteur suit le contenu et la vignette s'y ajuste.
///
/// Les trois gestes de « Découvrir » ne s'écrivent plus ici : la carte du deck
/// les joue elle-même dans la vignette (`SwipeDeckView.playTourDemo`).
struct OnboardingCartouche: View {
    let step: OnboardingTour.Step
    let counter: String
    let progress: Double
    let onNext: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            VStack(alignment: .leading, spacing: 0) {
                Text(step.title)
                    .planTitle(22)
                    .foregroundStyle(Ink.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Text(step.detail)
                    .font(.system(size: 13.5))
                    .foregroundStyle(Ink.ink2)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 12)
            .id(step)
            .transition(.opacity)

            PlanButton(
                title: step.isLast
                    ? String(localized: "Commencer", bundle: .app)
                    : String(localized: "Suivant", bundle: .app),
                height: Metrics.control,
                action: onNext
            )
            .padding(.top, 18)

            PlanProgressRule(fraction: progress)
                .padding(.top, 14)
                .animation(Metrics.unfold, value: progress)
        }
        .padding(.horizontal, Metrics.margin)
        .padding(.top, 4)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Ink.ground)
        .animation(Metrics.shift, value: step)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Le rang et la sortie

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(counter)
                .planLabel()
                .monospacedDigit()
                .foregroundStyle(Ink.ink2)

            Spacer(minLength: 12)

            // « Passer » disparaît à la dernière étape : il n'y a plus rien à
            // passer, et le bouton plein dit déjà la sortie.
            if !step.isLast {
                Button(action: onSkip) {
                    Text("Passer", bundle: .app)
                        .planLabel()
                        .foregroundStyle(Ink.ink2)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle().inset(by: -12))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Passer la prise en main", bundle: .app))
            }
        }
        .frame(minHeight: 40)
    }
}

#Preview("Le cartouche") {
    ZStack(alignment: .bottom) {
        Ink.ground.ignoresSafeArea()
        OnboardingCartouche(
            step: .decouvrir,
            counter: "4 / 7",
            progress: 4.0 / 7,
            onNext: {},
            onSkip: {}
        )
    }
}
