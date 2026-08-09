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
            .padding(.horizontal, Metrics.margin)
            .padding(.top, 18)
            .padding(.bottom, 36)
        }
        .background(Ink.ground)
        .safeAreaInset(edge: .top) {
            PlanHeader(shown.handleDisplay)
        }
        .toolbar(.hidden, for: .navigationBar)
        .task(id: profile.id) { await load() }
        .alert(
            String(localized: "Impossible", bundle: .app),
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button(String(localized: "OK", bundle: .app), role: .cancel) { errorMessage = nil }
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
                    .planTitle(22)
                    .foregroundStyle(Ink.ink)
                    .multilineTextAlignment(.center)

                Text(shown.handleDisplay)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Ink.ink2)
            }

            if let badge = signatureBadge {
                HStack(spacing: 7) {
                    BadgeView(badge: badge, isUnlocked: true, size: 22)
                    Text(badge.name)
                        .planLabel()
                        .foregroundStyle(badge.rarity.accent)
                }
                .padding(.top, 4)
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

    /// Exactement la rangée de `ProfileView` : trois compteurs entre deux
    /// filets. Un second langage visuel pour la même information n'aurait
    /// aucune justification — c'est déjà la règle que cet écran s'était donnée.
    private var stats: some View {
        VStack(spacing: 0) {
            PlanEdge()
            HStack(spacing: 0) {
                statCell(value: shown.galleryCount, label: String(localized: "Vus", bundle: .app))
                statCell(value: shown.followerCount, label: String(localized: "Abonnés", bundle: .app))
                statCell(value: shown.followingCount, label: String(localized: "Abonnements", bundle: .app))
            }
            PlanEdge()
        }
    }

    private func statCell(value: Int, label: String) -> some View {
        VStack(spacing: 5) {
            Text(verbatim: "\(value)")
                .planTitle(21)
                .foregroundStyle(Ink.ink)
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(label)
                .planLabel()
                .foregroundStyle(Ink.ink3)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: "\(value) \(label)"))
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
                sectionTitle(String(localized: "Son ADN cinéphile", bundle: .app))

                GeometryReader { proxy in
                    HStack(spacing: 1.5) {
                        ForEach(genres) { share in
                            Rectangle()
                                .fill(share.color)
                                .frame(width: max(2, proxy.size.width * share.share - 1.5))
                        }
                    }
                }
                .frame(height: 6)

                FlowLayout(spacing: 14) {
                    ForEach(genres.prefix(4)) { share in
                        HStack(spacing: 6) {
                            Rectangle().fill(share.color).frame(width: 5, height: 5)
                            Text(share.name).foregroundStyle(Ink.ink2)
                            Text(share.percentText).foregroundStyle(Ink.ink).monospacedDigit()
                        }
                        .font(.system(size: 11))
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
                    sectionTitle(String(localized: "Sa galerie", bundle: .app))
                    Spacer()
                    Text(verbatim: "\(shown.galleryCount)")
                        .planLabel()
                        .monospacedDigit()
                        .foregroundStyle(Ink.ink2)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(posters) { poster in
                            PosterTile(
                                posterPath: poster.posterPath,
                                title: poster.title,
                                width: 66,
                                cornerRadius: Metrics.radius
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
            .planTitle(21)
            .foregroundStyle(Ink.ink)
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
