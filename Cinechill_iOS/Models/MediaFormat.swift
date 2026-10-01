//
//  MediaFormat.swift
//  Cinechill_iOS
//

import Foundation

/// Films ou séries : ce sur quoi les deux écrans qui apprennent le goût
/// travaillent en ce moment.
///
/// **Deux écrans, pas cinq.** Découvrir et CinéMatch bâtissent deux profils
/// distincts — on ne compare pas une série à un film, et une Porte des séries
/// ne s'ouvre pas avec des films — et mêler les deux brouillerait chacun.
/// L'accueil, la galerie et la watchlist rangent une bibliothèque : ils restent
/// mêlés, sans interrupteur.
///
/// **Un seul réglage pour les deux écrans.** Passer Découvrir sur Séries passe
/// CinéMatch sur Séries : on est « en séries » ou « en films », pas l'un ici et
/// l'autre là. Le choix est retenu d'une ouverture à l'autre.
nonisolated enum MediaFormat: String, CaseIterable, Sendable {
    case film
    case series

    /// La clé `@AppStorage` que partagent Découvrir et CinéMatch.
    static let storageKey = "learning.format"

    var label: String {
        switch self {
        case .film: String(localized: "Films", bundle: .app)
        case .series: String(localized: "Séries", bundle: .app)
        }
    }

    /// Le type de média qu'on range dans ce format.
    var mediaType: MediaType {
        switch self {
        case .film: .movie
        case .series: .tv
        }
    }
}
