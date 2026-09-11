//
//  ResultView.swift
//  Cinechill_iOS
//

import SwiftUI

/// Le verdict — un seul film assumé, pas trois.
///
/// La feature prétend trouver le film parfait ; trois propositions disaient le
/// contraire. L'écran montre un seul titre, sans score affiché — l'assurance se
/// montre, elle ne se chiffre pas. « Ce n'est pas lui » révèle le n°2, puis le
/// n°3 : le backend prépare toujours un classement complet, seul le client
/// change ce qu'il révèle. Et chaque refus est un signal de goût **par film**,
/// daté — la granularité que le refus d'un trio moyennait sur trois.
/// Le verdict — un seul film assumé, pas trois.
///
/// La feature prétend trouver le film parfait ; trois propositions disaient le
/// contraire. L'écran montre un seul titre, sans score affiché — l'assurance se
/// montre, elle ne se chiffre pas. « Une autre affiche » révèle le n°2, puis le
/// n°3 : le backend prépare toujours un classement complet, seul le client
/// change ce qu'il révèle. Et chaque refus est un signal de goût **par film**,
/// daté — la granularité que le refus d'un trio moyennait sur trois.
///
/// **L'écran a été vidé.** Il portait un titre de section, un sous-titre, une
/// ligne de raisons, quatre boutons et trois liens : de quoi hésiter, sur
/// l'écran dont le propos est de ne plus hésiter. Il ne reste que l'affiche
/// entière, le titre, et deux gestes — partir voir le film, ou en demander un
/// autre. Ce qui a disparu et n'a pas trouvé d'autre place : la ligne de
/// raisons (qui citait les films de l'utilisateur, seule sortie visible du
/// chantier C5), l'ajout à la liste, la bande-annonce et « Pourquoi ce
/// film ? », qui ouvrait la Fiche du trait.
struct ResultView: View {
    let results: [RecommendationResult]
    let onRestart: () -> Void
    /// Signale qu'on est parti voir ce film — le geste qui ouvre la boucle.
    var onLaunch: ((Int) -> Void)?
    /// « Une autre affiche » — le refus du film révélé, avant d'ouvrir le
    /// suivant.
    var onPass: ((Int) -> Void)?
    /// Plus rien à révéler et rien ne tente : la sortie honnête, qui recompose
    /// une sélection ailleurs dans le vivier.
    var onReject: (() -> Void)?

    @Environment(\.openURL) private var openURL

    /// L'index du film révélé. Les refusés ne restent pas à l'écran : le
    /// verdict est un face-à-face, pas une liste qui s'allonge.
    @State private var revealedIndex = 0

    private var current: RecommendationResult? {
        revealedIndex < results.count ? results[revealedIndex] : results.last
    }

    var body: some View {
        // Salle noire, faisceau visible, et pour seul objet éclairé l'affiche.
        // La toile est éteinte pour cet écran (voir `SalleBackdrop`) : elle
        // n'aurait plus de question à porter, et un rectangle blanc derrière
        // l'affiche aurait été le plus gros aplat de l'application.
        SalleStage {
            VStack(spacing: 0) {
                topBar

                if let current {
                    poster(for: current)
                        .id(current.id)
                        .transition(.opacity)
                        .padding(.top, 8)

                    sheet(for: current)
                        .padding(.top, 22)
                }
            }
            .padding(.horizontal, Metrics.margin)
            .padding(.bottom, Metrics.margin)
        }
        // Un second trio recomposé (« Aucun ne me tente ») repart du verdict :
        // l'identité du premier film dit que la sélection a changé.
        .task(id: results.first?.id) { revealedIndex = 0 }
        .animation(Metrics.unfold, value: revealedIndex)
    }

    // MARK: - Recommencer

