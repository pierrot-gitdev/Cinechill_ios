//
//  WatchlistView.swift
//  Cinechill_iOS
//

import SwiftUI

/// La watchlist — « La Séance ».
///
/// Rien n'est trié par date d'ajout, parce que ce n'est pas la question qu'on
/// se pose devant sa watchlist. Tout converge vers un seul choix : le temps
/// qu'on a, ce qu'on peut lancer maintenant, et une proposition à trancher.
struct WatchlistView: View {
    @Bindable var model: WatchlistViewModel
    @Binding var selectedTab: Int

    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var libraryStore: LibraryStore
    @EnvironmentObject private var profileStore: UserProfileStore
    @Environment(BadgesViewModel.self) private var badgesModel
    @Environment(MediaCatalog.self) private var catalog

    @State private var showProfile = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()

                if libraryStore.watchlistItems.isEmpty {
                    emptyState.padding(.horizontal, 34)
                } else {
                    content
                }
            }
            .safeAreaInset(edge: .top) {
                AppHeaderView(title: "Watchlist", onProfileTap: { showProfile = true })
            }
            .navigationBarHidden(true)
            .fullScreenCover(isPresented: $showProfile) {
                ProfileView(badgesModel: badgesModel)
                    .environmentObject(profileStore)
                    .environmentObject(libraryStore)
                    .environmentObject(authService)
            }
        }
        .task {
            await catalog.loadIfNeeded()
            await syncModel()
        }
        .onChange(of: libraryStore.watchlistItems) { _, _ in Task { await syncModel() } }
        .onChange(of: libraryStore.preferredPlatformIDs) { _, _ in Task { await syncModel() } }
        .onChange(of: catalog.platforms) { _, _ in Task { await syncModel() } }
    }

    private func syncModel() async {
        await model.update(
            entries: libraryStore.watchlistItems,
            preferredPlatformIDs: libraryStore.preferredPlatformIDs,
            platforms: catalog.platforms
        )
    }

    // MARK: - Contenu

    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                budgetPicker

                if let pick = model.tonight {
                    TonightCardView(
                        pick: pick,
                        platformName: platformName(for: pick.item),
                        onWatch: { watch(pick.item) },
                        onReject: {
                            Haptics.impact(.light)
                            withAnimation(.spring(response: 0.34, dampingFraction: 0.8)) {
                                model.rejectTonight()
                            }
                        }
                    )
                    .padding(.horizontal, 18)
                    .padding(.bottom, 6)
                    .transition(.opacity)
                    .id(pick.item.id)
                }

                if libraryStore.preferredPlatformIDs.isEmpty {
                    declarePlatformsBanner
                }

                ForEach(model.groups) { group in
                    groupSection(group)
                }

                budgetFooter
            }
            .padding(.bottom, 24)
        }
        .animation(.easeInOut(duration: 0.25), value: model.budget)
    }

    private var budgetPicker: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Text("Combien de temps ce soir ?")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)

                if model.isEnriching {
                    CinechillSpinner(size: 14)
                }
            }

            HStack(spacing: 7) {
                ForEach(TimeBudget.allCases) { budget in
                    let isSelected = model.budget == budget
                    Button {
                        Haptics.selection()
                        model.budget = budget
                    } label: {
                        Text(budget.label)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(isSelected ? .white : .primary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background {
                                if isSelected {
                                    Capsule().fill(
                                        LinearGradient(
                                            colors: [.indigo, .pink],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                } else {
                                    Capsule().fill(Color(.secondarySystemBackground))
                                }
                            }
                    }
                    .buttonStyle(PressableScaleStyle(scale: 0.93))
                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 14)
    }

    /// Sans abonnement déclaré, « Disponible chez vous » ne peut rien vouloir
    /// dire : on le remplace par l'invitation à les déclarer, plutôt que
    /// d'afficher un groupe systématiquement vide.
    private var declarePlatformsBanner: some View {
        Button {
            showProfile = true
        } label: {
            HStack(spacing: 11) {
                Image(systemName: "tv.badge.wifi")
                    .font(.system(size: 15))
                    .foregroundStyle(.indigo)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Déclarez vos abonnements")
                        .font(.system(size: 12.5, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text("Pour savoir ce que vous pouvez lancer tout de suite.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(13)
            .background(Color.indigo.opacity(0.09), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.indigo.opacity(0.22), lineWidth: 1)
            )
        }
        .buttonStyle(PressableScaleStyle(scale: 0.98))
        .padding(.horizontal, 18)
        .padding(.top, 6)
    }

    private func groupSection(_ group: WatchlistGroup) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(group.title)
                    .font(.system(size: 9.5, weight: .heavy, design: .rounded))
                    .kerning(0.9)
                    .foregroundStyle(group.kind == .dormant ? .orange : .secondary)

                Spacer(minLength: 0)

                if group.kind == .dormant {
                    Button {
                        Haptics.selection()
                        withAnimation(.easeOut(duration: 0.2)) { model.isTriaging.toggle() }
                    } label: {
                        Text(model.isTriaging ? "Terminé" : "Faire le tri")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.indigo)
                    }
                } else {
                    Text("\(group.items.count)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 6)

            ForEach(group.items) { item in
                row(item, isDormant: group.kind == .dormant)
            }
        }
    }

    private func row(_ item: WatchlistItem, isDormant: Bool) -> some View {
        HStack(spacing: 11) {
            NavigationLink(destination: ItemDetailView(item: item.entry.mediaItem)) {
                HStack(spacing: 11) {
                    PosterTile(
                        posterPath: item.entry.posterPath,
                        title: item.entry.title,
                        width: 30,
                        cornerRadius: 5
                    )

                    Text(item.entry.title)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    if let runtime = item.runtimeText {
                        Text(runtime)
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }

                    platformBadge(for: item)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isDormant, model.isTriaging {
                Button {
                    Haptics.impact(.light)
                    libraryStore.removeFromWatchlist(item.entry.mediaItem)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 26)
                        .background(Color(.tertiarySystemFill), in: Circle())
                }
                .buttonStyle(PressableScaleStyle(scale: 0.9))
                .transition(.scale.combined(with: .opacity))
                .accessibilityLabel("Retirer \(item.entry.title) de la watchlist")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 5)
    }

    @ViewBuilder
    private func platformBadge(for item: WatchlistItem) -> some View {
        if let platform = preferredPlatform(for: item) {
            PlatformBadge(platform: platform)
        } else if item.providerIDs.isEmpty {
            Text("—")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.tertiary)
                .frame(width: 20, height: 20)
        } else {
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 20, height: 20)
        }
    }

    @ViewBuilder
    private var budgetFooter: some View {
        if model.hiddenByBudget > 0 {
            Button {
                Haptics.selection()
                model.budget = .any
            } label: {
                Text("\(model.hiddenByBudget) film\(model.hiddenByBudget > 1 ? "s" : "") dépasse\(model.hiddenByBudget > 1 ? "nt" : "") \(model.budget.label) · Tout voir")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
        }
    }

    // MARK: - Actions

    private func watch(_ item: WatchlistItem) {
        Haptics.success()
        libraryStore.addToGallery(item.entry.mediaItem)
    }

    private func preferredPlatform(for item: WatchlistItem) -> StreamingPlatform? {
        let preferred = Set(libraryStore.preferredPlatformIDs.compactMap(Int.init))
        guard let providerID = item.providerIDs.first(where: { preferred.contains($0) }) else {
            return nil
        }
        return catalog.platform(forProvider: providerID)
    }

    private func platformName(for item: WatchlistItem) -> String? {
        preferredPlatform(for: item)?.name
    }

    // MARK: - Vide

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "bookmark.slash")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(.tertiary)
            Text("Rien en attente")
                .font(.system(size: 19, weight: .bold, design: .rounded))
            Text("Balayez un film vers le haut depuis le deck pour le mettre de côté. On vous dira quoi en regarder, et quand.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Trouver des films") {
                selectedTab = 2
            }
            .buttonStyle(.borderedProminent)
            .tint(.indigo)
            .padding(.top, 4)
        }
    }
}

/// Le logo de la plateforme, ou ses initiales si TMDB n'en fournit pas.
private struct PlatformBadge: View {
    let platform: StreamingPlatform

    var body: some View {
        Group {
            if let url = platform.logoURL {
                PosterImageView(url: url)
            } else {
                Text(platform.shortLabel)
                    .font(.system(size: 8, weight: .heavy, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.tertiarySystemFill))
            }
        }
        .frame(width: 20, height: 20)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .accessibilityLabel("Disponible sur \(platform.name)")
    }
}
