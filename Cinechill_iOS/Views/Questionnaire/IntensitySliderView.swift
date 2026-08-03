//
//  IntensitySliderView.swift
//  Cinechill_iOS
//

import SwiftUI

/// Curseur d'intensité (0…1) — capture une nuance continue plutôt qu'un choix discret, pour les
/// questions où "à quel point" a plus de sens que "lequel" (voir `QuestionnaireAnswers.surpriseIntensity`).
struct IntensitySliderView: View {
    @Binding var value: Double
    var lowLabel = "Valeurs sûres"
    var highLabel = "Inattendu total"

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            VStack(spacing: 10) {
                Slider(value: $value, in: 0...1)
                    .tint(.indigo)
                HStack {
                    Text(lowLabel)
                    Spacer()
                    Text(highLabel)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            }
        }
        .padding(22)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.08), radius: 20, y: 10)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.5), .white.opacity(0.05)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(QuestionStep.surpriseIntensity.title)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle = QuestionStep.surpriseIntensity.subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    IntensitySliderView(value: .constant(0.5))
        .padding()
}
