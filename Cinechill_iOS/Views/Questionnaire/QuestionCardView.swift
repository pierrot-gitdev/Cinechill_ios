//
//  QuestionCardView.swift
//  Cinechill_iOS
//

import SwiftUI

/// Une question à puces : un titre, éventuellement une note de service, une grille
/// de `PlanChip`. Plus de carte de verre — dans « Le Plan » un bloc se pose à plat,
/// et c'est la grille qui le tient, pas un fond.
struct QuestionCardView: View {
    let step: QuestionStep
    let options: [ChipOption]
    let selectedIDs: Set<String>
    let onToggle: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text(step.title)
                    .planTitle()
                    .foregroundStyle(Ink.ink)
                    .fixedSize(horizontal: false, vertical: true)

                if let subtitle = step.subtitle {
                    Text(subtitle)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Ink.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            FlowLayout(spacing: 7) {
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
        Ink.ground.ignoresSafeArea()
        QuestionCardView(
            step: .mindset,
            options: Mindset.chipOptions,
            selectedIDs: [Mindset.beSurprised.rawValue],
            onToggle: { _ in }
        )
        .padding(Metrics.margin)
    }
}
