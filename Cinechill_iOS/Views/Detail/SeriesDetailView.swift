//
//  SeriesDetailView.swift
//  Cinechill_iOS
//

import SwiftUI

/// La fiche d'une série — un dossier, pas un objet qu'on range.
///
/// **Une saison est un film.** C'est elle qui se range, en galerie comme en
/// watchlist, et sa fiche est celle d'un film au mot près. La série n'a donc
/// pas d'état à elle : elle n'est jamais « en cours », ni vue, ni à voir. Elle
/// rassemble ses saisons et dit, pour chacune, ce que la bibliothèque en sait
/// — avec les marques de toute l'app : point plein pour ce qui est en galerie,
/// point creux pour ce qui est dans la file, rien pour le reste.
///
/// Le plancher agit sur **une seule saison**, celle qui est en jeu : la
/// première qui n'est pas encore vue. Et son libellé la nomme, parce qu'un
/// « Vu » sans complément serait ambigu sur un dossier.
struct SeriesDetailView: View {
    let item: MediaItem

    @EnvironmentObject private var libraryStore: LibraryStore
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    @State private var detail: TVSeriesDetail?
    @State private var loading = true
    @State private var errorMessage: String?
    @State private var scrollOffset: CGFloat = 0

    private let client = TVClient()

    var body: some View {
        ZStack(alignment: .top) {
            Ink.ground.ignoresSafeArea()
            content
            DetailCeiling(
                title: detail?.name ?? item.title,
                progress: DetailCeiling.progress(forOffset: scrollOffset),
                onBack: { dismiss() },
                onTrailer: trailerAction
            )
        }
        .safeAreaInset(edge: .bottom) { floor }
        .toolbar(.hidden, for: .navigationBar)
        .task { await load() }
        .task { await libraryStore.warmUpStatusEndpoint() }
    }

