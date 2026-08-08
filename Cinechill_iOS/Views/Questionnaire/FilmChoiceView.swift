//
//  FilmChoiceView.swift
//  Cinechill_iOS
//

import SwiftUI

/// Le film cherché : quel genre, et quelle ambiance.
///
/// Remplace le cadran d'humeur, qui demandait de situer son propre état sur deux
/// dimensions abstraites puis en déduisait les genres. Deux problèmes : le geste
/// n'était compris par personne, et le genre — le critère le plus discriminant
/// dont on dispose pour resserrer la recherche — était deviné au lieu d'être
/// demandé. Il est ici redevenu une réponse, à côté d'une ambiance choisie dans
/// une liste plutôt que déduite d'un point sur un carré.
struct FilmChoiceView: View {
    let availableGenres: [Genre]
    /// En lecture seule : toute écriture passe par `onToggleGenre`, qui seul
    /// tient le plafond de deux genres.
    let selectedGenres: Set<Genre>
    @Binding var mood: Mood?
    let maxGenres: Int
    /// Faux quand la limite de genres est atteinte et que la puce n'est pas déjà
    /// cochée — on grise plutôt que d'ignorer silencieusement le tap.
    let isGenreSelectable: (Genre) -> Bool
    let onToggleGenre: (Genre) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 34) {
            group(
                "Quel genre de film ?",
                note: genreNote
            ) {
                ForEach(availableGenres, id: \.self) { genre in
                    let selectable = isGenreSelectable(genre)
                    // Grisé de l'extérieur plutôt qu'en ajoutant un état à
                    // `PlanChip` : la puce est partagée par toute l'application,
                    // et la limite à deux genres ne concerne que cet écran.
                    PlanChip(title: genre.label, isOn: selectedGenres.contains(genre)) {
                        onToggleGenre(genre)
                    }
                    .disabled(!selectable)
                    .opacity(selectable ? 1 : 0.35)
                }
            }

            group("Quelle ambiance ?", note: nil) {
                ForEach(Mood.allCases, id: \.self) { value in
                    PlanChip(title: value.label, isOn: mood == value) {
                        mood = value
                    }
                }
            }
        }
    }

    /// La note dit l'état de la sélection plutôt qu'une règle abstraite : « Deux
    /// genres au maximum » avant tout choix n'informe personne, alors que
    /// « Encore un genre possible » arrive au moment où ça compte.
    private var genreNote: String {
        switch selectedGenres.count {
        case 0: "Facultatif — laissez vide si vous êtes ouvert·e à tout."
        case maxGenres: "C'est le maximum. Touchez un genre pour le retirer."
        default: "Vous pouvez en choisir un second."
        }
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

#Preview("Quel film ce soir") {
    struct Harness: View {
        @State private var genres: Set<Genre> = [.thriller]
        @State private var mood: Mood? = .intense

        var body: some View {
            ZStack {
                Ink.ground.ignoresSafeArea()
                ScrollView {
                    FilmChoiceView(
                        availableGenres: Genre.allCases.filter { $0 != .animation },
                        selectedGenres: genres,
                        mood: $mood,
                        maxGenres: 2,
                        isGenreSelectable: { genres.contains($0) || genres.count < 2 },
                        onToggleGenre: { genre in
                            if genres.contains(genre) { genres.remove(genre) } else { genres.insert(genre) }
                        }
                    )
                    .padding(Metrics.margin)
                }
            }
        }
    }
    return Harness()
}
