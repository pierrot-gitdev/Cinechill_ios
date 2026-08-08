//
//  PlatformPicker.swift
//  Cinechill_iOS
//

import SwiftUI

/// Le sélecteur d'abonnements — **un seul, pour toute l'application**.
///
/// Il en existait deux : la grille des réglages et `PlatformFilterSheet`, ouverte
/// depuis l'accueil. Deux dessins, deux jeux de couleurs, deux comportements
/// (l'un enregistrait à chaque tap, l'autre demandait un bouton « Enregistrer »)
/// — pour un seul et même réglage. La feuille a été supprimée ; ce composant est
/// ce qui reste, et il est employé aux trois endroits qui en ont besoin.
///
/// La sélection ne se colore pas, elle **s'allume** : pleine saturation, filet
/// d'encre, point de lumière. Non retenue : en retrait, désaturée. C'est le même
/// couple que sur la fiche film pour le même objet, et il reste lisible en
/// niveaux de gris.
struct PlatformGrid: View {
    let platforms: [StreamingPlatform]
    @Binding var selection: Set<String>
    var columns: Int = 5

    private var layout: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 9), count: columns)
    }

    var body: some View {
        LazyVGrid(columns: layout, spacing: 9) {
            ForEach(platforms) { platform in
                cell(platform)
            }
        }
    }

    private func cell(_ platform: StreamingPlatform) -> some View {
        let isOn = selection.contains(platform.id)
        return Button {
            Haptics.selection()
            if isOn { selection.remove(platform.id) } else { selection.insert(platform.id) }
        } label: {
            Group {
                if let url = platform.logoURL {
                    PosterImageView(url: url)
                } else {
                    Text(platform.shortLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Ink.ink2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(hex: 0x151B23))
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                    .strokeBorder(isOn ? Ink.ink : Ink.rule, lineWidth: 1)
            )
            .opacity(isOn ? 1 : 0.35)
            .saturation(isOn ? 1 : 0.2)
            .overlay(alignment: .topTrailing) {
                if isOn {
                    PlanLight().padding(4)
                }
            }
        }
        .buttonStyle(PressableScaleStyle(scale: 0.94))
        .accessibilityLabel(platform.name)
        .accessibilityValue(isOn ? "Abonné" : "Pas abonné")
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}

/// La grille, présentée en feuille depuis un écran de contenu.
///
/// Elle enregistre **à chaque tap**, comme dans les réglages : l'ancienne feuille
/// travaillait sur un brouillon et demandait un bouton « Enregistrer », si bien
/// que le même geste produisait deux comportements différents selon l'endroit
/// d'où on l'avait lancé.
struct PlatformPickerSheet: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    @Environment(MediaCatalog.self) private var catalog

    private var selection: Binding<Set<String>> {
        Binding(
            get: { libraryStore.preferredPlatformIDs },
            set: { libraryStore.setPreferredPlatforms($0) }
        )
    }

    var body: some View {
        ZStack {
            Ink.ground.ignoresSafeArea()

            VStack(spacing: 0) {
                PlanHeader("Mes abonnements", leading: .close) {
                    if !libraryStore.preferredPlatformIDs.isEmpty {
                        Button {
                            Haptics.selection()
                            libraryStore.setPreferredPlatforms([])
                        } label: {
                            Text("Tout décocher")
                                .planLabel()
                                .foregroundStyle(Ink.ink3)
                                .contentShape(Rectangle().inset(by: -10))
                        }
                        .buttonStyle(.plain)
                    }
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Ce qui n'est pas chez vous ne vous sera pas proposé. Ne rien cocher, c'est ne pas filtrer.")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Ink.ink3)
                            .fixedSize(horizontal: false, vertical: true)

                        if catalog.platforms.isEmpty {
                            HStack(spacing: 10) {
                                CinechillSpinner(size: 18)
                                Text("Chargement des plateformes…")
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(Ink.ink3)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 20)
                        } else {
                            PlatformGrid(platforms: catalog.platforms, selection: selection)
                        }
                    }
                    .padding(.horizontal, Metrics.margin)
                    .padding(.top, 20)
                    .padding(.bottom, 28)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .task { await catalog.loadIfNeeded() }
    }
}
