//
//  SeasonDetailView.swift
//  Cinechill_iOS
//

import SwiftUI

/// La fiche d'une saison — la fiche d'un film, au mot près.
///
/// Une saison a une année, des épisodes, une affiche, une note et une fin :
/// c'est un objet fini, et elle se range exactement comme un film. Même héros,
/// mêmes plateformes, même plancher : « Vue » la range en galerie d'un seul
/// tap, épisodes ou pas ; « À voir » la met dans la file.
///
/// La liste des épisodes ne sert qu'à une chose : dire lequel lancer. Un tap
/// sur une ligne le pose. Ce n'est pas un état de la saison — elle reste « à
/// voir » tant qu'elle n'est pas vue — mais la description de la prochaine
/// soirée, comme la durée ou la plateforme d'une ligne de film.
struct SeasonDetailView: View {
    let item: MediaItem
    let season: Int
    var showsSeriesLink = true

    @EnvironmentObject private var libraryStore: LibraryStore
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    @State private var series: TVSeriesDetail?
    @State private var detail: TVSeasonDetail?
    @State private var loading = true
    @State private var errorMessage: String?
    @State private var scrollOffset: CGFloat = 0

    private let client = TVClient()

    private var title: String {
        String(localized: "Saison \(season)", bundle: .app)
    }

    private var seriesName: String {
        series?.name ?? item.title
    }

    /// La saison, telle qu'elle se range. Le serveur complète le reste.
    private var seasonItem: MediaItem {
        MediaItem(
            tmdbId: item.tmdbId,
            mediaType: .tv,
            title: seriesName,
            posterPath: detail?.posterPath ?? item.posterPath,
            overview: detail?.overview ?? item.overview,
            voteAverage: detail?.voteAverage ?? item.voteAverage,
            voteCount: nil,
            genreIds: series?.genreIds ?? item.genreIds,
            releaseDate: detail?.airDate ?? item.releaseDate,
            season: season
        )
    }

    private var isSeen: Bool { libraryStore.isInGallery(seasonItem) }
    private var queuedEntry: WatchlistEntry? { libraryStore.watchlistEntry(for: seasonItem) }

    /// Sortie, ou au moins commencée. Une saison annoncée n'a qu'une issue.
    private var isReleased: Bool {
        guard let airDate = detail?.airDate ?? item.releaseDate else { return detail == nil }
        return airDate <= TVDate.today
    }

    var body: some View {
        ZStack(alignment: .top) {
            Ink.ground.ignoresSafeArea()
            content
            DetailCeiling(
                title: title,
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
                        value: proxy.frame(in: .named("saison")).minY
                    )
                }
                .frame(height: 0)

                DetailHero(
                    backdropURL: series?.backdropURL,
                    posterPath: detail?.posterPath ?? item.posterPath,
                    title: title,
                    eyebrow: seriesName
                )
                generique

                if showsSeriesLink {
                    seriesLink
                }

                if let providers = series?.providers, !providers.isEmpty {
                    DetailProvidersRow(
                        providers: providers,
                        preferredIDs: libraryStore.preferredPlatformIDs,
                        title: seriesName
                    )
                }

                if let episodes = detail?.episodes, !episodes.isEmpty {
                    episodesSection(episodes)
                }

                if let text = detail?.overview ?? series?.overview, !text.isEmpty {
                    DetailSynopsis(text: text)
                }

                if let cast = series?.cast, !cast.isEmpty {
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
        .coordinateSpace(name: "saison")
        .onPreferenceChange(HeroOffsetKey.self) { scrollOffset = $0 }
        .ignoresSafeArea(edges: .top)
        .scrollIndicators(.hidden)
    }

    // MARK: - Le générique

    /// L'année, le nombre d'épisodes, la durée d'un épisode : les faits d'un
    /// film, ramenés à la saison.
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

                    Text("/ 10", bundle: .app)
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
        if let year = (detail?.airDate ?? item.releaseDate)?.prefix(4), year.count == 4 {
            parts.append(String(year))
        }
        if let count = detail?.episodes.count, count > 0 {
            parts.append(count == 1
                         ? String(localized: "1 épisode", bundle: .app)
                         : String(localized: "\(count) épisodes", bundle: .app))
        }
        if let runtime = detail?.episodeRunTime, runtime > 0 {
            parts.append(String(localized: "\(runtime) min par épisode", bundle: .app))
        }
        return parts.joined(separator: " · ")
    }

