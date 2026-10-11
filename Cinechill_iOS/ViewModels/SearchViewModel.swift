//
//  SearchViewModel.swift
//  Cinechill_iOS
//

import Foundation
import FirebaseAuth

/// Ce qu'on cherche : un film, une série, ou quelqu'un.
///
/// Pas de portée « Tout » : chaque liste reste homogène, et le passage de l'une
/// à l'autre est immédiat puisque les deux sources répondent à chaque frappe.
enum SearchScope: Hashable, CaseIterable {
    case films
    case series
    case profiles

    var title: String {
        switch self {
        case .films: String(localized: "Films", bundle: .app)
        case .series: String(localized: "Séries", bundle: .app)
        case .profiles: String(localized: "Profils", bundle: .app)
        }
    }
}

/// La recherche de l'app : films, séries et profils.
///
/// La rapidité vient de la frappe, pas d'un bouton : chaque caractère relance
/// la recherche, amortie de 250 ms pour qu'une saisie continue n'en déclenche
/// qu'une. Les deux sources partent ensemble (le serveur pour les titres,
/// Firestore pour les profils) et échouent chacune de son côté : un TMDB
/// injoignable n'empêche pas de trouver quelqu'un.
@Observable
@MainActor
final class SearchViewModel {
    private static let debounce: Duration = .milliseconds(250)

    var query: String = ""
    var scope: SearchScope

    private(set) var titles: [MediaItem] = []
    private(set) var profiles: [PublicProfile] = []
    /// La requête à laquelle les résultats correspondent, citée mot pour mot
    /// dans l'état vide.
    private(set) var settledQuery: String = ""
    private(set) var isSearching = false
    /// Les échecs restent affichés jusqu'à la réponse suivante, et les derniers
    /// résultats avec eux : effacés à chaque touche, ils clignoteraient.
    private(set) var titlesError: String?
    private(set) var profilesError: String?
    private(set) var recents: [SearchRecent] = []

    private let titleClient: any TitleSearching
    private let recentsStore: SearchRecentsStore
    private var searchTask: Task<Void, Never>?

    /// Les récents appartiennent au compte connecté : sur un appareil partagé,
    /// l'un ne voit pas ce que l'autre a ouvert.
    init(scope: SearchScope, titleClient: any TitleSearching = BackendTitleSearchClient()) {
        self.scope = scope
        self.titleClient = titleClient
        self.recentsStore = SearchRecentsStore(uid: Auth.auth().currentUser?.uid)
        self.recents = recentsStore.load()
    }

    // MARK: - La saisie

    var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Un `@` en tête cherche un pseudo, et seulement un pseudo.
    var isProfileQuery: Bool { trimmedQuery.hasPrefix("@") }

    private var needle: String {
        guard isProfileQuery else { return trimmedQuery }
        return String(trimmedQuery.dropFirst()).trimmingCharacters(in: .whitespaces)
    }

    /// Deux caractères pour un titre : en dessous, TMDB rend n'importe quoi.
    /// Après un `@`, un seul suffit : les pseudos sont courts, et la base des
    /// profils l'est aussi.
    var isQueryTooShort: Bool {
        needle.count < (isProfileQuery ? 1 : 2)
    }

    // MARK: - Les résultats

    var films: [MediaItem] { titles.filter { $0.mediaType == .movie } }
    var series: [MediaItem] { titles.filter { $0.mediaType == .tv } }

    func count(for scope: SearchScope) -> Int {
        switch scope {
        case .films: films.count
        case .series: series.count
        case .profiles: profiles.count
        }
    }

    var currentError: String? {
        scope == .profiles ? profilesError : titlesError
    }

    /// Les résultats correspondent-ils bien à ce qui est tapé ? Pendant la
    /// frappe, l'écran ne doit pas annoncer « aucun résultat ».
    var isSettled: Bool {
        !isSearching && settledQuery == trimmedQuery
    }

    var showsNoResults: Bool {
        isSettled && !isQueryTooShort && count(for: scope) == 0 && currentError == nil
    }

    /// Une autre portée qui a trouvé quelque chose, pour l'offrir quand celle-ci
    /// est vide : on tape « léa » sur Films, et Léa est dans Profils.
    var alternativeScope: SearchScope? {
        SearchScope.allCases.first { $0 != scope && count(for: $0) > 0 }
    }

    // MARK: - Les récents

    func recents(for scope: SearchScope) -> [SearchRecent] {
        let filtered = recents.filter { recent in
            switch (recent, scope) {
            case (.title(let title), .films): title.mediaType == MediaType.movie.rawValue
            case (.title(let title), .series): title.mediaType == MediaType.tv.rawValue
            case (.profile, .profiles): true
            default: false
            }
        }
        return Array(filtered.prefix(8))
    }

    func recordOpened(_ item: MediaItem) {
        recents = recentsStore.record(.title(.init(item)))
    }

    func recordOpened(_ profile: PublicProfile) {
        recents = recentsStore.record(.profile(.init(profile)))
    }

    func clearRecents() {
        recentsStore.clear()
        recents = []
    }

    // MARK: - La recherche

    func search(store: SocialStore) {
        searchTask?.cancel()
        let typed = trimmedQuery
        let needle = needle
        let profilesOnly = isProfileQuery

        guard !isQueryTooShort else {
            titles = []
            profiles = []
            settledQuery = typed
            titlesError = nil
            profilesError = nil
            isSearching = false
            return
        }

        isSearching = true
        searchTask = Task { [weak self, titleClient] in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled else { return }

            async let foundTitles = Self.fetchTitles(needle, skip: profilesOnly, client: titleClient)
            async let foundProfiles = Self.fetchProfiles(needle, store: store)
            let titleOutcome = await foundTitles
            let profileOutcome = await foundProfiles

            guard !Task.isCancelled, let self else { return }
            switch titleOutcome {
            case .success(let items):
                self.titles = items
                self.titlesError = nil
            case .failure(let message):
                self.titlesError = message
            }
            switch profileOutcome {
            case .success(let found):
                self.profiles = found
                self.profilesError = nil
            case .failure(let message):
                self.profilesError = message
            }
            self.settledQuery = typed
            self.isSearching = false
        }
    }

    /// L'issue d'une source : la liste, ou le message à afficher.
    private enum Outcome<Value: Sendable>: Sendable {
        case success(Value)
        case failure(String)
    }

    private static func fetchTitles(
        _ needle: String, skip: Bool, client: any TitleSearching
    ) async -> Outcome<[MediaItem]> {
        guard !skip else { return .success([]) }
        #if DEBUG
        if let fixture = DebugFixtures.titles(matching: needle) { return .success(fixture) }
        #endif
        do {
            return .success(try await client.searchTitles(needle))
        } catch {
            return .failure(message(for: error))
        }
    }

    private static func fetchProfiles(_ needle: String, store: SocialStore) async -> Outcome<[PublicProfile]> {
        #if DEBUG
        if let fixture = DebugFixtures.profiles(matching: needle) { return .success(fixture) }
        #endif
        do {
            return .success(try await store.searchProfiles(matching: needle))
        } catch {
            return .failure(message(for: error))
        }
    }

    private nonisolated static func message(for error: any Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
