//
//  SuggestionSettingsScreens.swift
//  Cinechill_iOS
//

import SwiftUI

/// Réglages › Mes plateformes.
///
/// La grille occupait la moitié de l'écran des réglages pour un choix qu'on
/// fait une fois. Elle vit ici, et les réglages n'en gardent qu'une ligne qui
/// nomme ce qui est retenu.
struct PlatformSettingsView: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    @Environment(MediaCatalog.self) private var catalog

    var body: some View {
        SettingsSubpage(
            title: String(localized: "Mes plateformes", bundle: .app),
            note: String(localized: "On ne te proposera que des films disponibles sur tes plateformes.", bundle: .app)
        ) {
            if catalog.platforms.isEmpty {
                HStack(spacing: 10) {
                    CinechillSpinner(size: 16)
                    Text("Chargement des plateformes…", bundle: .app)
                        .planFont(13)
                        .foregroundStyle(Ink.ink2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                PlatformGrid(
                    platforms: catalog.platforms,
                    selection: Binding(
                        get: { libraryStore.preferredPlatformIDs },
                        set: { libraryStore.setPreferredPlatforms($0) }
                    )
                )
            }
        }
        .task { await catalog.loadIfNeeded() }
    }
}

/// Réglages › Genres exclus.
///
/// Une liste à cocher plutôt qu'un nuage de puces barrées : une ligne par
/// genre se lit de haut en bas, et la case cochée dit « exclu » sans qu'il
/// faille apprendre ce que veut dire une puce rayée.
struct BannedGenresSettingsView: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    @Environment(MediaCatalog.self) private var catalog

    private var sortedGenres: [(id: Int, name: String)] {
        catalog.genreNames
            .map { (id: $0.key, name: $0.value) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        SettingsSubpage(
            title: String(localized: "Genres exclus", bundle: .app),
            note: String(localized: "Coche les genres qu'on ne doit jamais te proposer.", bundle: .app)
        ) {
            if catalog.genreNames.isEmpty {
                HStack(spacing: 10) {
                    CinechillSpinner(size: 16)
                    Text("Chargement des genres…", bundle: .app)
                        .planFont(13)
                        .foregroundStyle(Ink.ink2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 0) {
                    ForEach(sortedGenres, id: \.id) { genre in
                        row(genre)
                    }
                }
            }
        }
        .task { await catalog.loadIfNeeded() }
    }

    private func row(_ genre: (id: Int, name: String)) -> some View {
        let isBanned = libraryStore.bannedGenreIDs.contains(genre.id)
        return Button {
            Haptics.impact(.light)
            var ids = libraryStore.bannedGenreIDs
            if isBanned { ids.remove(genre.id) } else { ids.insert(genre.id) }
            libraryStore.setBannedGenres(ids)
        } label: {
            HStack(spacing: 12) {
                Text(genre.name)
                    .planFont(15)
                    .foregroundStyle(Ink.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                // La case cochée prend l'écart : exclure est un retrait, et
                // c'est la même teinte que la puce barrée qu'elle remplace.
                RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                    .strokeBorder(isBanned ? Color.clear : Ink.ruleSet, lineWidth: 1)
                    .background(
                        RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                            .fill(isBanned ? Ink.warn : Color.clear)
                    )
                    .overlay {
                        if isBanned {
                            BannedCheckGlyph()
                                .stroke(Ink.ground, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                                .frame(width: 11, height: 11)
                        }
                    }
                    .frame(width: 20, height: 20)
                    .animation(Metrics.shift, value: isBanned)
            }
            .frame(minHeight: 50)
            .contentShape(Rectangle())
            .overlay(alignment: .top) { PlanEdge() }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityValue(isBanned ? String(localized: "Exclu", bundle: .app) : String(localized: "Autorisé", bundle: .app))
        .accessibilityAddTraits(isBanned ? .isSelected : [])
    }
}

/// La coche d'un genre exclu.
private struct BannedCheckGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.minY + rect.height * 0.88))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.12))
        return path
    }
}

/// Le gabarit d'une sous-page des réglages : le plafond avec son chevron,
/// la conséquence du réglage, puis le contrôle.
private struct SettingsSubpage<Content: View>: View {
    let title: String
    let note: String
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            Ink.ground.ignoresSafeArea()

            VStack(spacing: 0) {
                PlanHeader(title)

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(note)
                            .planFont(13)
                            .foregroundStyle(Ink.ink2)
                            .fixedSize(horizontal: false, vertical: true)

                        content
                    }
                    .padding(.horizontal, Metrics.margin)
                    .padding(.top, 20)
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}
