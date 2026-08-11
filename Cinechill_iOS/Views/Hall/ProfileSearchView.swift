//
//  ProfileSearchView.swift
//  Cinechill_iOS
//

import SwiftUI

/// La recherche de profils — première étape du Hall.
///
/// Chercher quelqu'un n'est pas une activité quotidienne : on le fait une
/// poignée de fois, par à-coups. Elle n'occupe donc pas de place permanente
/// dans la navigation et vit là où l'on gère déjà ses relations.
struct ProfileSearchView: View {
    @EnvironmentObject private var socialStore: SocialStore
    @Environment(\.dismiss) private var dismiss

    @State private var model = ProfileSearchViewModel()
    @State private var openedProfile: PublicProfile?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                // Le champ dit lui-même ce qu'il accepte : pseudo, prénom ou
                // nom — la recherche interroge les deux, pas seulement l'un.
                HallSearchField(
                    placeholder: String(localized: "Pseudo, prénom ou nom", bundle: .app),
                    text: $model.query,
                    isBusy: model.isSearching
                )
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 14)

                if model.isQueryTooShort {
                    suggestionsSection
                } else if model.showsNoResults {
                    noResults
                } else {
                    resultsSection
                }
            }
            .padding(.bottom, 30)
        }
        .background(Ink.ground)
        .safeAreaInset(edge: .top) {
            PlanHeader(String(localized: "Rechercher", bundle: .app))
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $openedProfile) { profile in
            PublicProfileView(profile: profile)
        }
        .onChange(of: model.query) { _, _ in
            model.search(store: socialStore)
        }
        .task {
            await model.loadSuggestions(store: socialStore)
        }
    }

    // MARK: - Résultats

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(
                String(localized: "\(model.results.count) profils", bundle: .app)
            )
            rows(model.results)
        }
    }

    /// Un écran de recherche vide n'a pas à renvoyer l'utilisateur à sa propre
    /// absence d'idée : on propose des profils actifs.
    @ViewBuilder
    private var suggestionsSection: some View {
        if model.suggestions.isEmpty {
            HallEmptyState(
                icon: .hall,
                title: String(localized: "Personne à proposer pour l'instant", bundle: .app),
                message: String(localized: "Tape un pseudo pour retrouver quelqu'un que tu connais.", bundle: .app)
            )
            .padding(.top, 40)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader(String(localized: "Suggestions", bundle: .app))
                rows(model.suggestions)
            }
        }
    }

    private var noResults: some View {
        HallEmptyState(
            icon: .chercher,
            title: String(localized: "Aucun profil pour « \(model.settledQuery) »", bundle: .app),
            message: String(localized: "Vérifie l'orthographe, ou invite cette personne à rejoindre Cinechill.", bundle: .app)
        )
        .padding(.top, 40)
    }

    private func rows(_ profiles: [PublicProfile]) -> some View {
        ForEach(profiles) { profile in
            Button {
                openedProfile = profile
            } label: {
                HallProfileRow(
                    profile: profile,
                    isFollowing: socialStore.isFollowing(profile.id),
                    isBusy: model.pendingFollows.contains(profile.id),
                    onToggleFollow: {
                        Haptics.impact(.light)
                        Task { await model.toggleFollow(profile, store: socialStore) }
                    }
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 18)

            Divider().padding(.leading, 66)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .planLabel()
            .foregroundStyle(Ink.ink2)
            .padding(.horizontal, Metrics.margin)
            .padding(.bottom, 8)
    }
}
