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
    @Environment(MediaCatalog.self) private var catalog

    @State private var showProfile = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()

                if libraryStore.galleryItems.isEmpty {
                    emptyState.padding(.horizontal, 34)
                } else {
                    content
                }
            }
            .safeAreaInset(edge: .top) {
                AppHeaderView(onProfileTap: { showProfile = true })
                    .padding(.horizontal)
                    .padding(.top, 10)
                    .padding(.bottom, 6)
                    .background(.ultraThinMaterial)
            }
            .navigationBarHidden(true)
            .fullScreenCover(isPresented: $showProfile) {
                ProfileView()
                    .environmentObject(profileStore)
                    .environmentObject(libraryStore)
                    .environmentObject(authService)
            }
        }
        .task {
            await catalog.loadIfNeeded()
            syncModel()
        }
        .onChange(of: libraryStore.galleryItems) { _, _ in syncModel() }
        .onChange(of: catalog.genreNames) { _, _ in syncModel() }
    }

    private func syncModel() {
        model.update(entries: libraryStore.galleryItems, genreNames: catalog.genreNames)
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

    private var axisPicker: some View {
        HStack(spacing: 6) {
            ForEach(GalleryAxis.allCases) { axis in
                let isSelected = model.axis == axis
                Button {
                    Haptics.selection()
                    model.axis = axis
                } label: {
                    Text(axis.label)
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        .foregroundStyle(isSelected ? Color(.systemBackground) : .secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background {
                            if isSelected {
                                Capsule().fill(Color.primary)
                            } else {
                                Capsule().fill(Color(.secondarySystemBackground))
                            }
                        }
                }
                .buttonStyle(PressableScaleStyle(scale: 0.92))
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private func bandView(_ band: GalleryBand) -> some View {
        let posterWidth = model.posterWidth(for: band)

        return VStack(alignment: .leading, spacing: 8) {
            NavigationLink(destination: GalleryBandGridView(band: band)) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(band.title)
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(.primary)
                        .monospacedDigit()

                    if let subtitle = band.subtitle {
                        Text(subtitle)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)

                    Text("\(band.count)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    ForEach(band.entries) { entry in
                        NavigationLink(destination: ItemDetailView(item: entry.mediaItem)) {
                            PosterTile(
                                posterPath: entry.posterPath,
                                title: entry.title,
                                width: posterWidth,
                                cornerRadius: max(4, posterWidth * 0.09)
                            )
                        }
                        .buttonStyle(PressableScaleStyle(scale: 0.93))
                    }
                }
                .padding(.horizontal, 20)
            }
            .scrollClipDisabled()
        }
    }

    // MARK: - Vide

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "square.stack.3d.up.slash")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(.tertiary)
            Text("Votre collection est vide")
                .font(.system(size: 19, weight: .bold, design: .rounded))
            Text("Chaque film que vous marquez comme vu vient s'y ranger, et dessine peu à peu votre profil de cinéphile.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Commencer à swiper") {
                selectedTab = 2
            }
            .buttonStyle(.borderedProminent)
            .tint(.indigo)
            .padding(.top, 4)
        }
    }
}
