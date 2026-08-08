//
//  PublicProfileView.swift
//  Cinechill_iOS
//

import SwiftUI

/// Le profil de quelqu'un d'autre.
///
/// Reprend les blocs de `ProfileView` — carte de signature, compteurs, ADN
/// cinéphile — parce qu'un second langage visuel pour la même information
/// n'aurait aucune justification. Ce qui change, c'est ce qu'on retire : la
/// watchlist n'y figure pas. Ce qu'on a l'intention de voir est une note à
/// soi-même, pas une déclaration publique — et c'est une décision, pas un
/// réglage à arbitrer.
struct PublicProfileView: View {
    let profile: PublicProfile

    @EnvironmentObject private var socialStore: SocialStore

    @State private var detail: PublicProfileDetail?
    @State private var isLoading = true
    @State private var isTogglingFollow = false
    @State private var errorMessage: String?

    private var shown: PublicProfile { detail?.profile ?? profile }
    private var isFollowing: Bool { socialStore.isFollowing(profile.id) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                identity
                stats
                actions
                if isLoading {
                    loadingRow
                } else {
                    dnaSection
                    postersSection
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .padding(.bottom, 36)
        }
        .background(Color(.systemBackground))
        .navigationTitle(shown.handleDisplay)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: profile.id) { await load() }
        .alert(
            "Impossible",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Identité

    private var identity: some View {
        VStack(spacing: 8) {
            HallAvatar(
                seed: shown.id,
                initial: shown.initials,
                url: shown.avatarURL,
                size: 76
            )

            VStack(spacing: 2) {
                Text(shown.displayName)
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .multilineTextAlignment(.center)

                Text(shown.handleDisplay)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            if let badge = signatureBadge {
                HStack(spacing: 5) {
                    BadgeView(badge: badge, isUnlocked: true, size: 22)
                    Text(badge.name.uppercased())
                        .font(.system(size: 9.5, weight: .heavy, design: .rounded))
                        .kerning(0.6)
                        .foregroundStyle(badge.rarity.accent)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    badge.rarity.accent.opacity(0.16),
                    in: Capsule()
                )
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Le badge affiché vient du catalogue local : le serveur n'en transmet
    /// que l'identifiant, l'illustration vit déjà dans l'app.
    private var signatureBadge: Badge? {
        guard let id = shown.badgeSignature else { return nil }
        return BadgeCatalog.all.first { $0.id == id }
    }

    // MARK: - Chiffres

    private var stats: some View {
        HStack(spacing: 8) {
            statCell(value: shown.galleryCount, label: "VUS")
            statCell(value: shown.followerCount, label: "ABONNÉS")
            statCell(value: shown.followingCount, label: "ABONNEMENTS")
        }
    }

    private func statCell(value: Int, label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.system(size: 19, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(label)
                .font(.system(size: 8.5, weight: .bold, design: .rounded))
                .kerning(0.5)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 11)
        .background(
            Color(.secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
        )
    }

    // MARK: - Actions

    /// Un seul état de suivi, réversible d'un tap, sans confirmation : se
    /// désabonner n'est pas destructeur, une alerte y ajouterait une
    /// cérémonie injustifiée.
    ///
    /// Pas de raccourci « recommander » ici : le parcours part du film, pas
    /// de la personne (galerie → Recommander → choisir l'ami). Un second
    /// point d'entrée demanderait un sélecteur de film, donc un deuxième
    /// parcours pour la même action.
    private var actions: some View {
        HallFollowButton(
            isFollowing: isFollowing,
            isBusy: isTogglingFollow,
            fullWidth: true
        ) {
            Haptics.impact(.medium)
            Task { await toggleFollow() }
        }
    }

    // MARK: - ADN

    @ViewBuilder
    private var dnaSection: some View {
        if let genres = detail?.genres, !genres.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("Son ADN cinéphile")

                GeometryReader { proxy in
                    HStack(spacing: 1.5) {
                        ForEach(genres) { share in
                            Capsule()
                                .fill(share.color)
                                .frame(width: max(2, proxy.size.width * share.share - 1.5))
                        }
                    }
                }
                .frame(height: 9)

                FlowLayout(spacing: 12) {
                    ForEach(genres.prefix(4)) { share in
                        HStack(spacing: 5) {
                            Circle().fill(share.color).frame(width: 6, height: 6)
                            Text(share.name).foregroundStyle(.secondary)
                            Text(share.percentText).foregroundStyle(.primary)
                        }
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    }
                }
            }
        }
    }

    // MARK: - Galerie

    @ViewBuilder
    private var postersSection: some View {
        if let posters = detail?.posters, !posters.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    sectionTitle("Sa galerie")
                    Spacer()
                    Text("\(shown.galleryCount)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(posters) { poster in
                            PosterTile(
                                posterPath: poster.posterPath,
                                title: poster.title,
                                width: 66,
                                cornerRadius: 7
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollClipDisabled()
            }
        }
    }

    private var loadingRow: some View {
        HStack {
            Spacer()
            CinechillSpinner(size: 26)
            Spacer()
        }
        .padding(.vertical, 30)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 17, weight: .heavy, design: .rounded))
    }

    // MARK: - Chargement

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            detail = try await socialStore.profileDetail(uid: profile.id)
        } catch is CancellationError {
            return
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    private func toggleFollow() async {
        guard !isTogglingFollow else { return }
        isTogglingFollow = true
        defer { isTogglingFollow = false }
        do {
            try await socialStore.toggleFollow(uid: profile.id)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }
}