    /// Recommencer est une icône, en haut à droite : le mot occupait une ligne
    /// entière au bas de l'écran, à égalité visuelle avec le film retenu, alors
    /// qu'il dit d'abandonner tout ce qu'on vient de répondre.
    private var topBar: some View {
        HStack {
            Spacer()
            Button(action: onRestart) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Ink.ink2)
                    .frame(width: Metrics.control, height: Metrics.control)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Recommencer une recherche", bundle: .app))
        }
        .padding(.trailing, -8)
    }

    // MARK: - L'affiche

    /// Entière et à ses proportions. Elle prend toute la hauteur qui reste une
    /// fois le texte posé : c'est elle l'objet de l'écran.
    private func poster(for result: RecommendationResult) -> some View {
        AsyncImage(url: result.item.posterURL) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFit()
            default:
                ZStack {
                    Rectangle().fill(Color(hex: 0x141C26))
                    CinechillHallIconView(.salle)
                        .frame(width: 26, height: 26)
                        .foregroundStyle(Ink.ink3)
                }
                .aspectRatio(2 / 3, contentMode: .fit)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous))
        .accessibilityHidden(true)
    }

    // MARK: - Le film, et les deux gestes

    private func sheet(for result: RecommendationResult) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Text(rankLabel)
                    .planLabel()
                    .foregroundStyle(Ink.ink3)
                    .monospacedDigit()
                if revealedIndex == 0 { PlanLight() }
            }

            Text(result.item.title)
                .planTitle(26)
                .foregroundStyle(Ink.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)

            Text(verbatim: "\(result.item.mediaType.singularLabel) · \(result.item.displayYear)")
                .font(.system(size: 12.5))
                .foregroundStyle(Ink.ink3)
                .padding(.top, 6)

            PlanButton(title: String(localized: "Démarrer le film", bundle: .app)) {
                start(result)
            }
            .padding(.top, 20)

            secondary(for: result)
                .padding(.top, 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Le second geste, toujours discret : demander un autre film tant qu'il en
    /// reste, puis recomposer une sélection ailleurs dans le vivier.
    @ViewBuilder
    private func secondary(for result: RecommendationResult) -> some View {
        if revealedIndex < results.count - 1 {
            Button {
                onPass?(result.item.tmdbId)
                revealedIndex += 1
            } label: {
                Text("Une autre affiche", bundle: .app)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Ink.ink2)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
        } else if let onReject {
            Button(action: onReject) {
                Text("Aucun ne me tente, propose-m'en d'autres", bundle: .app)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Ink.ink2)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
        }
    }

    private var rankLabel: String {
        switch revealedIndex {
        case 0: String(localized: "Le verdict", bundle: .app)
        default: String(localized: "N°\(revealedIndex + 1)", bundle: .app)
        }
    }

    // MARK: - Partir voir le film

    /// Ouvre l'app native de la plateforme si elle est installée (ex. Netflix via
    /// `nflx://`), sinon retombe sur le site web du service.
    ///
    /// C'est le geste le plus proche d'un « je vais le voir » qu'on puisse
    /// observer : on le note ici, et c'est lui qui déclenchera la question du
    /// lendemain. Il est noté même si aucune destination ne s'ouvre — la
    /// décision a été prise, c'est elle qui compte.
    private func start(_ result: RecommendationResult) {
        onLaunch?(result.item.tmdbId)
        for candidate in result.watchAppURLCandidates
        where UIApplication.shared.canOpenURL(candidate) {
            UIApplication.shared.open(candidate)
            return
        }
        guard let webURL = result.watchWebURL else { return }
        openURL(webURL)
    }
}

#Preview {
    NavigationStack {
        ZStack {
            Ink.ground.ignoresSafeArea()
            ResultView(
                results: [
                    RecommendationResult(
                        item: MediaItem(
                            tmdbId: 1,
                            mediaType: .movie,
                            title: "Interstellar",
                            posterPath: nil,
                            overview: nil,
                            voteAverage: 8.3,
                            voteCount: 34_000,
                            genreIds: [],
                            releaseDate: "2014-01-01"
                        ),
                        matchScore: 92,
                        reasons: ["Science-fiction", "2h+", "Disponible sur Netflix"],
                        trailerKey: "zSWdZVtXT7E",
                        providerIDs: [8]
                    )
                ],
                onRestart: {}
            )
        }
    }
    .environmentObject(LibraryStore())
}
