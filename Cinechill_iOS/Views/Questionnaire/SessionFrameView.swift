//
//  SessionFrameView.swift
//  Cinechill_iOS
//

import SwiftUI

/// La durée : la première contrainte dure de la soirée, seule sur son écran.
///
/// La Salle projette une question à la fois. Cet écran en portait deux — la
/// durée et la forme du contenu — et la forme a rejoint les genres, qui posent
/// la même question sur le même objet. Le genre, l'origine et l'ambiance ont
/// chacun le leur (voir `FilmChoiceView`).
///
/// **« Avec qui » n'est pas demandé ici** : la question est posée à l'entrée
/// de la Salle (`SessionEntryView`), et sa réponse arrive jusqu'ici par
/// `start(audience:)`. La reposer reviendrait à afficher deux fois la même
/// question à un écran d'écart. Pour la changer, on revient en arrière.
struct SessionFrameView: View {
    @Binding var budget: RuntimePreference

    /// Renseigné quand le budget a été présélectionné d'après l'heure — la note
    /// n'apparaît que si elle dit quelque chose de vrai.
    var lateHourNote: String?

    var body: some View {
        VStack(spacing: 14) {
            // Pas de titre : « Durée du film » est projeté sur la toile par
            // `SalleStage`. Ne reste que la note d'heure tardive, qui dit une
            // conséquence et non la question.
            if let lateHourNote {
                Text(lateHourNote)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Ink.ink2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            FlowLayout(spacing: 7, alignment: .center) {
                ForEach(budgets, id: \.0) { preference, title in
                    PlanChip(title: title, isOn: budget == preference) {
                        budget = preference
                    }
                }
            }
        }
    }

    /// Le budget de la soirée réutilise `RuntimePreference` — mêmes valeurs, mais
    /// dites en durée disponible plutôt qu'en préférence de format. `.long` n'y
    /// figure plus : « toute la soirée » et « peu importe » disaient la même
    /// chose au serveur (aucun plafond), et seul le second est une réponse que
    /// l'on donne sans y penser. Calculée : un `static let` fige ses libellés
    /// dans la langue du premier accès et ne les relit jamais.
    private var budgets: [(RuntimePreference, String)] {
        [
            (.short, String(localized: "Environ 1 h 30", bundle: .app)),
            (.medium, String(localized: "Environ 2 h", bundle: .app)),
            (.any, String(localized: "Peu importe", bundle: .app)),
        ]
    }
}

#Preview("La durée") {
    struct Harness: View {
        @State private var budget: RuntimePreference = .medium

        var body: some View {
            ZStack {
                SalleBackdrop(light: SalleLight.frame).ignoresSafeArea()
                SalleStage(question: "Durée du film") {
                    VStack {
                        Spacer(minLength: 0)
                        SessionFrameView(
                            budget: $budget,
                            lateHourNote: "Il est 21 h 40 : on a présélectionné un format court pour que tu puisses le finir ce soir."
                        )
                        .padding(Metrics.margin)
                    }
                }
            }
        }
    }
    return Harness()
}
