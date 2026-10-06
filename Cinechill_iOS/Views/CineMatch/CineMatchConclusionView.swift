//
//  CineMatchConclusionView.swift
//  Cinechill_iOS
//

import SwiftUI

/// La conclusion : le film lancé, et la galerie pour plus tard.
///
/// « Démarrer le film » ouvre la plateforme ; c'est cet écran qu'on retrouve
/// en revenant. Il ne demande rien ce soir. L'appréciation monte quand le
/// choix est définitif, et personne ne le prévoit : l'écran ferme donc la
/// recherche au lieu de proposer d'y revenir, souhaite un bon film, et garde
/// la galerie pour quand le film aura été vu.
///
/// **L'ajout attend sa confirmation avant de se dire fait** : la requête part,
/// le bouton dit qu'il enregistre, et « Ajouté à ta galerie » n'apparaît qu'une
/// fois que la galerie le contient réellement.
///
/// **Une série ne se range pas en galerie** : on vient de la commencer. Sa
/// saison 1 est partie dans la file au moment de « Je la commence », et
/// l'écran attend de l'y voir avant de le dire, de la même façon.
struct CineMatchConclusionView: View {
    let viewModel: CineMatchViewModel

    @EnvironmentObject private var libraryStore: LibraryStore
    @Environment(MediaCatalog.self) private var catalog

    /// Le plafond d'attente de la confirmation. Au-delà, l'écriture est
    /// considérée comme perdue et on le dit, plutôt que de tourner sans fin.
    private static let confirmationTimeout: Duration = .seconds(8)

    init(viewModel: CineMatchViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        Group {
            if let film = viewModel.concludedFilm {
                content(film)
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Ink.ground)
    }

    private func content(_ film: CineMatchFilm) -> some View {
        VStack(spacing: 0) {
            poster(film)

            VStack(spacing: 0) {
                Group {
                    if film.isSeries {
                        Text("Bonne série !", bundle: .app)
                    } else {
                        Text("Bon film !", bundle: .app)
                    }
                }
                    .planTitle(32)
                    .foregroundStyle(Ink.ink)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)

                meta(film)
                    .padding(.top, 9)
            }
            .padding(.top, 20)

            Group {
                if film.isSeries {
                    seriesFooter(film)
                } else {
                    footer(film)
                }
            }
            .padding(.top, 22)
        }
        .padding(.horizontal, Metrics.margin)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    // MARK: - L'affiche

    private func poster(_ film: CineMatchFilm) -> some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)

