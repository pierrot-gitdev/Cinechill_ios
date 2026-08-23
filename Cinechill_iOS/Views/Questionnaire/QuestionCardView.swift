//
//  QuestionCardView.swift
//  Cinechill_iOS
//

import SwiftUI

/// Une question à puces : une note de service éventuelle, une grille de
/// `PlanChip`. Plus de carte de verre — dans « Le Plan » un bloc se pose à plat,
/// et c'est la grille qui le tient, pas un fond.
///
/// **Le titre a quitté cette vue** : depuis la refonte de la Salle, la question
/// est projetée sur la toile, au-dessus des réponses. L'écrire ici aussi la
/// dédoublerait, à trente points d'écart.
struct QuestionCardView: View {
    let step: QuestionStep
    let options: [ChipOption]
    let selectedIDs: Set<String>
    let onToggle: (String) -> Void

    var body: some View {
        VStack(spacing: 16) {
            if let subtitle = step.subtitle {
                Text(subtitle)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Ink.ink3)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            FlowLayout(spacing: 7, alignment: .center) {
                ForEach(options) { option in
                    PlanChip(title: option.label, isOn: selectedIDs.contains(option.id)) {
                        onToggle(option.id)
                    }
                }
            }
        }
    }
}

#Preview("Question") {
    ZStack {
        SalleBackdrop(light: SalleLight.asking(question: 3)).ignoresSafeArea()
        SalleStage(question: QuestionStep.mindset.title, eyebrow: "Question 3") {
        VStack {
            Spacer(minLength: 0)
            QuestionCardView(
                step: .mindset,
                options: Mindset.chipOptions,
                selectedIDs: [Mindset.beSurprised.rawValue],
                onToggle: { _ in }
            )
            .padding(Metrics.margin)
        }
        }
    }
}
