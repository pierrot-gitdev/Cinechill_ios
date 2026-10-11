//
//  ProfileSearchViewModel.swift
//  Cinechill_iOS
//

import Foundation

/// La recherche de profils.
///
/// La rapidité vient de la frappe, pas d'un bouton : chaque caractère relance
/// une requête, amortie de 250 ms pour qu'une saisie continue n'en déclenche
/// qu'une seule. Deux caractères minimum — en dessous, le préfixe ramènerait
/// une part trop large de la base pour être utile.
@Observable
@MainActor
final class ProfileSearchViewModel {
    private static let debounce: Duration = .milliseconds(250)
    private static let minimumLength = 2

    /// La vue relance `search(store:)` à chaque changement : le modèle ne
    /// détient pas le store, et le lui injecter pour un seul appel le lierait
    /// à Firestore sans contrepartie.
    var query: String = ""

    private(set) var results: [PublicProfile] = []
    private(set) var suggestions: [PublicProfile] = []
    private(set) var isSearching = false
    /// La requête à laquelle `results` correspond — citée mot pour mot dans
    /// l'état vide, pour qu'on voie ce qui a réellement été cherché.
    private(set) var settledQuery: String = ""
    /// Les suivis en cours de bascule, pour ne pas rendre tout l'écran occupé.
    private(set) var pendingFollows: Set<String> = []
    /// Tant que les suggestions n'ont pas répondu, « personne à proposer »
    /// serait faux : l'écran attend.
    private(set) var isLoadingSuggestions = false
    private(set) var suggestionsError: String?
    /// L'échec de la dernière recherche. Il reste affiché jusqu'à la réponse
    /// suivante plutôt que d'être effacé à chaque touche : sinon le message
    /// clignoterait pendant la frappe. Les derniers résultats restent aussi.
    private(set) var searchError: String?

    private var searchTask: Task<Void, Never>?

    var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isQueryTooShort: Bool {
        trimmedQuery.count < Self.minimumLength
    }

    /// Un résultat vide n'est une impasse que si la recherche a bien abouti :
    /// pendant la frappe, l'écran ne doit pas clignoter en « aucun profil ».
    var showsNoResults: Bool {
        !isSearching && !isQueryTooShort && results.isEmpty
            && settledQuery == trimmedQuery && searchError == nil
    }

    func loadSuggestions(store: SocialStore) async {
        guard suggestions.isEmpty, !isLoadingSuggestions else { return }
        isLoadingSuggestions = true
        suggestionsError = nil
        defer { isLoadingSuggestions = false }
        do {
            suggestions = try await store.suggestedProfiles()
        } catch is CancellationError {
            return
        } catch {
            suggestionsError = Self.message(for: error)
        }
    }

    func search(store: SocialStore) {
        searchTask?.cancel()
        let needle = trimmedQuery

        guard needle.count >= Self.minimumLength else {
            results = []
            settledQuery = needle
            searchError = nil
            isSearching = false
            return
        }

        isSearching = true
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled, let self else { return }
            do {
                let found = try await store.searchProfiles(matching: needle)
                guard !Task.isCancelled else { return }
                self.results = found
                self.settledQuery = needle
                self.searchError = nil
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self.searchError = Self.message(for: error)
            }
            self.isSearching = false
        }
    }

    private static func message(for error: any Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    func toggleFollow(_ profile: PublicProfile, store: SocialStore) async {
        guard !pendingFollows.contains(profile.id) else { return }
        pendingFollows.insert(profile.id)
        defer { pendingFollows.remove(profile.id) }
        do {
            try await store.toggleFollow(uid: profile.id)
        } catch {
            // Rien n'a changé : le bouton reste tel quel, la vibration le dit.
            Haptics.warning()
        }
    }
}
