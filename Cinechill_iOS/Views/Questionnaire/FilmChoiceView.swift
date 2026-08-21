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
    /// L'ambiance passe par des fermetures et non par un binding : c'est ce
    /// qui permet au modèle de distinguer « pas encore répondu » de « peu
    /// importe » — deux états que `nil` seul ne sait pas raconter.
    let selectedMood: Mood?
    let isMoodAny: Bool
    let onPickMood: (Mood) -> Void
    let onMoodAny: () -> Void
    let maxGenres: Int
    /// Faux quand la limite de genres est atteinte et que la puce n'est pas déjà
    /// cochée — on grise plutôt que d'ignorer silencieusement le tap.
    let isGenreSelectable: (Genre) -> Bool
    let onToggleGenre: (Genre) -> Void

    /// En lecture seule, comme les genres : le plafond se tient dans le modèle.
    let selectedOrigins: Set<OriginCountry>
    let maxOrigins: Int
    let isOriginSelectable: (OriginCountry) -> Bool
    let onToggleOrigin: (OriginCountry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 34) {
            group(
                String(localized: "Quel genre de film ?", bundle: .app),
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

            group(String(localized: "D'où vient le film ?", bundle: .app), note: originNote) {
                ForEach(OriginCountry.allCases, id: \.self) { origin in
                    let selectable = isOriginSelectable(origin)
                    PlanChip(title: origin.label, isOn: selectedOrigins.contains(origin)) {
                        onToggleOrigin(origin)
                    }
                    .disabled(!selectable)
                    .opacity(selectable ? 1 : 0.35)
                }
            }

            group(String(localized: "Quelle ambiance ?", bundle: .app), note: nil) {
                ForEach(Mood.allCases, id: \.self) { value in
                    PlanChip(title: value.label, isOn: selectedMood == value) {
                        onPickMood(value)
                    }
                }
                // « Peu importe » est une réponse qu'on choisit, pas un champ
                // qu'on laisse vide (C3) : le cœur de cible, c'est justement
                // la personne qui ne sait pas quoi regarder.
                PlanChip(
                    title: String(localized: "Peu importe, surprends-moi", bundle: .app),
                    isOn: isMoodAny,
                    action: onMoodAny
                )
            }
        }
    }

    /// La note dit l'état de la sélection plutôt qu'une règle abstraite : « Deux
    /// genres au maximum » avant tout choix n'informe personne, alors que
    /// « Encore un genre possible » arrive au moment où ça compte.
    private var genreNote: String {
        switch selectedGenres.count {
        case 0: String(localized: "Facultatif : laisse vide si tu es ouvert·e à tout.", bundle: .app)
        case maxGenres: String(localized: "C'est le maximum. Touche un genre pour le retirer.", bundle: .app)
        default: String(localized: "Tu peux en choisir un second.", bundle: .app)
        }
    }

    private var originNote: String {
        switch selectedOrigins.count {
        case 0: String(localized: "Facultatif : laisse vide pour ne rien exclure.", bundle: .app)
        case maxOrigins: String(localized: "C'est le maximum. Touche un pays pour le retirer.", bundle: .app)
        default: String(localized: "Tu peux en choisir \(maxOrigins - selectedOrigins.count) de plus.", bundle: .app)
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
        @State private var origins: Set<OriginCountry> = [.france, .japan]
        @State private var mood: Mood? = .intense
        @State private var moodAny = false

        var body: some View {
            ZStack {
                Ink.ground.ignoresSafeArea()
                ScrollView {
                    FilmChoiceView(
                        availableGenres: Genre.allCases.filter { $0 != .animation },
                        selectedGenres: genres,
                        selectedMood: mood,
                        isMoodAny: moodAny,
                        onPickMood: { mood = $0; moodAny = false },
                        onMoodAny: { mood = nil; moodAny = true },
                        maxGenres: 2,
                        isGenreSelectable: { genres.contains($0) || genres.count < 2 },
                        onToggleGenre: { genre in
                            if genres.contains(genre) { genres.remove(genre) } else { genres.insert(genre) }
                        },
                        selectedOrigins: origins,
                        maxOrigins: 3,
                        isOriginSelectable: { origins.contains($0) || origins.count < 3 },
                        onToggleOrigin: { origin in
                            if origins.contains(origin) { origins.remove(origin) } else { origins.insert(origin) }
                        }
                    )
                    .padding(Metrics.margin)
                }
            }
        }
    }
    return Harness()
}
