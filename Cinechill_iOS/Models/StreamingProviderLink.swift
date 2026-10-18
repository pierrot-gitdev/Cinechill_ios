//
//  StreamingProviderLink.swift
//  Cinechill_iOS
//

import Foundation

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
