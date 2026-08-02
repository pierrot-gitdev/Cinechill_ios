//
//  RecommendationResult.swift
//  Cinechill_iOS
//

import Foundation

/// Un des trois films renvoyés par CinéMatch, avec son score de correspondance et les raisons
/// affichées à l'utilisateur ("Comédie", "< 2h", "Disponible sur Netflix"…).
nonisolated struct RecommendationResult: Identifiable, Hashable, Sendable {
    let item: MediaItem
    let matchScore: Int
    let reasons: [String]
    let trailerKey: String?
    let providerIDs: [Int]

    var id: String { item.id }

    var trailerURL: URL? {
        guard let trailerKey, !trailerKey.isEmpty else { return nil }
        return URL(string: "https://www.youtube.com/watch?v=\(trailerKey)")
    }

    var trailerAppURL: URL? {
        guard let trailerKey, !trailerKey.isEmpty else { return nil }
        return URL(string: "youtube://www.youtube.com/watch?v=\(trailerKey)")
    }

    /// URLs de l'app native à tenter, dans l'ordre, pour la première plateforme disponible.
    /// Retombe sur le web (`watchWebURL`) si aucune de ces apps n'est installée.
    var watchAppURLCandidates: [URL] {
        providerIDs.flatMap { StreamingProviderLink.appURLs(forProviderID: $0, title: item.title) }
    }

    var watchWebURL: URL? {
        providerIDs.lazy.compactMap(TMDBDetailWatchProviderItem.webURL(forProviderID:)).first
    }
}

/// Schémas d'URL des apps de streaming — permet d'ouvrir l'app native plutôt que le site web
/// quand elle est installée. Couverture volontairement limitée aux schémas documentés avec une
/// confiance raisonnable ; les autres retombent simplement sur le web, sans casser l'expérience.
///
/// Aucune de ces apps n'accepte un lien direct vers une fiche film sans l'identifiant interne du
/// catalogue de la plateforme (ex. l'ID Netflix d'un titre) — une donnée que TMDB n'expose pas et
/// qu'on n'a nulle part ailleurs. Seul Netflix documente un lien de recherche pré-remplie
/// (`nflx://…/search?q=`), utilisé ici pour se rapprocher au maximum du film exact ; les autres
/// plateformes ouvrent simplement l'app, sans présélection.
nonisolated enum StreamingProviderLink {
    static func appURLs(forProviderID providerID: Int, title: String) -> [URL] {
        let encodedTitle = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let schemes: [String]
        switch providerID {
        case 8: schemes = ["nflx://www.netflix.com/search?q=\(encodedTitle)", "nflx://"] // Netflix
        case 119, 9: schemes = ["aiv://"] // Prime Video
        case 337: schemes = ["disneyplus://"] // Disney+
        case 1899, 384: schemes = ["max://", "hbomax://"] // Max (ex-HBO Max)
        default: schemes = []
        }
        return schemes.compactMap(URL.init(string:))
    }
}