    /// Le chemin vers le dossier. On arrive le plus souvent ici depuis la
    /// watchlist ou la galerie, qui rangent la saison ; c'est d'ici qu'on
    /// rejoint les autres.
    private var seriesLink: some View {
        NavigationLink(destination: ItemDetailView(item: item.seriesItem)) {
            HStack(spacing: 10) {
                Text("Toutes les saisons", bundle: .app)
                    .planFont(13)
                    .foregroundStyle(Ink.ink2)
                Spacer(minLength: 8)
                DetailChevron()
                    .stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(Ink.ink3)
                    .frame(width: 12, height: 12)
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .overlay(alignment: .top) { PlanEdge() }
            .overlay(alignment: .bottom) { PlanEdge() }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Metrics.margin)
        .padding(.top, 20)
    }

    // MARK: - Les épisodes

    private func episodesSection(_ episodes: [TVEpisode]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            DetailSectionHeader(
                title: String(localized: "Les épisodes", bundle: .app),
                // La consigne n'a de sens que si l'on peut encore choisir.
                trailing: isSeen ? nil : String(localized: "Touche celui à lancer", bundle: .app)
            )

            ForEach(episodes) { episode in
                episodeRow(episode)
                PlanEdge().padding(.horizontal, Metrics.margin)
            }
        }
        .padding(.top, 24)
    }

    private func episodeRow(_ episode: TVEpisode) -> some View {
        let toPlay = queuedEntry.map { libraryStore.pendingNextEpisode(for: $0) ?? $0.episodeToPlay }
        let isPast = isSeen || (toPlay.map { episode.number < $0 } ?? false)
        let isNext = !isSeen && toPlay == episode.number
        let isTappable = !isSeen && episode.isReleased

        return Button {
            guard isTappable else { return }
            Haptics.selection()
            setEpisodeToPlay(episode.number)
        } label: {
            HStack(spacing: 11) {
                Text(verbatim: "\(episode.number)")
                    .planLabel()
                    .monospacedDigit()
                    .foregroundStyle(isNext ? Ink.ink : Ink.ink3)
                    .frame(width: 20, alignment: .leading)

                Text(episode.name.isEmpty
                     ? String(localized: "Épisode \(episode.number)", bundle: .app)
                     : episode.name)
                    .planFont(13.5, weight: isNext ? .semibold : .regular)
                    .foregroundStyle(Ink.ink)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text(episodeNote(episode))
                    .planFont(10.5)
                    .monospacedDigit()
                    .foregroundStyle(Ink.ink2)

                // Plein : vu. Creux : celui à lancer — c'est lui qui est dans la
                // file. Rien : ce qui reste. Le vocabulaire des affiches.
                Group {
                    if isPast {
                        PlanLight()
                    } else if isNext {
                        PlanLightOutline()
                    }
                }
                .frame(width: 8)
            }
            .padding(.horizontal, Metrics.margin)
            .padding(.vertical, 10)
            .background(isNext ? Ink.ground2 : .clear)
            .opacity(episode.isReleased ? 1 : 0.45)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isTappable)
        .accessibilityAddTraits(isNext ? [.isSelected] : [])
    }

    /// La durée d'un épisode sorti, la date d'un épisode à venir.
    private func episodeNote(_ episode: TVEpisode) -> String {
        if !episode.isReleased {
            if let date = episode.airDate, let day = TVDate.shortDay(date) { return day }
            return String(localized: "À venir", bundle: .app)
        }
        guard let runtime = episode.runtime, runtime > 0 else { return "" }
        return String(localized: "\(runtime) min", bundle: .app)
    }

    /// Le tap sur un épisode : il devient celui à lancer. Si la saison n'est
    /// pas encore dans la file, elle y entre du même geste — un seul appel.
    private func setEpisodeToPlay(_ number: Int) {
        if let entry = queuedEntry {
            libraryStore.setNextEpisode(entry, to: number)
        } else {
            libraryStore.addToWatchlist(seasonItem, nextEpisode: number)
        }
    }

    // MARK: - Le plancher

