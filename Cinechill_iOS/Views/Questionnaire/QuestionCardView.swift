//
//  QuestionCardView.swift
//  Cinechill_iOS
//

import SwiftUI

/// Rendu générique d'une question CinéMatch : titre, badge filtre/score, et une grille de chips.
/// Réutilisé pour les 11 questions du quiz — seuls le contenu et le mode de sélection changent.
struct QuestionCardView: View {
    let step: QuestionStep
    let options: [ChipOption]
    let selectedIDs: Set<String>
    let onToggle: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            FlowLayout(spacing: 10) {
                ForEach(options) { option in
                    chip(for: option)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                badge(text: step.badge.label, color: step.badge == .filter ? .orange : .indigo)
                if step.isSurprise {
                    badge(text: "Surprise", color: .pink, outlined: true)
                }
            }
            Text(step.title)
                .font(.title2.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle = step.subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func badge(text: String, color: Color, outlined: Bool = false) -> some View {
        Text(text.uppercased())
            .font(.caption2.weight(.bold))
            .tracking(0.4)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background {
                if outlined {
                    Capsule().stroke(color.opacity(0.5), lineWidth: 1)
                } else {
                    Capsule().fill(color.opacity(0.14))
                }
            }
    }

    private func chip(for option: ChipOption) -> some View {
        let selected = selectedIDs.contains(option.id)
        return Button {
            onToggle(option.id)
        } label: {
            Text(option.label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(selected ? .white : .primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(selected ? Color.indigo : Color(.secondarySystemBackground), in: Capsule())
                .overlay(
                    Capsule().stroke(selected ? Color.clear : Color.gray.opacity(0.25), lineWidth: 1)
                )
        }
        .buttonStyle(ChipButtonStyle())
        .sensoryFeedback(.selection, trigger: selected)
        .animation(.spring(response: 0.25, dampingFraction: 0.65), value: selected)
    }
}

private struct ChipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

#Preview {
    QuestionCardView(
        step: .mood,
        options: Mood.chipOptions,
        selectedIDs: [Mood.lightFun.rawValue],
        onToggle: { _ in }
    )
    .padding()
}
