//
//  GalleryBandGridView.swift
//  Cinechill_iOS
//

import SwiftUI

/// Une bande ouverte en grille plein écran.
///
/// C'est le mode « je cherche un titre précis », que la vue en bandes ne
/// couvre pas : elle donne la forme de la collection, pas l'accès à un film.
struct GalleryBandGridView: View {
    let band: GalleryBand

    /// Trois colonnes, comme « Le Rayon » : sur un écran de balayage, le nombre
    /// de titres qu'on embrasse d'un coup d'œil *est* la fonction.
    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: Metrics.gutter),
        count: 3
    )

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(band.entries) { entry in
                    NavigationLink(destination: ItemDetailView(item: entry.mediaItem)) {
                        PosterCell(
                            posterPath: entry.posterPath,
                            title: entry.title
                        )
                    }
                    .buttonStyle(PressableScaleStyle(scale: 0.94))
                }
            }
            .padding(.horizontal, Metrics.margin)
            .padding(.top, 16)
            .padding(.bottom, 28)
        }
        .background(Ink.ground)
        .safeAreaInset(edge: .top) {
            PlanHeader(band.title) {
                PlanHeaderCount(value: "\(band.count)")
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}
