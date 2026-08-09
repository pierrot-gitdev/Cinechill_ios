//
//  GalleryView.swift
//  Cinechill_iOS
//

import SwiftUI

/// La galerie — « La Frise ».
///
/// La collection est découpée en bandes, et **la taille des affiches encode le
/// volume de la bande**. La mise en page est donc elle-même le graphique : on
/// fait défiler et on voit la forme de sa cinéphilie, y compris ses trous.
/// C'est ce qui remplace un scroll de vignettes uniformes, sans intérêt passé
/// la centaine de films.
struct GalleryView: View {
    @Bindable var model: GalleryViewModel
    @Binding var selectedTab: Int

    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var libraryStore: LibraryStore
    @EnvironmentObject private var profileStore: UserProfileStore
    @EnvironmentObject private var socialStore: SocialStore
    @Environment(BadgesViewModel.self) private var badgesModel
    @Environment(MediaCatalog.self) private var catalog

    @State private var showProfile = false
    @State private var composerItem: MediaItem?
    @State private var outcome: SuggestionOutcome?

    var body: some View {
        NavigationStack {
            ZStack {
                Ink.ground.ignoresSafeArea()

                if libraryStore.galleryItems.isEmpty {
                    emptyState.padding(.horizontal, 34)
                } else {
                    content
                }
            }
            .safeAreaInset(edge: .top) {
                AppHeaderView(title: String(localized: "Galerie", bundle: .app), onProfileTap: { showProfile = true })
            }
            .navigationBarHidden(true)
            .fullScreenCover(isPresented: $showProfile) {
                ProfileView(badgesModel: badgesModel)
                    .environmentObject(profileStore)
                    .environmentObject(libraryStore)
                    .environmentObject(authService)
                    .environmentObject(socialStore)
            }
            .overlay(alignment: .bottom) { outcomeBanner }
        }
        .sheet(item: $composerItem) { item in
            SuggestionComposerSheet(item: item) { result in
                guard !result.isSilent else { return }
                withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                    outcome = result
                }
            }
            .environmentObject(socialStore)
        }
        .task {
            await catalog.loadIfNeeded()
            syncModel()
        }
        .task(id: outcome) {
            guard outcome != nil else { return }
            try? await Task.sleep(for: .seconds(3))
            withAnimation(.easeOut(duration: 0.25)) { outcome = nil }
        }
        .onChange(of: libraryStore.galleryItems) { _, _ in syncModel() }
        .onChange(of: catalog.genreNames) { _, _ in syncModel() }
    }

    private func syncModel() {
        model.update(entries: libraryStore.galleryItems, genreNames: catalog.genreNames)
    }

    @ViewBuilder
    private var outcomeBanner: some View {
        if let outcome {
            SuggestionOutcomeBanner(outcome: outcome)
        }
    }

    // MARK: - Contenu

    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                GallerySignatureView(signature: model.signature)

                Section {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(model.bands) { band in
                            bandView(band)
                        }
                    }
                    .padding(.top, 14)
                    .padding(.bottom, 26)
                } header: {
                    axisPicker
                }
            }
        }
        .animation(.easeInOut(duration: 0.28), value: model.axis)
    }

    /// Le voile de la nuit remplace `ultraThinMaterial` : c'était le seul
    /// matériau translucide d'un écran par ailleurs entièrement bâti sur des
    /// filets.
    private var axisPicker: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                ForEach(GalleryAxis.allCases) { axis in
                    PlanChip(title: axis.label, isOn: model.axis == axis) {
                        Haptics.selection()
                        model.axis = axis
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Metrics.margin)
            .padding(.vertical, 12)

            PlanEdge()
        }
        .background(Ink.ground)
    }

    private func bandView(_ band: GalleryBand) -> some View {
        let posterWidth = model.posterWidth(for: band)

        return VStack(alignment: .leading, spacing: 8) {
            NavigationLink(destination: GalleryBandGridView(band: band)) {
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Text(band.title)
                        .planTitle(16)
                        .foregroundStyle(Ink.ink)
                        .monospacedDigit()

                    if let subtitle = band.subtitle {
                        Text(subtitle)
                            .planLabel()
                            .foregroundStyle(Ink.ink3)
                    }

                    Spacer(minLength: 0)

                    Text(verbatim: "\(band.count)")
                        .planLabel()
                        .monospacedDigit()
                        .foregroundStyle(Ink.ink3)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Metrics.margin)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    ForEach(band.entries) { entry in
                        NavigationLink(destination: ItemDetailView(item: entry.mediaItem)) {
                            PosterTile(
                                posterPath: entry.posterPath,
                                title: entry.title,
                                width: posterWidth
                            )
                        }
                        .buttonStyle(PressableScaleStyle(scale: 0.93))
                        // Le raccourci de recommandation. Coût visuel au
                        // repos : zéro — c'est ce qui permet de le proposer
                        // sans encombrer « La Frise ».
                        .contextMenu {
                            Button {
                                composerItem = entry.mediaItem
                            } label: {
                                Label(String(localized: "Recommander", bundle: .app), systemImage: "paperplane")
                            }

                            Button(role: .destructive) {
                                Haptics.impact(.light)
                                libraryStore.removeFromGallery(entry.mediaItem)
                            } label: {
                                Label(String(localized: "Retirer de ma galerie", bundle: .app), systemImage: "xmark")
                            }
                        }
                    }
                }
                .padding(.horizontal, Metrics.margin)
            }
            .scrollClipDisabled()
        }
    }

    // MARK: - Vide

    private var emptyState: some View {
        PlanEmptyState(
            icon: .hall,
            title: String(localized: "Votre collection est vide", bundle: .app),
            message: String(localized: "Chaque film que vous marquez comme vu vient s'y ranger, et dessine peu à peu votre profil de cinéphile.", bundle: .app),
            actionTitle: String(localized: "Commencer à swiper", bundle: .app),
            action: { selectedTab = 2 }
        )
    }
}