        return GeometryReader { proxy in
            let height = max(0, min(proxy.size.height, proxy.size.width * 1.5))
            PosterImageView(url: film.item.posterURL, contentMode: .fill)
                .frame(width: height / 1.5, height: height)
                .clipShape(shape)
                .overlay(shape.strokeBorder(Ink.rule, lineWidth: 1))
                // La seule ombre portée de l'application : elle détache l'objet
                // que l'écran vient de trouver.
                .shadow(color: CinechillPalette.nightDeep.opacity(0.55), radius: 12, y: 6)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .bottom)
        }
        .frame(minHeight: 110)
        .accessibilityHidden(true)
    }

    // MARK: - Le film

    private func meta(_ film: CineMatchFilm) -> some View {
        let platform = platform(for: film)

        return HStack(spacing: 0) {
            Text(film.item.title)
                .planFont(13, weight: .medium)
                .foregroundStyle(Ink.ink)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            if let runtime = film.runtimeMinutes, runtime > 0 {
                separator
                Text(verbatim: Self.format(runtime))
                    .planFont(13)
                    .monospacedDigit()
                    .foregroundStyle(Ink.ink2)
            }

            if let platform {
                separator
                logo(platform)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var separator: some View {
        Text(verbatim: "·")
            .planFont(13)
            .foregroundStyle(Ink.ink3)
            .padding(.horizontal, 6)
            .accessibilityHidden(true)
    }

    private func logo(_ platform: StreamingPlatform) -> some View {
        Group {
            if let url = platform.logoURL {
                PosterImageView(url: url)
            } else {
                Text(verbatim: platform.shortLabel)
                    .planFont(8, weight: .semibold)
                    .foregroundStyle(Ink.ink2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Ink.ground3)
            }
        }
        .frame(width: 18, height: 18)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous))
        .accessibilityElement()
        .accessibilityLabel(platform.name)
    }

    // MARK: - La galerie

    private func footer(_ film: CineMatchFilm) -> some View {
        let state = viewModel.galleryAddState
        let isAdded = state == .added

        return VStack(spacing: 6) {
            Text(note(for: state))
                .planFont(13)
                .foregroundStyle(Ink.ink2)
                .lineSpacing(2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 8)
                .contentTransition(.opacity)

            if isAdded {
                HStack(spacing: 9) {
                    PlanLight()
                    Text("Ajouté à ta galerie", bundle: .app)
                        .planFont(15, weight: .medium)
                        .foregroundStyle(Ink.ink)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: Metrics.button)
                .overlay(
                    RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                        .strokeBorder(Ink.ruleSet, lineWidth: 1)
                )
                .accessibilityElement(children: .combine)
                .transition(.opacity)
            } else {
                PlanButton(
                    title: String(localized: "Ajouter à ma galerie", bundle: .app),
                    loadingTitle: String(localized: "Enregistrement…", bundle: .app),
                    isLoading: state == .adding
                ) {
                    addToGallery(film)
                }
            }

            Button {
                viewModel.backToHome()
            } label: {
                Text("Retour à l'accueil", bundle: .app)
                    .planFont(13.5, weight: .medium)
                    .foregroundStyle(Ink.ink2)
                    .padding(.horizontal, 18)
                    .frame(minHeight: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(state == .adding)
        }
        .animation(Metrics.shift, value: state)
    }

    private func note(for state: CineMatchViewModel.GalleryAddState) -> String {
        switch state {
        case .added:
            String(localized: "Il comptera dans tes prochaines propositions.", bundle: .app)
        case .failed:
            String(localized: "Le film n'a pas été ajouté. Réessaie.", bundle: .app)
        case .idle, .adding:
            String(localized: "Une fois que tu l'as vu, ajoute-le à ta galerie. Tes prochaines propositions en tiendront compte.", bundle: .app)
        }
    }

    /// La requête part, puis on attend que la galerie contienne vraiment le
    /// film : c'est le listener de la bibliothèque, et non le retour de la
    /// requête, qui rend l'ajout visible partout ailleurs.
    private func addToGallery(_ film: CineMatchFilm) {
        guard viewModel.galleryAddState != .adding else { return }
        viewModel.beginGalleryAdd()
        libraryStore.addToGallery(film.item)

        Task {
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: Self.confirmationTimeout)
            while !libraryStore.isInGallery(film.item), clock.now < deadline {
                try? await Task.sleep(for: .milliseconds(150))
            }
            let confirmed = libraryStore.isInGallery(film.item)
            if confirmed { Haptics.success() }
            viewModel.finishGalleryAdd(success: confirmed)
        }
    }

    // MARK: - La file, pour une série

    private func seriesFooter(_ film: CineMatchFilm) -> some View {
        let state = viewModel.galleryAddState
        let queued = libraryStore.watchlistEntry(for: film.firstSeason)

        return VStack(spacing: 6) {
            Text(seriesNote(queued: queued != nil, state: state))
                .planFont(13)
                .foregroundStyle(Ink.ink2)
                .lineSpacing(2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 8)
                .contentTransition(.opacity)

            if let queued {
                HStack(spacing: 9) {
                    PlanLight()
                    Text("Dans ta watchlist : saison 1, épisode \(queued.episodeToPlay)", bundle: .app)
                        .planFont(15, weight: .medium)
                        .foregroundStyle(Ink.ink)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: Metrics.button)
                .overlay(
                    RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                        .strokeBorder(Ink.ruleSet, lineWidth: 1)
                )
                .accessibilityElement(children: .combine)
                .transition(.opacity)
            } else {
                PlanButton(
                    title: String(localized: "Ajouter à ma watchlist", bundle: .app),
                    loadingTitle: String(localized: "Enregistrement…", bundle: .app),
                    isLoading: state == .adding
                ) {
                    queueFirstSeason(film, write: true)
                }
            }

            Button {
                viewModel.backToHome()
            } label: {
                Text("Retour à l'accueil", bundle: .app)
                    .planFont(13.5, weight: .medium)
                    .foregroundStyle(Ink.ink2)
                    .padding(.horizontal, 18)
                    .frame(minHeight: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(state == .adding)
        }
        .animation(Metrics.shift, value: queued != nil)
        .animation(Metrics.shift, value: state)
        // L'écriture est partie avec « Je la commence » : on attend seulement
        // de la voir arriver.
        .task(id: film.id) { queueFirstSeason(film, write: false) }
    }

    private func seriesNote(queued: Bool, state: CineMatchViewModel.GalleryAddState) -> String {
        if queued {
            return String(localized: "On garde l'épisode à lancer dans ta watchlist.", bundle: .app)
        }
        if state == .failed {
            return String(localized: "La saison 1 n'a pas été ajoutée à ta watchlist. Réessaie.", bundle: .app)
        }
        return String(localized: "On met la saison 1 dans ta watchlist, à son premier épisode.", bundle: .app)
    }

    /// Attend que la saison 1 soit dans la file. `write` relance l'écriture,
    /// pour le bouton qui suit un échec.
    private func queueFirstSeason(_ film: CineMatchFilm, write: Bool) {
        let season = film.firstSeason
        guard libraryStore.watchlistEntry(for: season) == nil,
              viewModel.galleryAddState != .adding
        else { return }
        viewModel.beginGalleryAdd()
        if write { libraryStore.addToWatchlist(season, nextEpisode: 1) }

        Task {
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: Self.confirmationTimeout)
            while libraryStore.watchlistEntry(for: season) == nil, clock.now < deadline {
                try? await Task.sleep(for: .milliseconds(150))
            }
            let confirmed = libraryStore.watchlistEntry(for: season) != nil
            if confirmed && write { Haptics.success() }
            viewModel.finishGalleryAdd(success: confirmed)
        }
    }

    // MARK: - Ce que l'écran affiche

    private func platform(for film: CineMatchFilm) -> StreamingPlatform? {
        let situation = viewModel.situation.platformIDs
        let preferred = situation.isEmpty ? Array(libraryStore.preferredPlatformIDs).sorted() : situation
        guard let providerID = film.providerID(preferring: preferred) else { return nil }
        return catalog.platform(forProvider: providerID)
    }

    /// « 1h52 » : des chiffres, pas une phrase, donc rien à traduire.
    private static func format(_ minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        return hours > 0 ? "\(hours)h\(String(format: "%02d", rest))" : "\(rest) min"
    }
}
