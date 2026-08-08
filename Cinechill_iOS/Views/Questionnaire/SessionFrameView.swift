//
//  SessionFrameView.swift
//  Cinechill_iOS
//

import SwiftUI

/// Le cadre : les seules contraintes dures de la soirée, sur un écran.
///
/// Remplace les quatre écrans du socle. Les plateformes ne sont plus demandées —
/// elles vivent dans les réglages et sont rappelées au seuil ; les genres ne sont
/// plus demandés non plus — ils se déduisent du cadran (voir `MoodTransfer`).
/// Restent trois choses qu'aucune donnée ne peut deviner : avec qui, combien de
/// temps, et sous quelle forme.
struct SessionFrameView: View {
    @Binding var audience: Audience?
    @Binding var budget: RuntimePreference
    @Binding var contentFormat: ContentFormat?

    /// Renseigné quand le budget a été présélectionné d'après l'heure — la note
    /// n'apparaît que si elle dit quelque chose de vrai.
    var lateHourNote: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 34) {
            group("Avec qui", note: audience == .family ? "On écartera ce qui ne se regarde pas à plusieurs." : nil) {
                ForEach(Audience.allCases, id: \.self) { value in
                    PlanChip(title: value.label, isOn: audience == value) {
                        audience = value
                    }
                }
            }

            group("Jusqu'à quand", note: lateHourNote) {
                ForEach(Self.budgets, id: \.0) { preference, title in
                    PlanChip(title: title, isOn: budget == preference) {
                        budget = preference
                    }
                }
            }

            group("Ce soir on regarde", note: nil) {
                ForEach(ContentFormat.allCases, id: \.self) { value in
                    PlanChip(title: value.label, isOn: contentFormat == value) {
                        contentFormat = value
                    }
                }
            }
        }
    }

    /// Le budget de la soirée réutilise `RuntimePreference` — mêmes valeurs, mais
    /// dites en durée disponible plutôt qu'en préférence de format. `.any` n'y
    /// figure pas : on a toujours une heure à laquelle on veut être couché.
    private static let budgets: [(RuntimePreference, String)] = [
        (.short, "1 h 30"),
        (.medium, "2 h"),
        (.long, "Toute la soirée"),
    ]

    private func group(
        _ title: String,
        note: String?,
        @ViewBuilder chips: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            PlanSectionLabel(title: title, note: note)
            FlowLayout(spacing: 7) {
                chips()
            }
        }
    }
}

#Preview("Le cadre") {
    struct Harness: View {
        @State private var audience: Audience? = .couple
        @State private var budget: RuntimePreference = .medium
        @State private var format: ContentFormat? = .liveAction

        var body: some View {
            ZStack {
                Ink.ground.ignoresSafeArea()
                SessionFrameView(
                    audience: $audience,
                    budget: $budget,
                    contentFormat: $format,
                    lateHourNote: "Il est 21 h 40 — on part sur quelque chose de court."
                )
                .padding(Metrics.margin)
            }
        }
    }
    return Harness()
}
