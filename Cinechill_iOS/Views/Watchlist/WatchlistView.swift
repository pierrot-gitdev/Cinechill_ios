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
    @EnvironmentObject private var socialStore: SocialStore
    @Environment(BadgesViewModel.self) private var badgesModel
    @Environment(MediaCatalog.self) private var catalog

    @State private var showProfile = false

    var body: some View {
        NavigationStack {
            ZStack {
                Ink.ground.ignoresSafeArea()

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
                    .environmentObject(socialStore)
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
                    .padding(.horizontal, Metrics.margin)
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Text("Combien de temps ce soir ?")
                    .planLabel()
                    .foregroundStyle(Ink.ink2)

                if model.isEnriching {
                    CinechillSpinner(size: 14)
                }
            }

            HStack(spacing: 7) {
                ForEach(TimeBudget.allCases) { budget in
                    PlanChip(title: budget.label, isOn: model.budget == budget) {
                        Haptics.selection()
                        model.budget = budget
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, Metrics.margin)
        .padding(.top, 18)
        .padding(.bottom, 16)
    }

    /// Sans abonnement déclaré, « Disponible chez vous » ne peut rien vouloir
    /// dire : on le remplace par l'invitation à les déclarer, plutôt que
    /// d'afficher un groupe systématiquement vide.
    /// Une invitation n'est pas une carte : c'est une ligne, entre deux filets,
    /// précédée du point. Le même dispositif que la remarque de la fiche film.
    private var declarePlatformsBanner: some View {
        Button {
            showProfile = true
        } label: {
            HStack(alignment: .top, spacing: 11) {
                PlanLight().padding(.top, 6)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Déclarez vos abonnements")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Ink.ink)
                    Text("Pour savoir ce que vous pouvez lancer tout de suite.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Ink.ink2)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
            .overlay(alignment: .top) { PlanEdge() }
            .overlay(alignment: .bottom) { PlanEdge() }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Metrics.margin)
        .padding(.top, 8)
    }

    private func groupSection(_ group: WatchlistGroup) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(group.title)
                    .planLabel()
                    .foregroundStyle(headerTint(for: group.kind))

                Spacer(minLength: 0)

                if group.kind == .dormant {
                    Button {
                        Haptics.selection()
                        withAnimation(Metrics.unfold) { model.isTriaging.toggle() }
                    } label: {
                        Text(model.isTriaging ? "Terminé" : "Faire le tri")
                            .font(.system(size: 12))
                            .foregroundStyle(Ink.ink2)
                            .overlay(alignment: .bottom) {
                                Rectangle().fill(Ink.ruleSet).frame(height: 1).offset(y: 2)
                            }
                            .contentShape(Rectangle().inset(by: -10))
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("\(group.items.count)")
                        .planLabel()
                        .monospacedDigit()
                        .foregroundStyle(Ink.ink3)
                }
            }
            .padding(.horizontal, Metrics.margin)
            .padding(.top, 18)
            .padding(.bottom, 8)

            ForEach(group.items) { item in
                row(item, isDormant: group.kind == .dormant)
            }
        }
    }

    /// La lumière signale ce qui vient d'un ami, l'écart ce qui dort depuis trop
    /// longtemps. Ce sont les deux seuls en-têtes teintés de l'écran, et ce sont
    /// les deux seules teintes du système — l'orange d'iOS a laissé la place.
    private func headerTint(for kind: WatchlistGroup.Kind) -> Color {
        switch kind {
        case .recommended: Ink.light
        case .dormant: Ink.warn
        default: Ink.ink3
        }
    }

    private func row(_ item: WatchlistItem, isDormant: Bool) -> some View {
        HStack(spacing: 11) {
            NavigationLink(destination: ItemDetailView(item: item.entry.mediaItem)) {
                HStack(spacing: 11) {
                    // Sur une ligne de 30 pt, un visage se lit plus vite
                    // qu'une vignette d'affiche : l'avatar prend sa place
                    // quand le film vient de quelqu'un.
                    if item.entry.isRecommended {
                        HallAvatarStack(recommenders: item.entry.recommendedBy, size: 30)
                    } else {
                        PosterTile(
                            posterPath: item.entry.posterPath,
                            title: item.entry.title,
                            width: 30
                        )
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.entry.title)
                            .font(.system(size: 13.5))
                            .foregroundStyle(Ink.ink)
                            .lineLimit(1)

                        if let provenance = item.entry.recommendedByText {
                            Text(provenance)
                                .font(.system(size: 10.5))
                                .foregroundStyle(Ink.ink2)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 4)

                    if let runtime = item.runtimeText {
                        Text(runtime)
                            .font(.system(size: 10.5))
                            .monospacedDigit()
                            .foregroundStyle(Ink.ink3)
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
                    WatchlistRemoveGlyph()
                        .stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                        .foregroundStyle(Ink.warn)
                        .frame(width: 12, height: 12)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableScaleStyle(scale: 0.9))
                .transition(.opacity)
                .accessibilityLabel("Retirer \(item.entry.title) de la watchlist")
            }
        }
        .padding(.horizontal, Metrics.margin)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func platformBadge(for item: WatchlistItem) -> some View {
        if let platform = preferredPlatform(for: item) {
            PlatformBadge(platform: platform)
        } else if item.providerIDs.isEmpty {
            Text("—")
                .font(.system(size: 11))
                .foregroundStyle(Ink.ink3)
                .frame(width: 20, height: 20)
        } else {
            // Disponible, mais pas chez vous : le point creux du vocabulaire
            // commun, plutôt qu'un symbole de téléchargement qui ne veut rien
            // dire ici.
            PlanLightOutline(tint: Ink.ink3)
                .frame(width: 20, height: 20)
                .accessibilityLabel("Hors de vos abonnements")
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
                    .font(.system(size: 12))
                    .foregroundStyle(Ink.ink2)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Metrics.margin)
            .padding(.top, 22)
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
        PlanEmptyState(
            icon: .salle,
            title: "Rien en attente",
            message: "Balayez un film vers le haut depuis le deck pour le mettre de côté. On vous dira quoi en regarder, et quand.",
            actionTitle: "Trouver des films",
            action: { selectedTab = 2 }
        )
    }
}

/// La croix de retrait, dans l'écriture de la famille.
private struct WatchlistRemoveGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        return path
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
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.tertiarySystemFill))
            }
        }
        .frame(width: 20, height: 20)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous))
        .accessibilityLabel("Disponible sur \(platform.name)")
    }
}
