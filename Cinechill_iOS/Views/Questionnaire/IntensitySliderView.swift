//
//  IntensitySliderView.swift
//  Cinechill_iOS
//

import SwiftUI

/// Un curseur d'intensité (0…1) — le seul format qui capte un « un peu » là où les
/// puces obligent à trancher. Alimente `QuestionnaireAnswers.surpriseIntensity`.
struct IntensitySliderView: View {
    @Binding var value: Double
    var lowLabel = "Valeurs sûres"
    var highLabel = "Inattendu total"

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text(QuestionStep.surpriseIntensity.title)
                    .planTitle()
                    .foregroundStyle(Ink.ink)
                    .fixedSize(horizontal: false, vertical: true)

                if let subtitle = QuestionStep.surpriseIntensity.subtitle {
                    Text(subtitle)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Ink.ink3)
                }
            }

            VStack(spacing: 12) {
                Slider(value: $value, in: 0...1)
                    .tint(Ink.ink)

                HStack {
                    Text(lowLabel)
                    Spacer(minLength: 12)
                    Text(highLabel)
                }
                .planLabel()
                .foregroundStyle(Ink.ink3)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(QuestionStep.surpriseIntensity.title)
    }
}

#Preview("Curseur") {
    ZStack {
        Ink.ground.ignoresSafeArea()
        IntensitySliderView(value: .constant(0.5))
            .padding(Metrics.margin)
    }
}
