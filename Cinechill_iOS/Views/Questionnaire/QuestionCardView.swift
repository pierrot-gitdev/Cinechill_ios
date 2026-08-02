//
//  QuestionCardView.swift
//  Cinechill_iOS
//

import SwiftUI

/// Rendu générique d'une question CinéMatch : titre et une grille de chips.
/// Réutilisé pour les 11 questions du quiz — seuls le contenu et le mode de sélection changent.
struct QuestionCardView: View {
    let step: QuestionStep
    let options: [ChipOption]
    let selectedIDs: Set<String>
    let onToggle: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            FlowLayout(spacing: 10) {
                ForEach(options) { option in
                    chip(for: option)
                }
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
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(step.title)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle = step.subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Même padding et même police, sélectionné ou non : seule la couleur change, pour que la
    /// taille du chip — et donc l'agencement de la grille — ne bouge jamais à la sélection.
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
                .background {
                    if selected {
                        Capsule().fill(
                            LinearGradient(colors: [.indigo, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .shadow(color: .indigo.opacity(0.35), radius: 10, y: 4)
                    } else {
                        Capsule().fill(Color(.secondarySystemBackground))
                    }
                }
                .overlay(
                    Capsule().stroke(selected ? Color.clear : Color.gray.opacity(0.25), lineWidth: 1)
                )
        }
        .buttonStyle(ChipButtonStyle())
        .sensoryFeedback(.selection, trigger: selected)
        .animation(.spring(response: 0.3, dampingFraction: 0.65), value: selected)
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
