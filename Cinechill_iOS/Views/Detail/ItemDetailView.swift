//
//  ItemDetailView.swift
//  Cinechill_iOS
//

import SwiftUI

/// Le point d'arrivée de tous les parcours, qui ouvre la bonne fiche.
///
/// Accueil, deck, galerie, watchlist, notification, profil d'un ami : chacun
/// ouvre `ItemDetailView` sans savoir ce qu'il ouvre. C'est ici, et seulement
/// ici, que l'on distingue trois objets :
///
/// - **un film**, et sa fiche ;
/// - **une saison**, dont la fiche est celle d'un film, au mot près — c'est elle
///   qui se range, en galerie comme en watchlist ;
/// - **une série**, qui ne se range pas : c'est un dossier de saisons, au même
///   titre qu'une saga est un dossier de films.
struct ItemDetailView: View {
    let item: MediaItem
    /// La fiche d'une saison ouverte depuis le dossier de sa série n'a pas à
    /// proposer d'y retourner : le bouton retour y mène déjà.
    var showsSeriesLink = true

    var body: some View {
        switch item.mediaType {
        case .movie:
            FilmDetailView(item: item)
        case .tv:
            if let season = item.season {
                SeasonDetailView(item: item, season: season, showsSeriesLink: showsSeriesLink)
            } else {
                SeriesDetailView(item: item)
            }
        }
    }
}
