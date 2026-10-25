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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
    /// Un film à cœur dont on a demandé le retrait : le cœur part avec lui,
    /// on le demande d'abord, comme la fiche.
    @State private var pendingRemoval: MediaItem?
    @State private var outcome: SuggestionOutcome?

    var body: some View {
        NavigationStack {
            ZStack {
                Ink.ground.ignoresSafeArea()

                // Avant le premier instantané, une liste vide n'est pas un
                // état vide : il clignotait au lancement d'un compte neuf.
                if libraryStore.galleryItems.isEmpty && !libraryStore.hasLoadedGalleryOnce {
                    CinechillSpinner(size: 26)
                } else if libraryStore.galleryItems.isEmpty {
                    emptyState.padding(.horizontal, 34)
                } else {
                    content
                }
            }
            .safeAreaInset(edge: .top) {
                AppHeaderView(title: String(localized: "Galerie", bundle: .app), onProfileTap: { showProfile = true })
            }
            .navigationBarHidden(true)
            // Des liens par valeur, et non par destination : retirer un film de
            // la frise depuis sa fiche retirait le lien qui l'avait poussée, et
            // la fiche pouvait se refermer seule.
            .navigationDestination(for: MediaItem.self) { item in
                ItemDetailView(item: item)
            }
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
            // Les bandes se rangent sans attendre le répertoire des genres :
            // sur un réseau lent, la galerie restait sans bandes jusqu'à sa
            // réponse. Les noms de genres les rejoignent à son arrivée.
            syncModel()
            await catalog.loadIfNeeded()
            syncModel()
        }
        .task(id: outcome) {
            guard outcome != nil else { return }
            try? await Task.sleep(for: .seconds(3))
            withAnimation(.easeOut(duration: 0.25)) { outcome = nil }
        }
        .alert(
            String(localized: "Retirer de ta galerie", bundle: .app),
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            ),
            presenting: pendingRemoval
        ) { item in
            Button(String(localized: "Retirer", bundle: .app), role: .destructive) {
                libraryStore.removeFromGallery(item)
                pendingRemoval = nil
            }
            Button(String(localized: "Annuler", bundle: .app), role: .cancel) {}
        } message: { _ in
            Text("Le film quitte ta galerie, et ton coup de cœur avec lui.", bundle: .app)
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
        // Ease-out : le changement d'axe répond à un appui, la réponse doit
        // partir vite et se poser doucement.
        .animation(reduceMotion ? nil : .easeOut(duration: 0.24), value: model.axis)
    }

    /// Le voile de la nuit remplace `ultraThinMaterial` : c'était le seul
    /// matériau translucide d'un écran par ailleurs entièrement bâti sur des
    /// filets.
    private var axisPicker: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                ForEach(GalleryAxis.allCases) { axis in
                    PlanChip(title: axis.label, isOn: model.axis == axis) {
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
                // Le sous-titre passe sous le titre quand la ligne ne tient
                // plus (texte agrandi, anglais sur un petit écran).
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline, spacing: 9) {
                            bandTitle(band)
                            bandSubtitle(band)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            bandTitle(band)
                            bandSubtitle(band)
                        }
                    }

                    Spacer(minLength: 0)

                    Text(verbatim: band.count.formatted(.number.locale(AppLanguage.current.locale)))
                        .planLabel()
                        .monospacedDigit()
                        .foregroundStyle(Ink.ink2)
                        .fixedSize()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Metrics.margin)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    ForEach(band.tiles) { tile in
                        tileView(tile, width: posterWidth)
                    }
                }
                .padding(.horizontal, Metrics.margin)
            }
            .scrollClipDisabled()
        }
    }

    /// Une tuile de la frise. Un film garde son menu ; une série, qui peut
    /// réunir plusieurs saisons, ouvre son dossier et n'en a pas — une action
    /// de masse sur trois saisons d'un appui long serait un piège.
    @ViewBuilder
    private func tileView(_ tile: GalleryTile, width posterWidth: CGFloat) -> some View {
        switch tile {
        case .series:
            if let destination = tile.destination {
                NavigationLink(value: destination) {
                    PosterTile(posterPath: tile.posterPath, title: tile.title, width: posterWidth)
                        .overlay(alignment: .bottomLeading) {
                            if let plate = tile.plate, posterWidth >= 66 {
                                PosterPlate(text: plate)
                            }
                        }
                }
                .buttonStyle(PressableScaleStyle(scale: 0.96))
            }
        case .film(let entry):
            filmTile(entry, width: posterWidth)
        }
    }

    private func bandTitle(_ band: GalleryBand) -> some View {
        Text(band.title)
            .planTitle(16)
            .foregroundStyle(Ink.ink)
            .monospacedDigit()
            .fixedSize()
    }

    @ViewBuilder
    private func bandSubtitle(_ band: GalleryBand) -> some View {
        if let subtitle = band.subtitle {
            Text(subtitle)
                .planLabel()
                .foregroundStyle(Ink.ink2)
        }
    }

    private func filmTile(_ entry: GalleryEntry, width posterWidth: CGFloat) -> some View {
        // Le cœur confirmé seulement : pendant l'écriture, le faisceau prend
        // sa place, et le cœur ne bouge qu'une fois Firestore revenu.
        let loved = entry.isLoved
        let isPending = libraryStore.isLovePending(id: entry.id)
        return NavigationLink(value: entry.mediaItem) {
            PosterTile(
                posterPath: entry.posterPath,
                title: entry.title,
                width: posterWidth
            )
            // Sans ce signe, « Coup de cœur » dans le menu ne changeait rien à
            // l'écran : seule la vibration confirmait le geste.
            .overlay(alignment: .bottomTrailing) {
                if isPending, posterWidth >= 48 {
                    CinechillSpinner(size: 14)
                        .padding(3)
                        .transition(.opacity)
                } else if loved, posterWidth >= 48 {
                    Image(decorative: "ArtefactCoeur")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 14, height: 14)
                        .shadow(color: Ink.ground.opacity(0.8), radius: 2)
                        .padding(3)
                        .transition(.opacity)
                }
            }
            .animation(Metrics.shift, value: loved)
            .animation(Metrics.shift, value: isPending)
        }
        .accessibilityValue(
            isPending
                ? String(localized: "Enregistrement…", bundle: .app)
                : loved ? String(localized: "coup de cœur", bundle: .app) : ""
        )
        .accessibilityAction(named: loved
            ? String(localized: "Retirer le coup de cœur", bundle: .app)
            : String(localized: "Coup de cœur", bundle: .app)
        ) {
            libraryStore.setLove(entry.mediaItem, loved: !loved)
        }
        .buttonStyle(PressableScaleStyle(scale: 0.96))
        // Le raccourci de recommandation. Coût visuel au
        // repos : zéro — c'est ce qui permet de le proposer
        // sans encombrer « La Frise ».
        .contextMenu {
            // Le coup de cœur, même logique que le raccourci de
            // recommandation : coût visuel au repos, zéro.
            Button {
                Haptics.impact(.light, intensity: 0.8)
                libraryStore.setLove(
                    entry.mediaItem,
                    loved: !libraryStore.isLoved(entry.mediaItem)
                )
            } label: {
                if libraryStore.isLoved(entry.mediaItem) {
                    Label(String(localized: "Retirer le coup de cœur", bundle: .app), systemImage: "heart.slash")
                } else {
                    Label(String(localized: "Coup de cœur", bundle: .app), systemImage: "heart")
                }
            }
            // Pas de second ordre tant que le premier n'est pas revenu.
            .disabled(isPending)

            Button {
                composerItem = entry.mediaItem
            } label: {
                Label(String(localized: "Recommander", bundle: .app), systemImage: "paperplane")
            }

            Button(role: .destructive) {
                Haptics.impact(.light)
                if libraryStore.isLoved(entry.mediaItem) {
                    pendingRemoval = entry.mediaItem
                } else {
                    libraryStore.removeFromGallery(entry.mediaItem)
                }
            } label: {
                Label(String(localized: "Retirer de ma galerie", bundle: .app), systemImage: "xmark")
            }
        }
    }

    // MARK: - Vide

    private var emptyState: some View {
        PlanEmptyState(
            icon: .hall,
            title: String(localized: "Ta galerie est vide", bundle: .app),
            message: String(localized: "Les films que tu as vus s'affichent ici. Plus il y en a, mieux on connaît tes goûts.", bundle: .app),
            actionTitle: String(localized: "Commencer à swiper", bundle: .app),
            action: { selectedTab = 2 }
        )
    }
}
