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
struct ResultView: View {
    let results: [RecommendationResult]
    let onRestart: () -> Void
    /// Ouvre la Fiche. C'est la réponse au « pourquoi ce film ? » : plutôt que
    /// d'expliquer une formule, on montre ce qu'on croit savoir de la personne.
    var onExplain: (() -> Void)?
    /// Signale qu'on est parti voir ce film — le geste qui ouvre la boucle.
    var onLaunch: ((Int) -> Void)?
    /// « Ce n'est pas lui » — le refus du film révélé, avant d'ouvrir le
    /// suivant.
    var onPass: ((Int) -> Void)?
    /// Plus rien à révéler et rien ne tente : la sortie honnête, qui recompose
    /// une sélection ailleurs dans le vivier.
    var onReject: (() -> Void)?

    /// L'index du film révélé. Les refusés ne restent pas à l'écran : le
    /// verdict est un face-à-face, pas une liste qui s'allonge.
    @State private var revealedIndex = 0

    private var current: RecommendationResult? {
        revealedIndex < results.count ? results[revealedIndex] : results.last
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header

                if let current {
                    PlanEdge()
                    ResultRowView(
                        rankLabel: rankLabel,
                        isVerdict: revealedIndex == 0,
                        result: current,
                        onLaunch: onLaunch
                    )
                    .id(current.id)
                    .transition(.opacity)
                    .padding(.vertical, 20)
                }

                PlanEdge()

                if revealedIndex < results.count - 1 {
                    // En contour, jamais concurrent des actions du film : le
                    // refus est une sortie, pas une invitation.
                    Button {
                        guard let current else { return }
                        onPass?(current.item.tmdbId)
                        withAnimation(Metrics.unfold) { revealedIndex += 1 }
                    } label: {
                        Text("Ce n'est pas lui", bundle: .app)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Ink.ink2)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                    .buttonStyle(.plain)
                    PlanEdge()
                } else if let onReject {
                    Button(action: onReject) {
                        Text("Aucun ne me tente, propose-m'en d'autres", bundle: .app)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Ink.ink2)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                    .buttonStyle(.plain)
                    PlanEdge()
                }

                if let onExplain {
                    Button(action: onExplain) {
                        Text("Pourquoi ce film ?", bundle: .app)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Ink.ink2)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                    .buttonStyle(.plain)
                    PlanEdge()
                }

                Button(action: onRestart) {
                    Text("Recommencer une recherche", bundle: .app)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Ink.ink3)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Metrics.margin)
            .padding(.bottom, Metrics.margin)
        }
        // Un second trio recomposé (« Aucun ne me tente ») repart du verdict :
        // l'identité du premier film dit que la sélection a changé.
        .task(id: results.first?.id) { revealedIndex = 0 }
    }

    private var rankLabel: String {
        switch revealedIndex {
        case 0: String(localized: "Le verdict", bundle: .app)
        default: String(localized: "N°\(revealedIndex + 1)", bundle: .app)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Group {
                switch revealedIndex {
                case 0: Text("Ton film de ce soir", bundle: .app)
                case 1: Text("Deuxième proposition", bundle: .app)
                default: Text("Dernière proposition", bundle: .app)
                }
            }
            .planTitle(26)
            .foregroundStyle(Ink.ink)

            if revealedIndex == 0 {
                Text("Un seul film, choisi pour toi. S'il ne te tente pas, on en a d'autres.", bundle: .app)
                    .font(.system(size: 13))
                    .foregroundStyle(Ink.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 28)
        .padding(.bottom, 26)
    }
}

/// Une proposition : l'affiche, et surtout **pourquoi** — les motifs renvoyés
/// par le backend étaient jusqu'ici calculés puis jetés à l'affichage. Le rang
/// est un libellé (« Le verdict », « N°2 ») : l'écran n'affiche plus qu'un
/// film à la fois.
private struct ResultRowView: View {
    let rankLabel: String
    let isVerdict: Bool
    let result: RecommendationResult
    var onLaunch: ((Int) -> Void)?

    @EnvironmentObject private var libraryStore: LibraryStore
    @Environment(\.openURL) private var openURL
    @State private var isAddingToWatchlist = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            NavigationLink(destination: ItemDetailView(item: result.item)) {
                HStack(alignment: .top, spacing: 14) {
                    poster

                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 7) {
                            Text(rankLabel)
                                .planLabel()
                                .foregroundStyle(Ink.ink3)
                                .monospacedDigit()
                            if isVerdict {
                                PlanLight()
                            }
                        }

                        Text(result.item.title)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Ink.ink)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(verbatim: "\(result.item.mediaType.singularLabel) · \(result.item.displayYear)")
                            .font(.system(size: 12))
                            .foregroundStyle(Ink.ink3)

                        if !result.reasons.isEmpty {
                            Text(result.reasons.prefix(3).joined(separator: " · "))
                                .font(.system(size: 12))
                                .foregroundStyle(Ink.ink2)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 2)
                        }
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            actions
        }
        .onChange(of: libraryStore.isInWatchlist(result.item)) { _, inWatchlist in
            if inWatchlist { isAddingToWatchlist = false }
        }
        .task(id: isAddingToWatchlist) {
            guard isAddingToWatchlist else { return }
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            if !Task.isCancelled { isAddingToWatchlist = false }
        }
    }

    private var poster: some View {
        AsyncImage(url: result.item.posterURL) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            default:
                ZStack {
                    Rectangle().fill(Ink.ground)
                    CinechillHallIconView(.salle)
                        .frame(width: 18, height: 18)
                        .foregroundStyle(Ink.ink3)
                }
            }
        }
        .frame(width: 68, height: 100)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                .strokeBorder(Ink.rule, lineWidth: 1)
        }
    }

    private var actions: some View {
        HStack(spacing: Metrics.gutter) {
            watchlistButton

            if result.trailerURL != nil {
                iconButton(systemImage: "play.fill", label: String(localized: "Bande-annonce", bundle: .app), action: openTrailer)
            }

            if result.watchWebURL != nil {
                iconButton(systemImage: "arrow.up.forward", label: String(localized: "Regarder ce film", bundle: .app), action: openStreamingApp)
            }
        }
    }

    @ViewBuilder
    private var watchlistButton: some View {
        let inWatchlist = libraryStore.isInWatchlist(result.item)

        if inWatchlist {
            HStack(spacing: 7) {
                PlanLightOutline()
                Text("Dans ta liste", bundle: .app)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Ink.ink2)
            }
            .frame(maxWidth: .infinity)
            .frame(height: Metrics.control)
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                    .stroke(Ink.rule, lineWidth: 1)
            )
        } else if isAddingToWatchlist {
            CinechillSpinner(size: 18)
                .frame(maxWidth: .infinity)
                .frame(height: Metrics.control)
                .overlay(
                    RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                        .stroke(Ink.ruleSet, lineWidth: 1)
                )
        } else {
            PlanSecondaryButton(title: String(localized: "Ajouter à ma liste", bundle: .app), height: Metrics.control) {
                isAddingToWatchlist = true
                libraryStore.addToWatchlist(result.item)
            }
        }
    }

    private func iconButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Ink.ink)
                .frame(width: Metrics.control, height: Metrics.control)
                .overlay(
                    RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                        .stroke(Ink.ruleSet, lineWidth: 1)
                )
        }
        .buttonStyle(PressableScaleStyle(scale: 0.96))
        .accessibilityLabel(label)
    }

    // MARK: - Actions

    private func openTrailer() {
        guard let appURL = result.trailerAppURL, let webURL = result.trailerURL else { return }
        if UIApplication.shared.canOpenURL(appURL) {
            UIApplication.shared.open(appURL)
        } else {
            openURL(webURL)
        }
    }

    /// Ouvre l'app native de la plateforme si elle est installée (ex. Netflix via `nflx://`),
    /// sinon retombe sur le site web du service.
    ///
    /// C'est le geste le plus proche d'un « je vais le voir » qu'on puisse observer :
    /// on le note ici, et c'est lui qui déclenchera la question du lendemain. Partir
    /// vers la bande-annonce ne compte pas — on hésite encore.
    private func openStreamingApp() {
        onLaunch?(result.item.tmdbId)
        for candidate in result.watchAppURLCandidates where UIApplication.shared.canOpenURL(candidate) {
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
                        reasons: ["SF / Fantastique", "2h+", "Disponible sur Netflix"],
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
