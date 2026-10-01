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
                // Les tuiles de la frise, pas ses entrées : trois saisons de la
                // même série restent une affiche, ici comme dans la bande.
                ForEach(band.tiles) { tile in
                    if let destination = tile.destination {
                        NavigationLink(destination: ItemDetailView(item: destination)) {
                            PosterCell(
                                posterPath: tile.posterPath,
                                title: tile.title
                            )
                            .overlay(alignment: .topLeading) {
                                if let plate = tile.plate {
                                    PosterPlate(text: plate)
                                }
                            }
                        }
                        .buttonStyle(PressableScaleStyle(scale: 0.94))
                    }
                }
            }
            .padding(.horizontal, Metrics.margin)
            .padding(.top, 16)
            .padding(.bottom, 28)
        }
        .background(Ink.ground)
        .safeAreaInset(edge: .top) {
            PlanHeader(band.title) {
                PlanHeaderCount(value: band.count.formatted())
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}
