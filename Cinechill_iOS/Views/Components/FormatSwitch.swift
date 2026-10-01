//
//  FormatSwitch.swift
//  Cinechill_iOS
//

import SwiftUI

/// L'interrupteur Films · Séries, en tête de Découvrir et de CinéMatch.
///
/// Deux puces du système, et rien d'autre : c'est le sélecteur de toute l'app,
/// et l'aplat d'encre dit lequel est retenu. Il se lit à `@AppStorage`, si bien
/// que les deux écrans qui le portent basculent ensemble.
struct FormatSwitch: View {
    @AppStorage(MediaFormat.storageKey) private var formatRaw = MediaFormat.film.rawValue

    var isEnabled = true

    private var format: MediaFormat { MediaFormat(rawValue: formatRaw) ?? .film }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(MediaFormat.allCases, id: \.self) { option in
                PlanChip(title: option.label, isOn: format == option) {
                    guard format != option else { return }
                    Haptics.selection()
                    formatRaw = option.rawValue
                }
            }
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
        .accessibilityElement(children: .contain)
    }
}
