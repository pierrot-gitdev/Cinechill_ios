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
    @EnvironmentObject private var libraryStore: LibraryStore

    @State private var detail: PublicProfileDetail?
    @State private var isLoading = true
    @State private var isTogglingFollow = false
    @State private var errorMessage: String?
    /// Le chargement a échoué : on le dit sur place, avec de quoi réessayer,
    /// au lieu d'une alerte « Impossible » sur un écran qui restait à moitié vide.
    @State private var loadFailed = false
    /// Le serveur ne sert plus ce profil : il a bloqué la personne, ou le
    /// compte a été supprimé. Ce n'est pas une panne, « Réessayer » n'y
    /// changerait rien, et « Suivre » échouerait.
    @State private var isUnavailable = false
    /// Le profil dont on attend la confirmation du blocage.
    @State private var pendingBlock: ReportSubject?
    @State private var reportSubject: ReportSubject?
    @State private var showsRecommend = false
    /// Ce qu'a donné le dernier envoi, le temps du bandeau.
    @State private var outcome: SuggestionOutcome?

    private var shown: PublicProfile { detail?.profile ?? profile }
    private var isFollowing: Bool { socialStore.isFollowing(profile.id) }
    private var isOwnProfile: Bool { profile.id == socialStore.myUID }
    private var isBlocked: Bool { socialStore.isBlocked(profile.id) }
    /// Un blocage ou un déblocage part : le menu tourne, le suivi attend.
    private var isBlockBusy: Bool { socialStore.blocksInFlight.contains(profile.id) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                identity
                stats
                // On ne se suit pas soi-même.
                if !isOwnProfile && !isUnavailable {
                    if isBlocked {
                        blockedState
                            .transition(.opacity)
                    } else {
                        actions
                            .transition(.opacity)
                    }
                }
                if isLoading {
                    loadingRow
                } else if isUnavailable {
                    Text("Ce profil n'est pas accessible.", bundle: .app)
                        .planFont(13)
                        .foregroundStyle(Ink.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                } else if loadFailed {
                    loadFailedRow
                } else {
                    dnaSection
                    postersSection
                    emptyGalleryNote
                }
            }
            .padding(.horizontal, Metrics.margin)
            .padding(.top, 18)
            .padding(.bottom, 36)
        }
        .background(Ink.ground)
        .safeAreaInset(edge: .top) {
            // Sans pseudo, le nom : un « @ » seul se lisait comme une panne.
            PlanHeader(shown.handle.isEmpty ? shown.displayName : shown.handleDisplay) {
                if !isOwnProfile { moreMenu }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task(id: profile.id) { await load() }
        .animation(Metrics.shift, value: isBlocked)
        .blockConfirmation($pendingBlock) { _ in
            Task { await block() }
        }
        .sheet(item: $reportSubject) { subject in
            ReportSheet(subject: subject)
                .environmentObject(socialStore)
        }
        .sheet(isPresented: $showsRecommend) {
            RecommendFilmSheet(profile: shown) { result in
                guard !result.isSilent else { return }
                withAnimation(.easeOut(duration: 0.25)) { outcome = result }
            }
            .environmentObject(libraryStore)
            .environmentObject(socialStore)
        }
        .overlay(alignment: .bottom) {
            if let outcome {
                SuggestionOutcomeBanner(outcome: outcome)
            }
        }
        .task(id: outcome) {
            guard outcome != nil else { return }
            try? await Task.sleep(for: .seconds(3))
            withAnimation(.easeOut(duration: 0.25)) { outcome = nil }
        }
        // Le suivi, le blocage et le déblocage : le message dit déjà ce qui
        // s'est passé, il fait le titre.
        .alert(
            errorMessage ?? "",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button(String(localized: "OK", bundle: .app), role: .cancel) { errorMessage = nil }
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
                    .planFont(12.5)
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
            Text(verbatim: value.formatted(.number.locale(AppLanguage.current.locale)))
                .planTitle(21)
                .foregroundStyle(Ink.ink)
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(label)
                .planLabel()
                .foregroundStyle(Ink.ink2)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: "\(value.formatted(.number.locale(AppLanguage.current.locale))) \(label)"))
    }

    // MARK: - Actions

    /// Un seul état de suivi, réversible d'un tap, sans confirmation : se
    /// désabonner n'est pas destructeur, une alerte y ajouterait une
    /// cérémonie injustifiée.
    ///
    /// Une fois la personne suivie, l'action de l'écran devient « Lui
    /// recommander un film », au plein, au-dessus du suivi qui passe en
    /// contour. Le parcours qui partait du film seul cachait que l'on pouvait
    /// recommander : on vient sur le profil d'un ami pour ça. Avant le suivi,
    /// le bouton n'existe pas : le serveur ne laisse recommander qu'aux
    /// personnes qu'on suit.
    private var actions: some View {
        VStack(spacing: 10) {
            if isFollowing {
                Button {
                    Haptics.impact(.light)
                    showsRecommend = true
                } label: {
                    HStack(spacing: 9) {
                        CinechillHallIconView(.recommander)
                            .frame(width: 17, height: 17)
                        Text("Lui recommander un film", bundle: .app)
                            .planFont(14.5, weight: .semibold)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(Ink.ground)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: Metrics.control)
                    .background(Ink.paper, in: RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous))
                }
                .buttonStyle(PressableScaleStyle(scale: 0.97))
                .disabled(isBlockBusy)
                .transition(.opacity)
            }

            HallFollowButton(
                isFollowing: isFollowing,
                isBusy: isTogglingFollow || isBlockBusy,
                fullWidth: true
            ) {
                Haptics.impact(.medium)
                Task { await toggleFollow() }
            }
        }
        .animation(Metrics.shift, value: isFollowing)
    }

    // MARK: - Blocage

    /// Bloquer et signaler vivent derrière « ⋯ » : on s'en sert rarement, et
    /// un bouton à côté de « Suivre » aurait mis ces deux actions au même rang.
    private var moreMenu: some View {
        Menu {
            Button(String(localized: "Signaler", bundle: .app)) {
                reportSubject = ReportSubject(profile: shown)
            }
            if isBlocked {
                Button(String(localized: "Débloquer", bundle: .app)) {
                    Task { await unblock() }
                }
            } else {
                Button(String(localized: "Bloquer", bundle: .app), role: .destructive) {
                    pendingBlock = ReportSubject(profile: shown)
                }
            }
        } label: {
            Group {
                if isBlockBusy {
                    CinechillSpinner(size: 16)
                } else {
                    HallMoreGlyph()
                        .foregroundStyle(Ink.ink)
                }
            }
            .frame(width: 34, height: 34)
            .contentShape(Rectangle().inset(by: -5))
        }
        .disabled(isBlockBusy)
        .accessibilityLabel(String(localized: "Options du profil", bundle: .app))
    }

    /// À la place du bouton de suivi, une fois le profil bloqué. Le bloqueur
    /// voit encore ce profil, et c'est d'ici qu'il le débloque.
    private var blockedState: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Tu as bloqué ce profil", bundle: .app)
                    .planFont(14.5, weight: .medium)
                    .foregroundStyle(Ink.ink)
                Text("Plus d'abonnement ni de film entre ce profil et toi. Le débloquer ne rétablit pas les abonnements.", bundle: .app)
                    .planFont(12.5)
                    .foregroundStyle(Ink.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            PlanSecondaryButton(
                title: isBlockBusy
                    ? String(localized: "Déblocage…", bundle: .app)
                    : String(localized: "Débloquer", bundle: .app),
                isEnabled: !isBlockBusy,
                height: Metrics.control
            ) {
                Task { await unblock() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - ADN

    @ViewBuilder
    private var dnaSection: some View {
        if let genres = detail?.genres, !genres.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle(String(localized: "Ses goûts", bundle: .app))

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
                        .planFont(11)
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
                    Text(verbatim: shown.galleryCount.formatted(.number.locale(AppLanguage.current.locale)))
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

    /// Un profil sans film vu ne laissait rien sous le bouton de suivi.
    @ViewBuilder
    private var emptyGalleryNote: some View {
        if let detail, detail.genres.isEmpty, detail.posters.isEmpty {
            Text("Sa galerie est vide pour l'instant.", bundle: .app)
                .planFont(13)
                .foregroundStyle(Ink.ink2)
        }
    }

    private var loadFailedRow: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("On n'a pas pu charger ses goûts et sa galerie.", bundle: .app)
                .planFont(13)
                .foregroundStyle(Ink.ink2)
                .fixedSize(horizontal: false, vertical: true)
            PlanSecondaryButton(title: String(localized: "Réessayer", bundle: .app), height: Metrics.control) {
                Task { await load() }
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
        loadFailed = false
        defer { isLoading = false }
        do {
            detail = try await socialStore.profileDetail(uid: profile.id)
        } catch is CancellationError {
            return
        } catch SocialError.targetNotFound {
            isUnavailable = true
        } catch {
            loadFailed = true
        }
    }

    /// Le serveur défait les abonnements dans les deux sens : les compteurs
    /// affichés sont relus ensuite, sans roue, pour ne pas mentir.
    private func block() async {
        do {
            try await socialStore.block(uid: profile.id)
        } catch is CancellationError {
            return
        } catch {
            Haptics.warning()
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
            return
        }
        if let fresh = try? await socialStore.profileDetail(uid: profile.id) {
            detail = fresh
        }
    }

    private func unblock() async {
        do {
            try await socialStore.unblock(uid: profile.id)
        } catch is CancellationError {
            return
        } catch {
            Haptics.warning()
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
