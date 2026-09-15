//
//  CineMatchSituationSheet.swift
//  Cinechill_iOS
//

import SwiftUI

/// La feuille du scénario de la soirée : avec qui, combien de temps, sur
/// quelles plateformes.
///
/// Chaque réponse s'applique **au tap**, comme dans les réglages : refermer la
/// feuille d'un geste garde ce qu'on a choisi. « C'est bon » ne fait que la
/// refermer. Les plateformes sont celles de la bibliothèque, pas une copie
/// propre à la séance : les cocher ici les coche partout.
struct CineMatchSituationSheet: View {
    let viewModel: CineMatchViewModel
    let onClose: () -> Void

    @EnvironmentObject private var libraryStore: LibraryStore
    @Environment(MediaCatalog.self) private var catalog

    /// La hauteur du contenu, pour que la feuille s'arrête juste sous son
    /// bouton au lieu de couvrir l'écran ou de le rogner.
    @State private var contentHeight: CGFloat = 480
    @State private var bottomInset: CGFloat = 0

    private var platformSelection: Binding<Set<String>> {
        Binding(
            get: { libraryStore.preferredPlatformIDs },
            set: { ids in
                libraryStore.setPreferredPlatforms(ids)
                apply { $0.platformIDs = ids.sorted() }
            }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Le scénario de la soirée", bundle: .app)
                    .planTitle(22)
                    .foregroundStyle(Ink.ink)
                    .accessibilityAddTraits(.isHeader)

                question(String(localized: "Avec qui comptes-tu regarder le film ?", bundle: .app))
                    .padding(.top, 18)

                FlowLayout(spacing: 6) {
                    ForEach(CineMatchCompany.allCases, id: \.self) { company in
                        PlanChip(
                            title: company.scenarioLabel,
                            isOn: viewModel.situation.company == company
                        ) {
                            Haptics.selection()
                            apply { $0.company = company }
                        }
                    }
                }
                .padding(.top, 9)

                question(String(localized: "Quelle durée pour le film ?", bundle: .app))
                    .padding(.top, 16)

                FlowLayout(spacing: 6) {
                    ForEach(CineMatchDuration.allCases, id: \.self) { duration in
                        PlanChip(
                            title: duration.scenarioLabel,
                            isOn: viewModel.situation.duration == duration
                        ) {
                            Haptics.selection()
                            apply { $0.duration = duration }
                        }
                    }
                }
                .padding(.top, 9)

                question(String(localized: "Tes plateformes", bundle: .app))
                    .padding(.top, 16)

                platforms
                    .padding(.top, 9)

                PlanButton(title: String(localized: "C'est bon", bundle: .app)) {
                    apply { $0.platformIDs = libraryStore.preferredPlatformIDs.sorted() }
                    onClose()
                }
                .padding(.top, 20)
            }
            .padding(.horizontal, Metrics.margin)
            .padding(.top, 26)
            .padding(.bottom, 16)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { height in
                contentHeight = height
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.safeAreaInsets.bottom
        } action: { inset in
            bottomInset = inset
        }
        .background(Ink.ground2.ignoresSafeArea())
        .presentationDetents([.height(contentHeight + bottomInset)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Ink.ground2)
        .task { await catalog.loadIfNeeded() }
    }

    private func question(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Ink.ink)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var platforms: some View {
        if catalog.platforms.isEmpty {
            HStack(spacing: 10) {
                CinechillSpinner(size: 18)
                Text("Chargement des plateformes…", bundle: .app)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Ink.ink2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
        } else {
            PlatformGrid(platforms: catalog.platforms, selection: platformSelection, columns: 6)
        }
    }

    /// Une retouche de la situation, envoyée entière au modèle : il ne connaît
    /// qu'un seul point d'entrée pour elle.
    private func apply(_ change: (inout CineMatchSituation) -> Void) {
        var situation = viewModel.situation
        change(&situation)
        guard situation != viewModel.situation else { return }
        viewModel.updateSituation(situation)
    }
}

// MARK: - Les libellés du scénario

// Propriétés calculées et non tables statiques : la langue peut changer en
// cours de route, et une chaîne résolue une fois ne suivrait pas.

extension CineMatchCompany {
    /// Le libellé de la puce, repris mot pour mot dans le bandeau de l'accueil.
    var scenarioLabel: String {
        switch self {
        case .alone: String(localized: "Seul", bundle: .app)
        case .duo: String(localized: "À plusieurs", bundle: .app)
        case .family: String(localized: "En famille", bundle: .app)
        }
    }
}

extension CineMatchDuration {
    /// Le libellé de la puce, repris mot pour mot dans le bandeau de l'accueil.
    var scenarioLabel: String {
        switch self {
        case .short: String(localized: "< 1h30", bundle: .app)
        case .medium: String(localized: "1h30 – 2h", bundle: .app)
        case .long: String(localized: "2h +", bundle: .app)
        case .any: String(localized: "Peu importe", bundle: .app)
        }
    }
}