    /// Le plancher d'un film. « Vue » et « À voir » se retirent en les
    /// retouchant ; le cœur n'apparaît qu'une fois la saison vue. Pas de
    /// recommandation : elle viendra avec les séries dans le Hall.
    private var floor: some View {
        let pending = libraryStore.pendingStatus(for: seasonItem)
        let isQueued = queuedEntry != nil

        return VStack(spacing: 0) {
            PlanEdge()

            HStack(spacing: Metrics.gutter) {
                if isReleased {
                    DetailFloorButton(
                        title: String(localized: "Vue", bundle: .app),
                        style: isSeen ? .inked : .line,
                        mark: isSeen ? .acquired : .none,
                        isWaiting: pending != nil && (pending == .seen || isSeen)
                    ) {
                        Haptics.impact(isSeen ? .light : .medium)
                        if isSeen {
                            libraryStore.removeFromGallery(seasonItem)
                        } else {
                            libraryStore.addToGallery(seasonItem)
                        }
                    }
                }

                DetailFloorButton(
                    title: String(localized: "À voir", bundle: .app),
                    style: isQueued ? .inked : (isReleased ? .line : .paper),
                    mark: isQueued ? .planned : .none,
                    isWaiting: pending != nil && (pending == .toWatch || isQueued)
                ) {
                    Haptics.impact(isQueued ? .light : .medium)
                    if isQueued {
                        libraryStore.removeFromWatchlist(seasonItem)
                    } else {
                        libraryStore.addToWatchlist(seasonItem)
                    }
                }

                if isSeen {
                    loveButton
                }
            }
            .padding(.horizontal, Metrics.margin)
            .padding(.top, 14)
            .padding(.bottom, 10)
            .disabled(pending != nil)
        }
        .background(Ink.ground)
        .animation(Metrics.shift, value: isSeen)
        .animation(Metrics.shift, value: isQueued)
    }

    /// Le coup de cœur, comme sur la fiche film. Il se pose sur une saison —
    /// « la saison 3 de Fargo » est un souvenir plus juste que « Fargo » — et
    /// ne compte pas pour la Porte, qui ne compte que des films.
    private var loveButton: some View {
        let loved = libraryStore.isLoved(seasonItem)
        let isPending = libraryStore.pendingLoveByItemID[seasonItem.id] != nil

        return Button {
            Haptics.impact(.light, intensity: loved ? 0.5 : 0.8)
            libraryStore.setLove(seasonItem, loved: !loved)
        } label: {
            DetailHeartShape()
                .stroke(
                    loved ? Color(hex: 0xC25562) : Ink.ink,
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                )
                .background(
                    DetailHeartShape()
                        .fill(loved ? Color(hex: 0xC25562) : .clear)
                )
                .frame(width: 18, height: 16)
                .frame(width: 48, height: Metrics.control)
                .overlay(
                    RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                        .strokeBorder(Ink.ruleSet, lineWidth: 1)
                )
                .opacity(isPending ? 0.6 : 1)
        }
        .buttonStyle(PressableScaleStyle(scale: 0.94))
        .transition(.opacity)
        .accessibilityLabel(
            loved
                ? String(localized: "Retirer le coup de cœur", bundle: .app)
                : String(localized: "Coup de cœur", bundle: .app)
        )
    }

    // MARK: - Chargement

    /// Le bouton de bande-annonce, s'il y en a une. Une propriété typée et non
    /// un ternaire dans `body` : mêler `nil` et une méthode isolée au main
    /// actor sous un `==` optionnel faisait renoncer le vérificateur de types
    /// de Xcode (« Failed to produce diagnostic »).
    private var trailerAction: (() -> Void)? {
        guard series?.trailerKey != nil else { return nil }
        return { openTrailer() }
    }

    private func openTrailer() {
        guard let appURL = series?.trailerAppURL, let webURL = series?.trailerURL else { return }
        if UIApplication.shared.canOpenURL(appURL) {
            UIApplication.shared.open(appURL)
        } else {
            openURL(webURL)
        }
    }

    /// La série et la saison en parallèle : la première porte les plateformes,
    /// le casting et le backdrop ; la seconde, les épisodes. Les deux passent
    /// par le cache du serveur, et la série y est presque toujours déjà.
    private func load() async {
        loading = true
        errorMessage = nil
        defer { loading = false }
        async let seriesResult = try? client.series(id: item.tmdbId)
        do {
            detail = try await client.season(tvId: item.tmdbId, season: season)
        } catch is CancellationError {
            return
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        series = await seriesResult
    }
}
