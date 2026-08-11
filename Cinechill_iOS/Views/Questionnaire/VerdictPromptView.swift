//
//  VerdictPromptView.swift
//  Cinechill_iOS
//

import SwiftUI

/// La question du lendemain : ce qu'un film a laissé.
///
/// Un geste, trois réponses, et c'est tout. Pas d'échelle de dix étoiles — elle ne
/// se remplit jamais, et ce qu'on cherche à savoir tient de toute façon en trois
/// cas. C'est le seul endroit du système où l'on apprend quelque chose de
/// l'expérience réelle plutôt que d'une déclaration ; à terme, c'est lui qui
/// calibrera tous les coefficients posés à la main jusqu'ici.
///
/// Elle s'efface aussi bien qu'elle se répond : « une autre fois » n'est pas une
/// dérobade, c'est une réponse légitime à une question qu'on n'a pas demandée.
struct VerdictPromptView: View {
    let pending: PendingVerdict
    let onAnswer: (FilmVerdict) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                PlanLightOutline()
                Text("Ton dernier film", bundle: .app)
                    .planLabel()
                    .foregroundStyle(Ink.ink3)
            }

            Text(question)
                .planTitle(19)
                .foregroundStyle(Ink.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)

            Text("Ta réponse nous aide à mieux choisir la prochaine fois.", bundle: .app)
                .font(.system(size: 12.5))
                .foregroundStyle(Ink.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)

            VStack(spacing: 7) {
                ForEach(FilmVerdict.allCases, id: \.self) { verdict in
                    Button { onAnswer(verdict) } label: {
                        Text(verdict.label)
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(Ink.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .frame(height: Metrics.control)
                            .overlay(
                                RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                                    .stroke(Ink.ruleSet, lineWidth: 1)
                            )
                    }
                    .buttonStyle(PressableScaleStyle(scale: 0.985))
                }
            }
            .padding(.top, 18)

            Button(action: onDismiss) {
                Text("Une autre fois", bundle: .app)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Ink.ink3)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(20)
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                .stroke(Ink.rule, lineWidth: 1)
        )
    }

    private var question: String {
        guard let title = pending.title, !title.isEmpty else {
            return String(localized: "Tu as aimé le film qu'on t'avait proposé ?", bundle: .app)
        }
        return String(localized: "Tu as aimé \(title) ?", bundle: .app)
    }
}

#Preview("Verdict") {
    ZStack {
        Ink.ground.ignoresSafeArea()
        VerdictPromptView(
            pending: PendingVerdict(tmdbID: 1, title: "Une séparation"),
            onAnswer: { _ in },
            onDismiss: {}
        )
        .padding(Metrics.margin)
    }
}
