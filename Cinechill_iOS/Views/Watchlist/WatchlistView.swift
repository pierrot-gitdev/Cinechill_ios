//
//  WatchlistView.swift
//  Cinechill_iOS
//

import SwiftUI

/// La watchlist — « La Séance ».
///
/// Rien n'est trié par date d'ajout, parce que ce n'est pas la question qu'on
/// se pose devant sa watchlist. Tout converge vers un seul choix : le temps
/// qu'on a, ce qu'on peut lancer maintenant, et une proposition à trancher.
struct WatchlistView: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    /// Les tailles d'accessibilité réorganisent les lignes plutôt que de les tronquer.
    private var isLargeType: Bool { typeSize.isAccessibilitySize }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var model: WatchlistViewModel
    @Binding var selectedTab: Int

    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var libraryStore: LibraryStore
    @EnvironmentObject private var profileStore: UserProfileStore
    @EnvironmentObject private var socialStore: SocialStore
    @Environment(BadgesViewModel.self) private var badgesModel
    @Environment(MediaCatalog.self) private var catalog
    @Environment(OnboardingTour.self) private var tour

    @State private var showProfile = false
    @State private var showPlatformSheet = false
    /// Le film dont on veut voir la fiche, posé par un tap sur sa ligne.
    @State private var opened: MediaItem?

    var body: some View {
        NavigationStack {
            ZStack {
                Ink.ground.ignoresSafeArea()

                if displayedEntries.isEmpty {
                    emptyState.padding(.horizontal, 34)
                } else {
                    content
                }
            }
            .safeAreaInset(edge: .top) {
                AppHeaderView(title: String(localized: "Watchlist", bundle: .app), onProfileTap: { showProfile = true })
            }
            .navigationBarHidden(true)
            .navigationDestination(item: $opened) { item in
                ItemDetailView(item: item)
            }
            .fullScreenCover(isPresented: $showProfile) {
                ProfileView(badgesModel: badgesModel)
                    .environmentObject(profileStore)
                    .environmentObject(libraryStore)
                    .environmentObject(authService)
                    .environmentObject(socialStore)
            }
            .sheet(isPresented: $showPlatformSheet) {
                PlatformPickerSheet()
                    .environmentObject(libraryStore)
                    .environment(catalog)
            }
        }
        .onAppear {
            model.prepare(
                entries: displayedEntries,
                preferredPlatformIDs: libraryStore.preferredPlatformIDs,
                platforms: catalog.platforms
            )
        }
        .task {
            await catalog.loadIfNeeded()
            await syncModel()
        }
        .onChange(of: libraryStore.watchlistItems) { _, _ in Task { await syncModel() } }
        .onChange(of: libraryStore.preferredPlatformIDs) { _, _ in Task { await syncModel() } }
        .onChange(of: catalog.platforms) { _, _ in Task { await syncModel() } }
        .onChange(of: tour.isRunning) { _, _ in Task { await syncModel() } }
    }

    /// Ce que la liste range. Pendant la prise en main, trois films d'exemple :
    /// l'étape a le tri par temps disponible à montrer, et un écran vide ne
    /// montre aucun tri. Rien n'est écrit nulle part.
    private var displayedEntries: [WatchlistEntry] {
        tour.isRunning ? OnboardingShowcase.watchlist : libraryStore.watchlistItems
    }

    private func syncModel() async {
        await model.update(
            entries: displayedEntries,
            preferredPlatformIDs: libraryStore.preferredPlatformIDs,
            platforms: catalog.platforms,
            enrich: !tour.isRunning
        )
    }

    // MARK: - Contenu

    /// Typée plutôt qu'un ternaire `nil`/méthode dans le `body`, que le
    /// solveur de types de Xcode ne résout pas toujours.
    private var rejectTonightAction: (() -> Void)? {
        guard model.tonightHasAlternative else { return nil }
        return { rejectTonight() }
    }

    private func rejectTonight() {
        Haptics.impact(.light)
        withAnimation(.spring(response: 0.34, dampingFraction: 0.8)) {
            model.rejectTonight()
        }
    }

    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                budgetPicker

                if let pick = model.tonight {
                    TonightCardView(
                        pick: pick,
                        platformName: platformName(for: pick.item),
                        onWatch: { watch(pick.item) },
                        onReject: rejectTonightAction
                    )
                    .padding(.horizontal, Metrics.margin)
                    .padding(.bottom, 6)
                    .transition(.opacity)
                    .id(pick.item.id)
                }

                if libraryStore.preferredPlatformIDs.isEmpty {
                    declarePlatformsBanner
                }

                ForEach(model.groups) { group in
                    groupSection(group)
                }

                budgetFooter
            }
            .padding(.bottom, 24)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: model.budget)
    }

    private var budgetPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Text("Combien de temps ce soir ?", bundle: .app)
                    .planLabel()
                    .foregroundStyle(Ink.ink2)

                if model.isEnriching {
                    CinechillSpinner(size: 14)
                }
            }

            HStack(spacing: 7) {
                ForEach(TimeBudget.allCases) { budget in
                    PlanChip(title: budget.label, isOn: model.budget == budget) {
                        Haptics.selection()
                        model.budget = budget
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, Metrics.margin)
        .padding(.top, 18)
        .padding(.bottom, 16)
    }

    /// Sans plateforme déclarée, « Disponible chez vous » ne peut rien vouloir
    /// dire : on le remplace par l'invitation à les déclarer, plutôt que
    /// d'afficher un groupe systématiquement vide.
    /// Une invitation n'est pas une carte : c'est une ligne, entre deux filets,
    /// précédée du point. Le même dispositif que la remarque de la fiche film.
    ///
    /// Elle ouvre le sélecteur, et non le profil. Elle y menait auparavant, ce
    /// qui obligeait à traverser le profil puis les réglages pour trouver la
    /// grille — trois écrans pour une invitation qui tient en un tap.
    /// `PlatformPickerSheet` est le sélecteur unique de l'application ;
    /// l'accueil l'ouvre déjà directement.
    private var declarePlatformsBanner: some View {
        Button {
            showPlatformSheet = true
        } label: {
            HStack(alignment: .top, spacing: 11) {
                PlanLight().padding(.top, 6)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Choisis tes plateformes", bundle: .app)
                        .planFont(13, weight: .medium)
                        .foregroundStyle(Ink.ink)
                    Text("Pour savoir ce que tu peux regarder tout de suite.", bundle: .app)
                        .planFont(11.5)
                        .foregroundStyle(Ink.ink2)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
            .overlay(alignment: .top) { PlanEdge() }
            .overlay(alignment: .bottom) { PlanEdge() }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Metrics.margin)
        .padding(.top, 8)
    }

    private func groupSection(_ group: WatchlistGroup) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(group.title)
                    .planLabel()
                    .foregroundStyle(headerTint(for: group.kind))

                Spacer(minLength: 0)

                if group.kind == .dormant {
                    Button {
                        Haptics.selection()
                        withAnimation(Metrics.unfold) { model.isTriaging.toggle() }
                    } label: {
                        Text(model.isTriaging ? String(localized: "Terminé", bundle: .app) : String(localized: "Faire le tri", bundle: .app))
                            .planFont(12)
                            .foregroundStyle(Ink.ink2)
                            .overlay(alignment: .bottom) {
                                Rectangle().fill(Ink.ruleSet).frame(height: 1).offset(y: 2)
                            }
                            .contentShape(Rectangle().inset(by: -10))
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(verbatim: "\(group.items.count)")
                        .planLabel()
                        .monospacedDigit()
                        .foregroundStyle(Ink.ink2)
                }
            }
            .padding(.horizontal, Metrics.margin)
            .padding(.top, 18)
            .padding(.bottom, 8)

            ForEach(group.items) { item in
                // Vers la gauche on l'a vu, vers la droite on n'en veut plus.
                let carriesCross = group.kind == .dormant && model.isTriaging

                PlanSwipeRow(
                    trailing: trailingAction(for: item),
                    leading: PlanRowAction(
                        label: String(localized: "Retirer", bundle: .app),
                        tint: Ink.warn,
                        isFilled: false
                    ) {
                        libraryStore.removeFromWatchlist(item.entry.mediaItem)
                    },
                    // La fiche s'ouvre au tap seul. Un `NavigationLink` est un
                    // bouton : il s'armait au contact et partait même quand le
                    // doigt avait amorcé un glissement, si bien qu'un film
                    // qu'on hésitait à trier ouvrait sa fiche.
                    onTap: { opened = item.entry.mediaItem },
                    // Pendant le tri, la croix de retrait prend la main : la
                    // surcouche du glissement la recouvrirait.
                    isEnabled: !carriesCross
                ) {
                    row(item, isDormant: group.kind == .dormant)
                }
            }
        }
    }

    /// La lumière signale ce qui vient d'un ami, l'écart ce qui dort depuis trop
    /// longtemps. Ce sont les deux seuls en-têtes teintés de l'écran, et ce sont
    /// les deux seules teintes du système — l'orange d'iOS a laissé la place.
    private func headerTint(for kind: WatchlistGroup.Kind) -> Color {
        switch kind {
        case .recommended: Ink.light
        case .dormant: Ink.warn
        default: Ink.ink3
        }
    }

    private func row(_ item: WatchlistItem, isDormant: Bool) -> some View {
        HStack(spacing: 11) {
            Group {
                HStack(spacing: 11) {
                    // Sur une ligne de 30 pt, un visage se lit plus vite
                    // qu'une vignette d'affiche : l'avatar prend sa place
                    // quand le film vient de quelqu'un.
                    if item.entry.isRecommended {
                        HallAvatarStack(recommenders: item.entry.recommendedBy, size: 30)
                    } else {
                        PosterTile(
                            posterPath: item.entry.posterPath,
                            title: item.entry.title,
                            width: 30
                        )
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        // Aux tailles d'accessibilité, le titre prend la place
                        // qu'il lui faut : sur une ligne, il ne restait que
                        // quelques lettres.
                        Text(item.entry.title)
                            .planFont(13.5)
                            .foregroundStyle(Ink.ink)
                            .lineLimit(isLargeType ? 3 : 1)

                        // Pour une saison, la seconde ligne dit quoi lancer :
                        // c'est plus utile que la provenance, que l'avatar
                        // porte déjà.
                        if let line = seasonLine(for: item) ?? item.entry.recommendedByText {
                            Text(line)
                                .planFont(10.5)
                                .monospacedDigit()
                                .foregroundStyle(Ink.ink2)
                                .lineLimit(isLargeType ? 2 : 1)
                                // Coupé au milieu : un nom long mangeait « et 1 autre ».
                                .truncationMode(.middle)
                        }

                        // La durée passe sous le titre quand le texte est très
                        // grand : à droite, elle lui volait la moitié de la ligne.
                        if isLargeType, !isWriting(item), let runtime = item.runtimeText {
                            Text(runtime)
                                .planFont(10.5)
                                .monospacedDigit()
                                .foregroundStyle(Ink.ink2)
                        }
                    }

                    Spacer(minLength: 4)

                    // L'épisode suivant n'est montré qu'une fois écrit : d'ici
                    // là, l'attente se lit à la place de la durée.
                    if isWriting(item) {
                        CinechillSpinner(size: 12)
                    } else if !isLargeType, let runtime = item.runtimeText {
                        Text(runtime)
                            .planFont(10.5)
                            .monospacedDigit()
                            .foregroundStyle(Ink.ink2)
                    }

                    platformBadge(for: item)
                }
                .contentShape(Rectangle())
            }

            if isDormant, model.isTriaging {
                Button {
                    Haptics.impact(.light)
                    libraryStore.removeFromWatchlist(item.entry.mediaItem)
                } label: {
                    WatchlistRemoveGlyph()
                        .stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                        .foregroundStyle(Ink.warn)
                        .frame(width: 12, height: 12)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableScaleStyle(scale: 0.9))
                .transition(.opacity)
                .accessibilityLabel(String(localized: "Retirer \(item.entry.title) de la watchlist", bundle: .app))
            }
        }
        .padding(.horizontal, Metrics.margin)
        .padding(.vertical, 6)
    }

    // MARK: - Les saisons

    /// « Saison 2 · épisode 5 sur 10 ». Écrit, jamais mesuré : une jauge se
    /// lirait comme un état, et la saison n'en a qu'un — à voir.
    private func seasonLine(for item: WatchlistItem) -> String? {
        guard let facts = item.entry.seasonFacts else { return nil }
        let season = facts.season
        let episode = item.entry.episodeToPlay
        if item.isAwaitingEpisode {
            if let date = item.nextAirDate, let day = TVDate.shortDay(date) {
                return String(localized: "Saison \(season) · épisode \(episode) le \(day)", bundle: .app)
            }
            return String(localized: "Saison \(season) · épisode \(episode) à venir", bundle: .app)
        }
        if item.entry.nextEpisode != nil, let total = facts.episodes, total > 0 {
            return String(localized: "Saison \(season) · épisode \(episode) sur \(total)", bundle: .app)
        }
        if let total = facts.episodes, total > 0 {
            return String(localized: "Saison \(season) · \(total) épisodes", bundle: .app)
        }
        return String(localized: "Saison \(season)", bundle: .app)
    }

    private func isWriting(_ item: WatchlistItem) -> Bool {
        libraryStore.pendingNextEpisode(for: item.entry) != nil
            || libraryStore.pendingStatus(for: item.entry.mediaItem) != nil
    }

    /// Vers la droite : « vu » pour un film, un épisode de plus pour une
    /// saison — et « saison vue » sur le dernier, parce que le même geste la
    /// range alors en galerie. Le libellé dit toujours ce qui va être écrit.
    private func trailingAction(for item: WatchlistItem) -> PlanRowAction? {
        // Personne n'a vu un épisode qui n'est pas sorti : la ligne ne glisse
        // que vers la gauche, pour la retirer.
        guard !item.isAwaitingEpisode else { return nil }
        guard item.entry.isSeason else {
            return PlanRowAction(label: String(localized: "Vu", bundle: .app), tint: Ink.ink) {
                libraryStore.addToGallery(item.entry.mediaItem)
            }
        }
        if item.entry.isOnLastEpisode {
            return PlanRowAction(label: String(localized: "Saison vue", bundle: .app), tint: Ink.paper) {
                libraryStore.addToGallery(item.entry.mediaItem)
            }
        }
        return PlanRowAction(label: String(localized: "+ 1 ép.", bundle: .app), tint: Ink.ink) {
            libraryStore.setNextEpisode(item.entry, to: item.entry.episodeToPlay + 1)
        }
    }

    @ViewBuilder
    private func platformBadge(for item: WatchlistItem) -> some View {
        if let platform = preferredPlatform(for: item) {
            PlatformBadge(platform: platform)
        } else if libraryStore.preferredPlatformIDs.isEmpty {
            // Sans plateforme déclarée, « hors de tes plateformes » serait faux
            // sur chaque ligne : la place reste tenue, vide.
            Color.clear
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
        } else if item.providerIDs.isEmpty {
            Text(verbatim: "—")
                .planFont(11)
                .foregroundStyle(Ink.ink2)
                .frame(width: 20, height: 20)
        } else {
            // Disponible, mais pas chez vous : le point creux du vocabulaire
            // commun, plutôt qu'un symbole de téléchargement qui ne veut rien
            // dire ici.
            PlanLightOutline(tint: Ink.ink3)
                .frame(width: 20, height: 20)
                .accessibilityLabel(String(localized: "Hors de tes plateformes", bundle: .app))
        }
    }

    @ViewBuilder
    private var budgetFooter: some View {
        if model.hiddenByBudget > 0 {
            Button {
                Haptics.selection()
                model.budget = .any
            } label: {
                Text(model.hiddenByBudget == 1
                     ? String(localized: "\(model.hiddenByBudget) film dépasse \(model.budget.label) · Tout voir", bundle: .app)
                     : String(localized: "\(model.hiddenByBudget) films dépassent \(model.budget.label) · Tout voir", bundle: .app))
                    .planFont(12)
                    .foregroundStyle(Ink.ink2)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Metrics.margin)
            .padding(.top, 22)
        }
    }

    // MARK: - Actions

    /// « Je le regarde » : un film part en galerie ; une saison avance d'un
    /// épisode, ou part en galerie si c'était le dernier.
    private func watch(_ item: WatchlistItem) {
        Haptics.success()
        if item.entry.isSeason, !item.entry.isOnLastEpisode {
            libraryStore.setNextEpisode(item.entry, to: item.entry.episodeToPlay + 1)
        } else {
            libraryStore.addToGallery(item.entry.mediaItem)
        }
    }

    private func preferredPlatform(for item: WatchlistItem) -> StreamingPlatform? {
        let preferred = Set(libraryStore.preferredPlatformIDs.compactMap(Int.init))
        guard let providerID = item.providerIDs.first(where: { preferred.contains($0) }) else {
            return nil
        }
        return catalog.platform(forProvider: providerID)
    }

    private func platformName(for item: WatchlistItem) -> String? {
        preferredPlatform(for: item)?.name
    }

    // MARK: - Vide

    private var emptyState: some View {
        PlanEmptyState(
            icon: .salle,
            title: String(localized: "Rien en attente", bundle: .app),
            message: String(localized: "Dans Découvrir, fais glisser un film vers le haut pour l'ajouter à ta watchlist.", bundle: .app),
            actionTitle: String(localized: "Trouver des films", bundle: .app),
            action: { selectedTab = 2 }
        )
    }
}

/// La croix de retrait, dans l'écriture de la famille.
private struct WatchlistRemoveGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        return path
    }
}

/// Le logo de la plateforme, ou ses initiales si TMDB n'en fournit pas.
private struct PlatformBadge: View {
    let platform: StreamingPlatform

    var body: some View {
        Group {
            if let url = platform.logoURL {
                PosterImageView(url: url)
            } else {
                Text(platform.shortLabel)
                    .planFont(8, weight: .semibold)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.tertiarySystemFill))
            }
        }
        .frame(width: 20, height: 20)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous))
        .accessibilityLabel(String(localized: "Disponible sur \(platform.name)", bundle: .app))
    }
}
