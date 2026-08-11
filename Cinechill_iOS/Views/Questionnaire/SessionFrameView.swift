//
//  SessionFrameView.swift
//  Cinechill_iOS
//

import SwiftUI

/// Le cadre : les seules contraintes dures de la soirée, sur un écran.
///
/// Remplace les quatre écrans du socle. Les plateformes ne sont plus demandées —
/// elles vivent dans les réglages et sont rappelées à l'accueil ; le genre et
/// l'ambiance ont leur propre écran (voir `FilmChoiceView`).
///
/// **« Avec qui » n'est plus demandé ici** : la question est posée sur l'écran
/// d'entrée, à même le mur d'affiches (`SessionEntryView`), et sa réponse arrive
/// jusqu'ici par `start(audience:)`. La reposer reviendrait à afficher deux fois
/// la même question à trente points d'écart, ce qui est précisément le défaut
/// qu'on est venu corriger. Pour la changer, on revient en arrière.
struct SessionFrameView: View {
    @Binding var budget: RuntimePreference
    @Binding var contentFormat: ContentFormat?

    /// Renseigné quand le budget a été présélectionné d'après l'heure — la note
    /// n'apparaît que si elle dit quelque chose de vrai.
    var lateHourNote: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 34) {
            group(String(localized: "Tu as combien de temps ?", bundle: .app), note: lateHourNote) {
                ForEach(budgets, id: \.0) { preference, title in
                    PlanChip(title: title, isOn: budget == preference) {
                        budget = preference
                    }
                }
            }

            group(String(localized: "Tu cherches quoi ?", bundle: .app), note: nil) {
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
    /// Calculée : un `static let` fige ses libellés dans la langue du premier
    /// accès et ne les relit jamais.
    private var budgets: [(RuntimePreference, String)] {
        [
            (.short, String(localized: "Environ 1 h 30", bundle: .app)),
            (.medium, String(localized: "Environ 2 h", bundle: .app)),
            (.long, String(localized: "Toute la soirée", bundle: .app)),
        ]
    }

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

#Preview("Ta soirée") {
    struct Harness: View {
        @State private var budget: RuntimePreference = .medium
        @State private var format: ContentFormat? = .liveAction

        var body: some View {
            ZStack {
                Ink.ground.ignoresSafeArea()
                SessionFrameView(
                    budget: $budget,
                    contentFormat: $format,
                    lateHourNote: "Il est 21 h 40 : on a présélectionné un format court pour que tu puisses le finir ce soir."
                )
                .padding(Metrics.margin)
            }
        }
    }
    return Harness()
}