    // MARK: - Le contenu

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: HeroOffsetKey.self,
                        value: proxy.frame(in: .named("serie")).minY
                    )
                }
                .frame(height: 0)

                DetailHero(
                    backdropURL: detail?.backdropURL,
                    posterPath: detail?.posterPath ?? item.posterPath,
                    title: detail?.name ?? item.title,
                    tagline: detail?.tagline
                )
                generique

                if let remark {
                    HStack(alignment: .top, spacing: 11) {
                        PlanLight().padding(.top, 6)
                        Text(remark)
                            .planFont(13)
                            .foregroundStyle(Ink.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, Metrics.margin)
                    .padding(.top, 18)
                    .accessibilityElement(children: .combine)
                }

                if let providers = detail?.providers, !providers.isEmpty {
                    DetailProvidersRow(
                        providers: providers,
                        preferredIDs: libraryStore.preferredPlatformIDs,
                        title: detail?.name ?? item.title
                    )
                }

                if let detail, !detail.seasons.isEmpty {
                    seasonsSection(detail)
                }

                if let text = detail?.overview ?? item.overview, !text.isEmpty {
                    DetailSynopsis(text: text)
                }

                if let cast = detail?.cast, !cast.isEmpty {
                    DetailCast(cast: cast)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .planFont(12.5)
                        .foregroundStyle(Ink.warn)
                        .padding(.horizontal, Metrics.margin)
                        .padding(.top, 24)
                }
            }
            .padding(.bottom, 32)
        }
        .coordinateSpace(name: "serie")
        .onPreferenceChange(HeroOffsetKey.self) { scrollOffset = $0 }
        .ignoresSafeArea(edges: .top)
        .scrollIndicators(.hidden)
    }

    // MARK: - Le générique

    /// L'année, le nombre de saisons, deux genres, qui l'a créée, où elle passe.
    /// Jamais le mot « série » : le nombre de saisons le dit mieux.
    private var generique: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !facts.isEmpty {
                Text(facts)
                    .planLabel()
                    .foregroundStyle(Ink.ink2)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(alignment: .firstTextBaseline, spacing: 7) {
                if let rating = detail?.voteAverage ?? item.voteAverage, rating > 0 {
                    Text(rating.formatted(.number.precision(.fractionLength(1))))
                        .planTitle(22)
                        .monospacedDigit()
                        .foregroundStyle(Ink.ink)

                    Text(voteText)
                        .planFont(11)
                        .foregroundStyle(Ink.ink2)
                }

                Spacer(minLength: 0)

                if loading {
                    CinechillSpinner(size: 15)
                }
            }
        }
        .padding(.horizontal, Metrics.margin)
        .padding(.top, 20)
    }

    private var facts: String {
        var parts: [String] = []
        if let year = detail?.firstAirDate?.prefix(4) ?? item.releaseDate?.prefix(4), year.count == 4 {
            parts.append(String(year))
        }
        let released = releasedSeasons.count
        if released > 0 {
            parts.append(released == 1
                         ? String(localized: "1 saison", bundle: .app)
                         : String(localized: "\(released) saisons", bundle: .app))
        }
        if let genres = detail?.genreNames, !genres.isEmpty {
            parts.append(genres.prefix(2).joined(separator: ", "))
        }
        if let creator = detail?.creators.first { parts.append(creator) }
        if let network = detail?.networks.first { parts.append(network) }
        return parts.joined(separator: " · ")
    }

    private var voteText: String {
        guard let count = detail?.voteCount, count > 0 else { return String(localized: "/ 10", bundle: .app) }
        // Le nombre passe en `%@`, formaté : le catalogue ne peut pas en tirer le pluriel.
        if count == 1 { return String(localized: "/ 10 · 1 vote", bundle: .app) }
        return String(localized: "/ 10 · \(count.formatted(.number.grouping(.automatic))) votes", bundle: .app)
    }

    // MARK: - Ce que la bibliothèque en sait

    private var releasedSeasons: [TVSeasonListing] {
        (detail?.seasons ?? []).filter(\.isReleased)
    }

    private var owned: (gallery: [GalleryEntry], watchlist: [WatchlistEntry]) {
        libraryStore.seasons(ofSeries: item.tmdbId)
    }

    private var seenNumbers: Set<Int> {
        Set(owned.gallery.compactMap { $0.seasonFacts?.season })
    }

    private func queued(_ number: Int) -> WatchlistEntry? {
        owned.watchlist.first { $0.seasonFacts?.season == number }
    }

    /// La remarque : ce que la galerie sait déjà de cette série. Calculée en
    /// local, comme celle de la fiche film.
    private var remark: String? {
        let seen = seenNumbers.count
        guard seen > 0 else { return nil }
        let released = releasedSeasons.count
        if released > 0, seen >= released {
            return String(localized: "Tu as vu toutes ses saisons.", bundle: .app)
        }
        if seen == 1, let number = seenNumbers.first {
            return String(localized: "Tu as déjà vu sa saison \(number).", bundle: .app)
        }
        return String(localized: "Tu as déjà vu \(seen) de ses saisons.", bundle: .app)
    }

    // MARK: - Les saisons

    private func seasonsSection(_ detail: TVSeriesDetail) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            DetailSectionHeader(
                title: String(localized: "Les saisons", bundle: .app),
                trailing: String(detail.seasons.count)
            )

            ForEach(detail.seasons) { season in
                NavigationLink(destination: ItemDetailView(item: detail.item(for: season), showsSeriesLink: false)) {
                    seasonRow(season, isInPlay: season.number == seasonInPlay?.number)
                }
                .buttonStyle(.plain)

                PlanEdge().padding(.horizontal, Metrics.margin)
            }
        }
        .padding(.top, 24)
    }

    private func seasonRow(_ season: TVSeasonListing, isInPlay: Bool) -> some View {
        let isSeen = seenNumbers.contains(season.number)
        let entry = queued(season.number)

        return HStack(spacing: 12) {
            PosterTile(
                posterPath: season.posterPath ?? detail?.posterPath,
                title: String(localized: "Saison \(season.number)", bundle: .app),
                width: 34
            )
            .opacity(season.isReleased ? 1 : 0.5)

            VStack(alignment: .leading, spacing: 2) {
                Text("Saison \(season.number)", bundle: .app)
                    .planFont(13.5, weight: isInPlay ? .semibold : .regular)
                    .foregroundStyle(season.isReleased ? Ink.ink : Ink.ink2)

                Text(seasonLine(season, entry: entry))
                    .planFont(10.5)
                    .monospacedDigit()
                    .foregroundStyle(Ink.ink2)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Group {
                if isSeen {
                    PlanLight()
                } else if entry != nil {
                    PlanLightOutline()
                }
            }
            .frame(width: 10)

            DetailChevron()
                .stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                .foregroundStyle(Ink.ink3)
                .frame(width: 12, height: 12)
        }
        .padding(.horizontal, Metrics.margin)
        .padding(.vertical, 10)
        // La saison en jeu est la seule posée sur le fond levé : c'est sur
        // elle qu'agit le plancher.
        .background(isInPlay ? Ink.ground2 : .clear)
        .contentShape(Rectangle())
    }

    /// La seconde ligne d'une saison : ce qu'on sait d'elle, écrit, jamais
    /// mesuré. Pas de jauge — une mesure se lit comme un état.
    private func seasonLine(_ season: TVSeasonListing, entry: WatchlistEntry?) -> String {
        if !season.isReleased {
            if let date = season.airDate, let day = TVDate.shortDay(date) {
                return String(localized: "Le \(day)", bundle: .app)
            }
            return String(localized: "À venir", bundle: .app)
        }
        if let entry, entry.nextEpisode != nil {
            if let total = entry.seasonFacts?.episodes, total > 0 {
                return String(localized: "Épisode \(entry.episodeToPlay) sur \(total)", bundle: .app)
            }
            return String(localized: "Épisode \(entry.episodeToPlay)", bundle: .app)
        }
        // Zéro épisode connu n'est pas une donnée : on ne l'écrit pas.
        guard season.episodeCount > 0 else { return season.year ?? "" }
        let episodes = season.episodeCount == 1
            ? String(localized: "1 épisode", bundle: .app)
            : String(localized: "\(season.episodeCount) épisodes", bundle: .app)
        guard let year = season.year else { return episodes }
        return "\(year) · \(episodes)"
    }

    /// La première saison qui n'est pas encore vue, sortie ou annoncée.
    private var seasonInPlay: TVSeasonListing? {
        (detail?.seasons ?? []).first { !seenNumbers.contains($0.number) }
    }

    // MARK: - Le plancher

    @ViewBuilder
    private var floor: some View {
        if let detail, let season = seasonInPlay {
            let seasonItem = detail.item(for: season)
            let entry = queued(season.number)
            let waitingStatus = libraryStore.pendingStatus(for: seasonItem) != nil
            let waitingEpisode = entry.flatMap { libraryStore.pendingNextEpisode(for: $0) } != nil

            VStack(spacing: 0) {
                PlanEdge()

                Text(floorLabel(season, entry: entry))
                    .planLabel()
                    .monospacedDigit()
                    .foregroundStyle(Ink.ink2)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Metrics.margin)
                    .padding(.top, 12)

                HStack(spacing: Metrics.gutter) {
                    if let entry {
                        if !entry.isAwaitingEpisode {
                            DetailFloorButton(
                                title: String(localized: "J'ai vu l'épisode \(entry.episodeToPlay)", bundle: .app),
                                style: .paper,
                                isWaiting: waitingEpisode || waitingStatus
                            ) {
                                Haptics.impact(.medium)
                                advance(entry, item: seasonItem)
                            }
                        }
                        DetailFloorButton(
                            title: String(localized: "À voir", bundle: .app),
                            style: .inked,
                            mark: .planned,
                            isWaiting: waitingStatus && !waitingEpisode
                        ) {
                            Haptics.impact(.light)
                            libraryStore.removeFromWatchlist(seasonItem)
                        }
                    } else if season.isReleased {
                        DetailFloorButton(
                            title: String(localized: "Vue", bundle: .app),
                            isWaiting: libraryStore.pendingStatus(for: seasonItem) == .seen
                        ) {
                            Haptics.impact(.medium)
                            libraryStore.addToGallery(seasonItem)
                        }
                        DetailFloorButton(
                            title: String(localized: "À voir", bundle: .app),
                            isWaiting: libraryStore.pendingStatus(for: seasonItem) == .toWatch
                        ) {
                            Haptics.impact(.medium)
                            libraryStore.addToWatchlist(seasonItem)
                        }
                    } else {
                        // Une saison annoncée n'a qu'une issue. La mettre dans la
                        // file, c'est dire qu'on la regardera : elle y attendra,
                        // avec sa date, sans prétendre être disponible.
                        DetailFloorButton(
                            title: String(localized: "À voir", bundle: .app),
                            style: .paper,
                            isWaiting: waitingStatus
                        ) {
                            Haptics.impact(.medium)
                            libraryStore.addToWatchlist(seasonItem)
                        }
                    }
                }
                .padding(.horizontal, Metrics.margin)
                .padding(.top, 10)
                .padding(.bottom, 10)
                .disabled(waitingStatus || waitingEpisode)
            }
            .background(Ink.ground)
            .animation(Metrics.shift, value: entry?.nextEpisode)
            .animation(Metrics.shift, value: waitingStatus)
        }
    }

    private func floorLabel(_ season: TVSeasonListing, entry: WatchlistEntry?) -> String {
        if let entry {
            if entry.isAwaitingEpisode, let date = entry.seasonFacts?.nextAirDate,
               let day = TVDate.shortDay(date) {
                return String(localized: "Saison \(season.number) · épisode \(entry.episodeToPlay) le \(day)", bundle: .app)
            }
            if let total = entry.seasonFacts?.episodes, total > 0 {
                return String(localized: "Saison \(season.number) · épisode \(entry.episodeToPlay) sur \(total)", bundle: .app)
            }
            return String(localized: "Saison \(season.number) · épisode \(entry.episodeToPlay)", bundle: .app)
        }
        if !season.isReleased {
            if let date = season.airDate, let day = TVDate.shortDay(date) {
                return String(localized: "Saison \(season.number) · le \(day)", bundle: .app)
            }
            return String(localized: "Saison \(season.number) · à venir", bundle: .app)
        }
        switch season.episodeCount {
        case 0: return String(localized: "Saison \(season.number)", bundle: .app)
        case 1: return String(localized: "Saison \(season.number) · 1 épisode", bundle: .app)
        default: return String(localized: "Saison \(season.number) · \(season.episodeCount) épisodes", bundle: .app)
        }
    }

    /// Un épisode de plus. Passé le dernier, il n'y a plus d'épisode à lancer :
    /// c'est la saison qui est vue, et elle quitte la file pour la galerie.
    private func advance(_ entry: WatchlistEntry, item seasonItem: MediaItem) {
        if entry.isOnLastEpisode {
            libraryStore.addToGallery(seasonItem)
        } else {
            libraryStore.setNextEpisode(entry, to: entry.episodeToPlay + 1)
        }
    }

    // MARK: - Actions

    /// Le bouton de bande-annonce, s'il y en a une. Une propriété typée et non
    /// un ternaire dans `body` : mêler `nil` et une méthode isolée au main
    /// actor sous un `==` optionnel faisait renoncer le vérificateur de types
    /// de Xcode (« Failed to produce diagnostic »).
    private var trailerAction: (() -> Void)? {
        guard detail?.trailerKey != nil else { return nil }
        return { openTrailer() }
    }

    private func openTrailer() {
        guard let appURL = detail?.trailerAppURL, let webURL = detail?.trailerURL else { return }
        if UIApplication.shared.canOpenURL(appURL) {
            UIApplication.shared.open(appURL)
        } else {
            openURL(webURL)
        }
    }

    private func load() async {
        loading = true
        errorMessage = nil
        defer { loading = false }
        do {
            detail = try await client.series(id: item.tmdbId)
        } catch is CancellationError {
            return
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

/// Le chevron d'une ligne qui ouvre une fiche, dans l'écriture « La Gravure ».
struct DetailChevron: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.35, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.2, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.35, y: rect.maxY))
        return path
    }
}
