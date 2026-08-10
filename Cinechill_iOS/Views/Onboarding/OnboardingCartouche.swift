//
//  OnboardingCartouche.swift
//  Cinechill_iOS
//

import SwiftUI

/// Le cartouche — **le seul objet neuf de la prise en main**.
///
/// Sur un plan d'architecte, le cartouche est le bloc en bas de la planche : il
/// nomme le dessin et le date. Ici il fait exactement ça — il nomme l'écran
/// qu'on a sous les yeux et dit à quoi il sert.
///
/// Il se pose sur le bas du contenu, **au-dessus de la barre d'onglets** qui
/// reste visible : c'est elle qui montre où l'on se trouve, et sa lampe se
/// déplace à chaque étape. Le recouvrir reviendrait à supprimer le seul repère
/// que la visite a à enseigner.
///
/// Rien ici n'est dessiné pour l'occasion : le filet, le titre, le niveau de
/// service, l'action pleine et la mesure sont ceux de `CinechillDesign`.
struct OnboardingCartouche: View {
    let step: OnboardingTour.Step
    let counter: String
    let progress: Double
    let onNext: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PlanRail()

            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.top, 14)

                Text(step.title)
                    .planTitle(22)
                    .foregroundStyle(Ink.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 16)

                Text(step.detail)
                    .font(.system(size: 13.5))
                    .foregroundStyle(Ink.ink2)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 11)

                if step.showsGestures {
                    gestures.padding(.top, 18)
                }

                PlanButton(
                    title: step.isLast
                        ? String(localized: "Commencer", bundle: .app)
                        : String(localized: "Suivant", bundle: .app),
                    height: Metrics.control,
                    action: onNext
                )
                .padding(.top, 20)

                PlanProgressRule(fraction: progress)
                    .padding(.top, 16)
                    .animation(Metrics.unfold, value: progress)
            }
            .padding(.horizontal, Metrics.margin)
            .padding(.bottom, 20)
        }
        // Pleine largeur, explicitement : posé en surcouche, le cartouche ne
        // prendrait sinon que la largeur de son plus long mot.
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Ink.ground)
        // Le texte change par fondu, jamais par glissement : une voix remplace
        // une voix, la plaque ne bouge pas.
        .animation(Metrics.shift, value: step)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Le rang et la sortie

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(counter)
                .planLabel()
                .monospacedDigit()
                .foregroundStyle(Ink.ink3)

            Spacer(minLength: 12)

            // « Passer » disparaît à la dernière étape : il n'y a plus rien à
            // passer, et le bouton plein dit déjà la sortie.
            if !step.isLast {
                Button(action: onSkip) {
                    Text("Passer", bundle: .app)
                        .planLabel()
                        .foregroundStyle(Ink.ink3)
                        .contentShape(Rectangle().inset(by: -12))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Passer la prise en main", bundle: .app))
            }
        }
    }

    // MARK: - Les trois gestes

    /// Écrits, jamais demandés. Les trois directions du deck sont la seule chose
    /// de l'application que rien à l'écran ne laisse deviner — d'où cette
    /// exception à la règle « un titre, deux lignes, rien d'autre ».
    ///
    /// Le vocabulaire est celui du deck lui-même : la même flèche, le même mot
    /// de destination. C'est cette égalité qui fait qu'on n'a le geste à
    /// apprendre qu'une fois.
    private var gestures: some View {
        VStack(spacing: 0) {
            PlanEdge()
            row(.right, outcome: String(localized: "Il rejoint votre galerie", bundle: .app))
            PlanEdge()
            row(.left, outcome: String(localized: "Il reviendra plus tard", bundle: .app))
            PlanEdge()
            row(.up, outcome: String(localized: "Il part en watchlist", bundle: .app))
            PlanEdge()
        }
    }

    private func row(_ direction: SwipeDirection, outcome: String) -> some View {
        HStack(spacing: 11) {
            SwipeArrowGlyph(direction: direction.arrow, side: 13)
                .foregroundStyle(Ink.ink2)

            Text(direction.verdict.label)
                .planLabel()
                .foregroundStyle(Ink.ink)

            Spacer(minLength: 10)

            Text(outcome)
                .font(.system(size: 12))
                .foregroundStyle(Ink.ink2)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(height: 34)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: "\(direction.verdict.label). \(outcome)"))
    }
}

/// Le voile de la prise en main.
///
/// Un aplat de nuit posé sur le contenu, sous le cartouche. Il n'a qu'un rôle :
/// rendre **lisible** le fait que l'application n'est pas en service. Sans lui
/// on montre un écran qui a l'air utilisable et qui ne répond pas, ce qui est
/// la seule chose vraiment irritante que cette conception puisse produire.
///
/// Il est **uni**, jamais percé : désigner un bouton supposerait qu'il y a
/// quelque chose à y faire, et il n'y a rien à faire.
struct OnboardingVeil: View {
    var body: some View {
        Ink.ground.opacity(0.55)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

#Preview("Le cartouche") {
    ZStack(alignment: .bottom) {
        Ink.ground.ignoresSafeArea()
        OnboardingCartouche(
            step: .decouvrir,
            counter: "3 / 6",
            progress: 0.5,
            onNext: {},
            onSkip: {}
        )
    }
}
