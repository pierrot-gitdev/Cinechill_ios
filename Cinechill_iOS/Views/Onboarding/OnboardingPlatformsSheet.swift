//
//  OnboardingPlatformsSheet.swift
//  Cinechill_iOS
//

import SwiftUI

/// Le préambule de la prise en main : les plateformes, demandées dès la création
/// du compte.
///
/// C'est la seule question posée avant la visite, parce que c'est la seule dont
/// tout le reste dépend : l'accueil, CinéMatch et la watchlist filtrent sur ce
/// réglage. Sans lui, la première proposition peut tomber sur un film qu'on ne
/// peut pas regarder.
///
/// La grille est celle des réglages (`PlatformGrid`) et elle enregistre **à
/// chaque toucher**, comme partout ailleurs. On ne ferme pas la feuille d'un
/// glissement : « Continuer » demande au moins une plateforme, et « Je n'ai
/// aucune plateforme » laisse passer ceux qui n'en ont pas, sans les bloquer.
struct OnboardingPlatformsSheet: View {
    let onContinue: () -> Void

    @EnvironmentObject private var libraryStore: LibraryStore
    @Environment(MediaCatalog.self) private var catalog

    private var selection: Binding<Set<String>> {
        Binding(
            get: { libraryStore.preferredPlatformIDs },
            set: { libraryStore.setPreferredPlatforms($0) }
        )
    }

    private var hasSelection: Bool { !libraryStore.preferredPlatformIDs.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Quelles plateformes as-tu ?", bundle: .app)
                        .planTitle(26)
                        .foregroundStyle(Ink.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)

                    Text("Coche celles que tu as : on ne te proposera que des films disponibles dessus.", bundle: .app)
                        .font(.system(size: 13.5))
                        .foregroundStyle(Ink.ink2)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10)

                    Group {
                        if catalog.platforms.isEmpty {
                            HStack(spacing: 10) {
                                CinechillSpinner(size: 18)
                                Text("Chargement des plateformes…", bundle: .app)
                                    .font(.system(size: 13))
                                    .foregroundStyle(Ink.ink2)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            PlatformGrid(platforms: catalog.platforms, selection: selection)
                        }
                    }
                    .padding(.top, 24)
                }
                .padding(.horizontal, Metrics.margin)
                .padding(.top, 32)
                .padding(.bottom, 24)
            }

            VStack(spacing: 4) {
                PlanEdge()
                    .padding(.bottom, 12)

                PlanButton(
                    title: String(localized: "Continuer", bundle: .app),
                    isEnabled: hasSelection,
                    height: Metrics.control,
                    action: onContinue
                )

                // Toujours à sa place, éteint dès qu'une plateforme est cochée :
                // le bas de la feuille ne bouge pas pendant qu'on choisit.
                Button {
                    libraryStore.setPreferredPlatforms([])
                    onContinue()
                } label: {
                    Text("Je n'ai aucune plateforme", bundle: .app)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Ink.ink2)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(hasSelection ? 0 : 1)
                .disabled(hasSelection)
                .accessibilityHidden(hasSelection)
            }
            .padding(.horizontal, Metrics.margin)
            .padding(.bottom, 8)
            .animation(Metrics.shift, value: hasSelection)
        }
        .background(Ink.ground.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationBackground(Ink.ground)
        .interactiveDismissDisabled()
        .task { await catalog.loadIfNeeded() }
    }
}
