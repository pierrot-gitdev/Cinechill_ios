//
//  FollowListView.swift
//  Cinechill_iOS
//

import SwiftUI

/// Les deux listes du Hall — abonnés et abonnements — dans une seule vue.
///
/// Elles ne diffèrent que par la collection lue et par leur état vide : en
/// faire deux écrans distincts aurait dupliqué la ligne, le filtre et la
/// navigation pour une variable.
struct FollowListView: View {
    enum Mode {
        case following
        case followers

        var title: String {
            switch self {
            case .following: String(localized: "Abonnements", bundle: .app)
            case .followers: String(localized: "Abonnés", bundle: .app)
            }
        }

        var emptyTitle: String {
            switch self {
            case .following: String(localized: "Tu ne suis personne", bundle: .app)
            case .followers: String(localized: "Personne ne te suit encore", bundle: .app)
            }
        }

        var icon: CinechillHallIcon {
            switch self {
            case .following: .hall
            case .followers: .salle
            }
        }
    }

    let mode: Mode
    /// Le compte dont on regarde les listes. Le sien par défaut.
    var uid: String?

    @EnvironmentObject private var socialStore: SocialStore

    @State private var profiles: [PublicProfile] = []
    @State private var filter = ""
    @State private var isLoading = true
    /// Un échec de lecture, à distinguer d'une liste vraiment vide : sans
    /// réseau, « Tu ne suis personne » serait un mensonge.
    @State private var loadError: String?
    @State private var pendingFollows: Set<String> = []
    @State private var openedProfile: PublicProfile?
    @State private var showsSearch = false

    private var isOwnList: Bool {
        uid == nil || uid == socialStore.myUID
    }

    private var filtered: [PublicProfile] {
        let needle = SocialStore.normalize(filter)
        guard !needle.isEmpty else { return profiles }
        return profiles.filter {
            SocialStore.normalize($0.displayName).contains(needle)
                || SocialStore.normalize($0.handle).contains(needle)
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if isLoading {
                    loading
                } else if let loadError {
                    HallEmptyState(
                        icon: mode.icon,
                        title: String(localized: "Liste indisponible", bundle: .app),
                        message: loadError,
                        actionTitle: String(localized: "Réessayer", bundle: .app),
                        action: { Task { await load() } }
                    )
                    .padding(.top, 44)
                } else if profiles.isEmpty {
                    emptyState.padding(.top, 44)
                } else {
                    if profiles.count > 8 {
                        HallSearchField(placeholder: String(localized: "Filtrer", bundle: .app), text: $filter)
                            .padding(.horizontal, 18)
                            .padding(.top, 8)
                            .padding(.bottom, 12)
                    }
                    rows
                }
            }
            .padding(.bottom, 30)
        }
        .background(Ink.ground)
        .safeAreaInset(edge: .top) {
            PlanHeader(mode.title) {
                if !profiles.isEmpty {
                    PlanHeaderCount(value: profiles.count.formatted(.number.locale(AppLanguage.current.locale)))
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $openedProfile) { profile in
            PublicProfileView(profile: profile)
        }
        .navigationDestination(isPresented: $showsSearch) {
            ProfileSearchView()
        }
        .task(id: uid ?? "self") { await load() }
    }

    // MARK: - Contenu

    private var rows: some View {
        ForEach(filtered) { profile in
            Button {
                openedProfile = profile
            } label: {
                HallProfileRow(
                    profile: profile,
                    showsGalleryCount: false,
                    isFollowing: socialStore.isFollowing(profile.id),
                    isBusy: pendingFollows.contains(profile.id),
                    onToggleFollow: {
                        Haptics.impact(.light)
                        Task { await toggleFollow(profile) }
                    }
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 18)

            Divider().padding(.leading, 66)
        }
    }

    private var loading: some View {
        HStack {
            Spacer()
            CinechillSpinner(size: 26)
            Spacer()
        }
        .padding(.top, 60)
    }

    /// Les états vides disent la conséquence, pas la mécanique — et donnent
    /// l'outil plutôt qu'un encouragement.
    @ViewBuilder
    private var emptyState: some View {
        switch mode {
        case .following:
            HallEmptyState(
                icon: .hall,
                title: mode.emptyTitle,
                message: isOwnList
                    // Les recommandations ne passent pas par cette liste : on
                    // recommande à ceux qu'on suit, et on reçoit de ceux qui
                    // nous suivent. « Arrivent ici » était faux.
                    ? String(localized: "Suis quelqu'un dont tu aimes les goûts pour voir ses films et lui en recommander.", bundle: .app)
                    : String(localized: "Cette personne ne suit encore personne.", bundle: .app),
                actionTitle: isOwnList ? String(localized: "Chercher un profil", bundle: .app) : nil,
                action: isOwnList ? { showsSearch = true } : nil
            )
        case .followers:
            HallEmptyState(
                icon: .salle,
                title: mode.emptyTitle,
                message: isOwnList
                    ? followersHint
                    : String(localized: "Personne ne suit encore cette personne.", bundle: .app)
            )
        }
    }

    private var followersHint: String {
        guard let handle = socialStore.myProfile?.handleDisplay else {
            return String(localized: "Choisis un pseudo pour qu'on puisse te retrouver.", bundle: .app)
        }
        return String(localized: "Ton pseudo est \(handle). Partage-le pour qu'on te retrouve.", bundle: .app)
    }

    // MARK: - Chargement

    private func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        guard let target = uid ?? socialStore.myUID else {
            profiles = []
            return
        }
        do {
            let ids: [String]
            switch mode {
            case .following: ids = try await socialStore.followingUIDs(of: target)
            case .followers: ids = try await socialStore.followerUIDs(of: target)
            }
            let me = socialStore.myUID
            profiles = try await socialStore.profiles(uids: ids)
                .filter { $0.id != me }
                .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        } catch is CancellationError {
            return
        } catch {
            // La liste déjà affichée tombe : l'en-tête compterait sinon des
            // personnes que l'écran ne montre plus.
            profiles = []
            loadError = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    private func toggleFollow(_ profile: PublicProfile) async {
        guard !pendingFollows.contains(profile.id) else { return }
        pendingFollows.insert(profile.id)
        defer { pendingFollows.remove(profile.id) }
        do {
            try await socialStore.toggleFollow(uid: profile.id)
        } catch {
            // Rien n'a changé : le bouton reste tel quel, la vibration le dit.
            Haptics.warning()
        }
    }
}
