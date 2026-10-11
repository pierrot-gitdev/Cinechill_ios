//
//  SearchView.swift
//  Cinechill_iOS
//

import SwiftUI

/// La recherche : un film, une série, ou quelqu'un.
///
/// On y arrive par la loupe de l'en-tête, sur les cinq onglets, et elle
/// s'empile dans la navigation de l'onglet en cours. Une fiche ouverte depuis
/// un résultat s'empile par-dessus ; au retour, la requête et la position dans
/// la liste sont intactes. « Annuler » ramène à l'onglet.
///
/// Pas d'animation propre : on ouvre cet écran plusieurs fois par jour, la
/// poussée du système suffit, et les résultats changent à chaque frappe sans
/// transition.
struct SearchView: View {
    @EnvironmentObject private var socialStore: SocialStore
    @EnvironmentObject private var libraryStore: LibraryStore
    @Environment(\.dismiss) private var dismiss

    @State private var model: SearchViewModel
    @State private var openedItem: MediaItem?
    @State private var openedProfile: PublicProfile?
    /// Les suivis qui ont échoué : un mot sous le champ, puis rien.
    @State private var followFailure: String?
    /// Le profil qu'on voulait suivre sans avoir encore de pseudo.
    @State private var handleGate: PublicProfile?

    init(scope: SearchScope = .films) {
        _model = State(initialValue: SearchViewModel(scope: scope))
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            scopeBar
            if let message = visibleFailure {
                failureLine(message)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    content
                }
                .padding(.bottom, 30)
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .background(Ink.ground)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $openedItem) { item in
            ItemDetailView(item: item)
        }
        .navigationDestination(item: $openedProfile) { profile in
            PublicProfileView(profile: profile)
        }
        .sheet(item: $handleGate) { profile in
            ClaimHandleSheet(onClaimed: { performFollow(profile) })
                .environmentObject(socialStore)
        }
        .onChange(of: model.query) { _, _ in
            // Un `@` en tête ne cherche que des pseudos : la portée suit.
            if model.isProfileQuery, model.scope != .profiles {
                model.scope = .profiles
            }
            model.search(store: socialStore)
        }
        .task {
            await socialStore.loadFollowSuggestions()
        }
    }

    // MARK: - Le haut

    private var topBar: some View {
        HStack(alignment: .center, spacing: 14) {
            HallSearchField(
                placeholder: String(localized: "Films, séries, profils", bundle: .app),
                text: $model.query,
                isBusy: model.isSearching,
                focusesOnAppear: true
            )

            Button {
                dismiss()
            } label: {
                Text("Annuler", bundle: .app)
                    .planFont(15)
                    .foregroundStyle(Ink.ink)
                    .frame(minHeight: Metrics.control)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableScaleStyle())
        }
        .padding(.horizontal, 18)
        .padding(.top, 6)
    }

    private var scopeBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SearchScope.allCases, id: \.self) { scope in
                    PlanChip(title: scope.title, isOn: model.scope == scope) {
                        model.scope = scope
                    }
                }
            }
            .padding(.horizontal, 18)
        }
        .padding(.top, 6)
        .padding(.bottom, 10)
    }

    // MARK: - Le contenu

    @ViewBuilder
    private var content: some View {
        if model.isQueryTooShort {
            idle
        } else if model.count(for: model.scope) == 0, let error = model.currentError {
            unavailable(error)
        } else if model.showsNoResults {
            noResults
        } else {
            results
        }
    }

    /// Avant de taper : ce qu'on a ouvert récemment, et pour Profils, les
    /// profils à suivre.
    @ViewBuilder
    private var idle: some View {
        let recents = model.recents(for: model.scope)
        if !recents.isEmpty {
            sectionHeader(String(localized: "Récents", bundle: .app)) {
                Button {
                    model.clearRecents()
                } label: {
                    Text("Effacer", bundle: .app)
                        .planFont(12.5)
                        .foregroundStyle(Ink.ink2)
                        .underline(color: Ink.ruleSet)
                        .frame(minHeight: Metrics.control)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableScaleStyle())
            }
            ForEach(recents) { recent in
                switch recent {
                case .title(let title):
                    titleRow(title.item)
                case .profile(let profile):
                    profileRow(profile.profile, note: nil)
                }
            }
        }

        switch model.scope {
        case .profiles:
            suggestions(showsHint: recents.isEmpty)
        case .films, .series:
            if recents.isEmpty {
                hint(String(localized: "Tape un titre, en français ou en version originale.", bundle: .app))
            }
        }
    }

    @ViewBuilder
    private func suggestions(showsHint: Bool) -> some View {
        let list = socialStore.followSuggestions
        if !list.isEmpty {
            sectionHeader(String(localized: "Profils à suivre", bundle: .app))
            ForEach(list) { suggestion in
                profileRow(suggestion.profile, note: suggestion.reason)
            }
        } else {
            switch socialStore.followSuggestionsPhase {
            case .loading, .idle:
                HStack {
                    Spacer()
                    CinechillSpinner(size: 22)
                    Spacer()
                }
                .padding(.top, 40)
            case .failed(let message):
                HallEmptyState(
                    icon: .hall,
                    title: String(localized: "Liste indisponible", bundle: .app),
                    message: message,
                    actionTitle: String(localized: "Réessayer", bundle: .app),
                    action: { Task { await socialStore.loadFollowSuggestions(force: true) } }
                )
                .padding(.top, 40)
            case .loaded:
                if showsHint {
                    hint(String(localized: "Tape un pseudo ou un nom pour retrouver quelqu'un que tu connais.", bundle: .app))
                }
            }
        }
    }

    @ViewBuilder
    private var results: some View {
        switch model.scope {
        case .films:
            ForEach(model.films) { titleRow($0) }
        case .series:
            ForEach(model.series) { titleRow($0) }
        case .profiles:
            if !model.profiles.isEmpty {
                sectionHeader(String(localized: "\(model.profiles.count) profils", bundle: .app))
            }
            ForEach(model.profiles) { profileRow($0, note: nil) }
        }
    }

    private var noResults: some View {
        let query = model.settledQuery
        let isProfiles = model.scope == .profiles
        let alternative = model.alternativeScope
        return HallEmptyState(
            icon: .chercher,
            title: isProfiles
                ? String(localized: "Aucun profil pour « \(query) »", bundle: .app)
                : String(localized: "Aucun résultat pour « \(query) »", bundle: .app),
            message: isProfiles
                ? String(localized: "Vérifie l'orthographe, ou invite cette personne à rejoindre Cinechill.", bundle: .app)
                : String(localized: "Vérifie l'orthographe ou essaie le titre original.", bundle: .app),
            actionTitle: alternative.map { alternativeTitle($0, count: model.count(for: $0)) },
            action: alternative.map { scope in { model.scope = scope } }
        )
        .padding(.top, 40)
    }

    /// « Voir les 3 séries » : ce que l'autre portée a trouvé, chiffré.
    private func alternativeTitle(_ scope: SearchScope, count: Int) -> String {
        switch scope {
        case .films: String(localized: "Voir les \(count) films", bundle: .app)
        case .series: String(localized: "Voir les \(count) séries", bundle: .app)
        case .profiles: String(localized: "Voir les \(count) profils", bundle: .app)
        }
    }

    private func unavailable(_ message: String) -> some View {
        HallEmptyState(
            icon: .chercher,
            title: String(localized: "Recherche indisponible", bundle: .app),
            message: message,
            actionTitle: String(localized: "Réessayer", bundle: .app),
            action: { model.search(store: socialStore) }
        )
        .padding(.top, 40)
    }

    /// L'échec qui s'affiche sous le champ : celui de la portée en cours, quand
    /// il reste des résultats plus anciens à montrer, ou celui d'un suivi.
    private var visibleFailure: String? {
        if !model.isQueryTooShort, let error = model.currentError, model.count(for: model.scope) > 0 {
            return error
        }
        return followFailure
    }

    private func failureLine(_ message: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 11) {
            PlanLight(tint: Ink.warn)
            Text(message)
                .planFont(12.5)
                .foregroundStyle(Ink.warn)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if followFailure == nil {
                Button {
                    model.search(store: socialStore)
                } label: {
                    Text("Réessayer", bundle: .app)
                        .planFont(12.5, weight: .medium)
                        .foregroundStyle(Ink.ink)
                        .underline()
                        .fixedSize()
                        .frame(minHeight: Metrics.control)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableScaleStyle())
                .disabled(model.isSearching)
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 6)
    }

    // MARK: - Les lignes

    private func titleRow(_ item: MediaItem) -> some View {
        Button {
            model.recordOpened(item)
            openedItem = item
        } label: {
            SearchTitleRow(
                item: item,
                inGallery: libraryStore.isInGallery(item),
                inWatchlist: libraryStore.isInWatchlist(item)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 18)
    }

    private func profileRow(_ profile: PublicProfile, note: String?) -> some View {
        Button {
            model.recordOpened(profile)
            openedProfile = profile
        } label: {
            HallProfileRow(
                profile: profile,
                note: note,
                isFollowing: socialStore.isFollowing(profile.id),
                isBusy: socialStore.followsInFlight.contains(profile.id),
                onToggleFollow: { toggleFollow(profile) }
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 18)
        .padding(.vertical, 3)
    }

    /// Sans pseudo, le serveur refuse tout suivi : la feuille du pseudo
    /// s'ouvre d'abord, et le suivi part dès qu'il est pris.
    private func toggleFollow(_ profile: PublicProfile) {
        if socialStore.hasLoadedProfileOnce, socialStore.myProfile == nil,
           !socialStore.isFollowing(profile.id) {
            handleGate = profile
            return
        }
        performFollow(profile)
    }

    private func performFollow(_ profile: PublicProfile) {
        followFailure = nil
        Task {
            guard await socialStore.toggleFollowTracked(uid: profile.id) else {
                Haptics.warning()
                followFailure = String(localized: "On n'arrive pas à joindre le serveur. Vérifie ta connexion internet.", bundle: .app)
                return
            }
        }
    }

    // MARK: - Petits éléments

    private func sectionHeader(_ title: String) -> some View {
        sectionHeader(title) { EmptyView() }
    }

    private func sectionHeader<Trailing: View>(_ title: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(alignment: .center) {
            Text(title)
                .planLabel()
                .foregroundStyle(Ink.ink2)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            trailing()
        }
        .frame(minHeight: Metrics.control)
        .padding(.horizontal, Metrics.margin)
        .padding(.top, 8)
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .planFont(13.5)
            .foregroundStyle(Ink.ink2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Metrics.margin)
            .padding(.top, 18)
    }
}

/// Une ligne de film ou de série : la vignette, le titre sur deux lignes au
/// plus, puis « Film · 2019 · Vu ».
///
/// L'état dans la bibliothèque s'écrit en toutes lettres plutôt qu'avec le
/// point de lumière : une liste de résultats en compterait des dizaines, et la
/// règle n'en tolère que deux par écran.
struct SearchTitleRow: View {
    @ScaledMetric(relativeTo: .body) private var thumbWidth: CGFloat = 40
    let item: MediaItem
    let inGallery: Bool
    let inWatchlist: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            PosterTile(posterPath: item.posterPath, title: item.title, width: min(thumbWidth, 64))

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .planFont(14, weight: .medium)
                    .foregroundStyle(Ink.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(meta)
                    .planFont(12)
                    .foregroundStyle(Ink.ink2)
                    .lineLimit(2)
            }
            .padding(.top, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(item.title), \(meta)"))
        .accessibilityAddTraits(.isButton)
    }

    /// Le format, l'année si on la connaît, les saisons d'une série, et ce que
    /// la bibliothèque en sait. Une année inconnue est omise, pas remplacée par
    /// un tiret qui resterait orphelin.
    private var meta: String {
        var parts = [item.mediaType == .tv
                     ? String(localized: "Série", bundle: .app)
                     : String(localized: "Film", bundle: .app)]
        if let date = item.releaseDate, date.count >= 4 {
            parts.append(String(date.prefix(4)))
        }
        if item.mediaType == .tv, let seasons = item.seasonCount, seasons > 0 {
            parts.append(seasons == 1
                         ? String(localized: "1 saison", bundle: .app)
                         : String(localized: "\(seasons) saisons", bundle: .app))
        }
        if inGallery {
            parts.append(String(localized: "Vu", bundle: .app))
        } else if inWatchlist {
            parts.append(String(localized: "Dans ta watchlist", bundle: .app))
        }
        return parts.joined(separator: " · ")
    }
}
