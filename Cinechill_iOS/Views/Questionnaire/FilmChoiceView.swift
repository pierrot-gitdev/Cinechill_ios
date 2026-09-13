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
///
/// **Les deux questions ont maintenant chacune leur écran.** La Salle projette
/// la question sur sa toile, et une toile n'en porte qu'une : les empiler
/// revenait à écrire deux questions au même endroit, ce qui ne se lit pas.
/// Chaque question a le sien : le genre (avec la forme du contenu, qui porte
/// sur le même objet), l'origine, puis l'ambiance.
struct GenreChoiceView: View {
    let availableGenres: [Genre]
    /// En lecture seule : toute écriture passe par `onToggleGenre`, qui seul
    /// tient le plafond de deux genres.
    let selectedGenres: Set<Genre>
    /// Faux quand la limite de genres est atteinte et que la puce n'est pas déjà
    /// cochée — on grise plutôt que d'ignorer silencieusement le tap.
    let isGenreSelectable: (Genre) -> Bool
    let onToggleGenre: (Genre) -> Void

    /// La forme du contenu, qui vivait sur l'écran de la durée. Elle est ici
    /// parce qu'elle pose la même question que le genre : de quelle sorte de
    /// film on parle. Elle reste un filtre dur, jamais assoupli.
    @Binding var contentFormat: ContentFormat?

    var body: some View {
        VStack(spacing: 30) {
            // Le titre du groupe a disparu : la question est projetée sur la
            // toile, au-dessus. Ne reste que la note, qui dit l'état de la
            // sélection et non la question.
            VStack(spacing: 14) {
                Text(genreNote)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Ink.ink2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                FlowLayout(spacing: 7, alignment: .center) {
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
            }

            VStack(spacing: 14) {
                // L'intitulé de section est fer à gauche partout ailleurs ;
                // ici il coiffe une rangée centrée et doit la suivre.
                Text("Tu cherches quoi ?", bundle: .app)
                    .planLabel()
                    .foregroundStyle(Ink.ink2)
                FlowLayout(spacing: 7, alignment: .center) {
                    ForEach(ContentFormat.allCases, id: \.self) { value in
                        PlanChip(title: value.label, isOn: contentFormat == value) {
                            contentFormat = value
                        }
                    }
                }
            }
        }
    }

    /// Une note fixe : elle dit que la question est facultative, ce qui reste
    /// vrai quoi qu'on coche.
    private var genreNote: String {
        String(localized: "Facultatif : laisse vide si tu es ouvert·e à tout.", bundle: .app)
    }
}

/// L'origine, seule sur son écran.
struct OriginChoiceView: View {
    /// En lecture seule, comme les genres : le plafond se tient dans le modèle.
    let selectedOrigins: Set<OriginCountry>
    let isOriginSelectable: (OriginCountry) -> Bool
    let onToggleOrigin: (OriginCountry) -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text(originNote)
                .font(.system(size: 12.5))
                .foregroundStyle(Ink.ink2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            FlowLayout(spacing: 7, alignment: .center) {
                ForEach(OriginCountry.allCases, id: \.self) { origin in
                    let selectable = isOriginSelectable(origin)
                    PlanChip(title: origin.label, isOn: selectedOrigins.contains(origin)) {
                        onToggleOrigin(origin)
                    }
                    .disabled(!selectable)
                    .opacity(selectable ? 1 : 0.35)
                }
            }
        }
    }

    private var originNote: String {
        String(localized: "Facultatif : laisse vide pour ne rien exclure.", bundle: .app)
    }
}

/// L'ambiance, seule sur son écran.
struct MoodChoiceView: View {
    /// L'ambiance passe par des fermetures et non par un binding : c'est ce
    /// qui permet au modèle de distinguer « pas encore répondu » de « peu
    /// importe » — deux états que `nil` seul ne sait pas raconter.
    let selectedMood: Mood?
    let isMoodAny: Bool
    let onPickMood: (Mood) -> Void
    let onMoodAny: () -> Void

    var body: some View {
        FlowLayout(spacing: 7, alignment: .center) {
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

#Preview("Le genre") {
    struct Harness: View {
        @State private var genres: Set<Genre> = [.thriller]
        @State private var format: ContentFormat? = .liveAction

        var body: some View {
            ZStack {
                SalleBackdrop(light: SalleLight.genre).ignoresSafeArea()
                SalleStage(question: "Quel genre de film ?") {
                    VStack {
                        Spacer(minLength: 0)
                        GenreChoiceView(
                            availableGenres: Genre.allCases,
                            selectedGenres: genres,
                            isGenreSelectable: { genres.contains($0) || genres.count < 2 },
                            onToggleGenre: { genre in
                                if genres.contains(genre) { genres.remove(genre) } else { genres.insert(genre) }
                            },
                            contentFormat: $format
                        )
                        .padding(Metrics.margin)
                    }
                }
            }
        }
    }
    return Harness()
}
