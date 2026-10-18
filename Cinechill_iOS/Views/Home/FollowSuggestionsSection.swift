//
//  FollowSuggestionsSection.swift
//  Cinechill_iOS
//

import SwiftUI

/// « Profils à suivre » : une rangée de cartes sur l'accueil, comme les
/// rangées d'affiches.
///
/// Chaque carte donne une raison vérifiable de suivre la personne et un bouton
/// qui la suit en un toucher. Suivie, la carte reste en place, en « Suivi » :
/// elle s'en ira au prochain chargement, jamais sous le doigt. La croix la
/// retire pour de bon, une fois le serveur d'accord.
///
/// La présence et la place de la rangée se décident dans `SocialStore`, au
/// chargement. Cette vue ne fait que la dessiner.
struct FollowSuggestionsSection: View {
    @EnvironmentObject private var socialStore: SocialStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let onOpen: (PublicProfile) -> Void

    /// Le profil qu'on voulait suivre sans avoir encore de pseudo.
    @State private var handleGate: PublicProfile?
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: HomeRhythm.title) {
            HomeSectionHeader(title: String(localized: "Profils à suivre", bundle: .app)) {
                NavigationLink {
                    SearchView(scope: .profiles)
                } label: {
                    Text("Tout voir", bundle: .app)
                        .homeTextLink()
                }
                .buttonStyle(PressableScaleStyle())
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: Metrics.gutter) {
                    ForEach(socialStore.followSuggestions) { suggestion in
                        FollowSuggestionCard(
                            suggestion: suggestion,
                            isFollowing: socialStore.isFollowing(suggestion.id),
                            isFollowBusy: socialStore.followsInFlight.contains(suggestion.id),
                            isDismissing: socialStore.dismissalsInFlight.contains(suggestion.id),
                            onOpen: { onOpen(suggestion.profile) },
                            onToggleFollow: { toggleFollow(suggestion.profile) },
                            onDismiss: { dismiss(suggestion) }
                        )
                        // Rien ne surgit de rien : la carte s'efface en se
                        // resserrant à peine, et la rangée referme l'espace.
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96)))
                    }
                }
                .padding(.horizontal, 1)
                .animation(reduceMotion ? nil : Metrics.unfold, value: socialStore.followSuggestions.map(\.id))
            }
            .scrollClipDisabled()

            if let failure {
                HStack(alignment: .firstTextBaseline, spacing: 11) {
                    PlanLight(tint: Ink.warn)
                    Text(failure)
                        .planFont(12.5)
                        .foregroundStyle(Ink.warn)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .transition(.opacity)
            }
        }
        .animation(Metrics.shift, value: failure)
        .sheet(item: $handleGate) { profile in
            ClaimHandleSheet(onClaimed: { performFollow(profile) })
                .environmentObject(socialStore)
        }
        // Le message passe : il dit ce qui n'a pas marché, puis laisse la place.
        .task(id: failure) {
            guard failure != nil else { return }
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            failure = nil
        }
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
        failure = nil
        Task {
            guard await socialStore.toggleFollowTracked(uid: profile.id) else {
                Haptics.warning()
                failure = String(localized: "On n'arrive pas à joindre le serveur. Vérifie ta connexion internet.", bundle: .app)
                return
            }
        }
    }

    private func dismiss(_ suggestion: FollowSuggestion) {
        failure = nil
        Task {
            guard await socialStore.dismissFollowSuggestion(uid: suggestion.id) else {
                Haptics.warning()
                failure = String(localized: "On n'arrive pas à joindre le serveur. Vérifie ta connexion internet.", bundle: .app)
                return
            }
        }
    }
}

/// Une carte de profil à suivre : l'avatar, le nom sur deux lignes au plus, le
/// pseudo, la raison, et Suivre.
///
/// Les lignes du nom et de la raison réservent leur hauteur de deux lignes :
/// toutes les cartes de la rangée ont ainsi la même hauteur, et le bouton tombe
/// au même endroit sur chacune, quelle que soit la longueur du nom.
struct FollowSuggestionCard: View {
    @ScaledMetric(relativeTo: .footnote) private var width: CGFloat = 150
    let suggestion: FollowSuggestion
    let isFollowing: Bool
    let isFollowBusy: Bool
    let isDismissing: Bool
    let onOpen: () -> Void
    let onToggleFollow: () -> Void
    let onDismiss: () -> Void

    private var profile: PublicProfile { suggestion.profile }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 0) {
                    HallAvatar(
                        seed: profile.id,
                        initial: profile.initials,
                        url: profile.avatarURL,
                        size: 48
                    )

                    Text(profile.displayName)
                        .planFont(14, weight: .medium)
                        .foregroundStyle(Ink.ink)
                        .lineLimit(2, reservesSpace: true)
                        .multilineTextAlignment(.leading)
                        .padding(.top, 10)

                    Text(verbatim: secondLine)
                        .planFont(11.5)
                        .foregroundStyle(Ink.ink2)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.top, 2)

                    Text(suggestion.reason)
                        .planFont(12)
                        .foregroundStyle(Ink.ink2)
                        .lineLimit(2, reservesSpace: true)
                        .multilineTextAlignment(.leading)
                        .padding(.top, 8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: "\(profile.displayName), \(secondLine), \(suggestion.reason)"))
            }
            .buttonStyle(.plain)

            HallFollowButton(
                isFollowing: isFollowing,
                isBusy: isFollowBusy,
                stretches: true,
                action: onToggleFollow
            )
            .padding(.top, 12)
        }
        .padding(.horizontal, 12)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(width: min(width, 220))
        .background(Ink.ground2, in: RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous))
        .overlay(alignment: .topTrailing) { dismissButton }
        .opacity(isDismissing ? 0.6 : 1)
        .animation(Metrics.shift, value: isDismissing)
    }

    /// Le pseudo, sauf s'il sert déjà de nom : un profil sans nom le
    /// répéterait. Le nombre de films vus prend alors sa place, à moins que la
    /// raison ne le dise déjà.
    private var secondLine: String {
        guard profile.displayName == profile.handle else { return profile.handleDisplay }
        let seen = FollowSuggestion.seenCount(profile.galleryCount)
        return suggestion.reason == seen ? profile.handleDisplay : seen
    }

    private var dismissButton: some View {
        Button(action: onDismiss) {
            Group {
                if isDismissing {
                    CinechillSpinner(size: 12)
                } else {
                    PlanClearGlyph()
                        .stroke(style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                        .foregroundStyle(Ink.ink3)
                        .frame(width: 10, height: 10)
                }
            }
            .frame(width: 36, height: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableScaleStyle(scale: 0.9))
        .disabled(isDismissing)
        .accessibilityLabel(String(localized: "Ne plus proposer \(profile.displayName)", bundle: .app))
    }
}
