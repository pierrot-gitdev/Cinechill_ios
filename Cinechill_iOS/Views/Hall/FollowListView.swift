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
            case .following: "Abonnements"
            case .followers: "Abonnés"
            }
        }

        var emptyTitle: String {
            switch self {
            case .following: "Vous ne suivez personne"
            case .followers: "Personne ne vous suit encore"
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
                } else if profiles.isEmpty {
                    emptyState.padding(.top, 44)
                } else {
                    if profiles.count > 8 {
                        HallSearchField(placeholder: "Filtrer", text: $filter)
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
                    PlanHeaderCount(value: "\(profiles.count)")
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
                    ? "Les films qu'on vous recommande arrivent ici. Commencez par quelqu'un dont vous aimez les goûts."
                    : "Cette personne ne suit encore personne.",
                actionTitle: isOwnList ? "Chercher un profil" : nil,
                action: isOwnList ? { showsSearch = true } : nil
            )
        case .followers:
            HallEmptyState(
                icon: .salle,
                title: mode.emptyTitle,
                message: isOwnList
                    ? followersHint
                    : "Personne ne suit encore cette personne."
            )
        }
    }

    private var followersHint: String {
        guard let handle = socialStore.myProfile?.handleDisplay else {
            return "Choisissez un pseudo pour qu'on puisse vous retrouver."
        }
        return "Votre pseudo est \(handle). Partagez-le pour qu'on vous retrouve."
    }

    // MARK: - Chargement

    private func load() async {
        isLoading = true
        defer { isLoading = false }

        guard let target = uid ?? socialStore.myUID else {
            profiles = []
            return
        }
        let ids: [String]
        switch mode {
        case .following: ids = await socialStore.followingUIDs(of: target)
        case .followers: ids = await socialStore.followerUIDs(of: target)
        }
        let me = socialStore.myUID
        profiles = await socialStore.profiles(uids: ids)
            .filter { $0.id != me }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private func toggleFollow(_ profile: PublicProfile) async {
        guard !pendingFollows.contains(profile.id) else { return }
        pendingFollows.insert(profile.id)
        defer { pendingFollows.remove(profile.id) }
        try? await socialStore.toggleFollow(uid: profile.id)
    }
}
