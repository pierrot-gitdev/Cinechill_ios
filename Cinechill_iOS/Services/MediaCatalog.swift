//
//  MediaCatalog.swift
//  Cinechill_iOS
//

import Foundation

/// Répertoire partagé des genres et des plateformes.
///
/// La galerie a besoin des noms de genres, la watchlist des logos de
/// plateformes, et l'accueil chargeait déjà les deux de son côté. Un seul
/// point d'entrée évite d'appeler `getmoviegenres` et `getmovieproviders`
/// une fois par écran — les réponses sont de toute façon mises en cache sur
/// disque par `BackendPopularClient`.
@Observable
@MainActor
final class MediaCatalog {
    private(set) var genreNames: [Int: String] = [:]
    private(set) var platforms: [StreamingPlatform] = []

    private let client: any HomeMetadataFetching
    private var hasLoaded = false

    /// Le client par défaut est construit dans le corps de l'initialiseur, et
    /// non en valeur par défaut de paramètre : ces expressions sont
    /// type-vérifiées hors de l'isolation de la classe, ce qui interdit d'y
    /// appeler un initialiseur isolé au main actor.
    init() {
        self.client = BackendPopularClient()
    }

    init(client: any HomeMetadataFetching) {
        self.client = client
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true

        if let genres = try? await client.movieGenres() {
            genreNames = Dictionary(
                genres.map { ($0.id, $0.name) },
                uniquingKeysWith: { first, _ in first }
            )
        }
        if let providers = try? await client.movieProviders() {
            platforms = StreamingPlatform.curated(from: providers)
        }
    }

    func name(forGenre id: Int) -> String? {
        genreNames[id]
    }

    func platform(forProvider id: Int) -> StreamingPlatform? {
        platforms.first { $0.providerID == id }
    }
}
