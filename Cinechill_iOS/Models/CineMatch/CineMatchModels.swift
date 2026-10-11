//
//  CineMatchModels.swift
//  Cinechill_iOS
//

import Foundation

// Les modèles de CinéMatch v2. Tout est `nonisolated` : ils traversent le
// client réseau, qui ne tourne pas sur le main actor (voir la note sur
// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` dans `QuestionnaireAnswer.swift`).

/// Avec qui on regarde. `family` fait écarter au serveur l'horreur et les
/// films interdits aux moins de 16 ans.
nonisolated enum CineMatchCompany: String, CaseIterable, Codable, Sendable {
    case alone, duo, family
}

/// La durée voulue. short < 90 min, medium 90 à 120, long > 120, any sans
/// filtre ; le serveur peut l'élargir par paliers s'il manque de films.
nonisolated enum CineMatchDuration: String, CaseIterable, Codable, Sendable {
    case short, medium, long, any
}

/// Le scénario de la soirée : ce qui vaut pour toute la recherche, réglé
/// depuis « Ce soir ».
nonisolated struct CineMatchSituation: Equatable, Codable, Sendable {
    var company: CineMatchCompany = .alone
    var duration: CineMatchDuration = .any
    /// Les ids provider TMDB en chaîne (« 8 », « 119 »…). Vide : pas de filtre.
    var platformIDs: [String] = []
    /// Séries seulement. Le serveur l'ignore pour un film.
    var engagement: CineMatchEngagement = .any
}

/// Le temps total qu'on accepte de donner à une série. Une série ne se
/// choisit pas pour une soirée, on choisit dans quoi s'engager. Le serveur en
/// fait un filtre souple, jamais un mur.
///
/// C'était la seconde question du parcours ; elle vit depuis le lot 1 dans
/// « Ce soir », à côté de la durée d'un épisode : elle décrit la soirée, pas
/// l'envie.
nonisolated enum CineMatchEngagement: String, CaseIterable, Codable, Sendable {
    case mini, season, long, any
}

/// Les dix styles de l'écran de départ, dans l'ordre du serveur
/// (`fiche.STYLES`). Un film appartient à chaque style dont il porte un
/// genre : Heat est à la fois un thriller et un film d'action.
///
/// Le style ne retire aucun candidat des cinq : il choisit seulement les six
/// films qu'on propose comme point de départ.
nonisolated enum CineMatchStyle: String, CaseIterable, Hashable, Sendable {
    case thriller, action, scifi, comedy, drama, romance, horror, animation, history, documentary
}

/// Une tuile de l'écran de départ : un style, le nombre de films de la
/// galerie qui en sont, et trois de leurs affiches.
nonisolated struct CineMatchStyleTile: Identifiable, Hashable, Sendable {
    let style: CineMatchStyle
    let count: Int
    let films: [CineMatchGalleryFilm]

    var id: CineMatchStyle { style }
}

/// Six films d'un style, proposés comme point de départ.
nonisolated struct CineMatchStarterPage: Equatable, Sendable {
    let style: CineMatchStyle
    /// La page rendue : le serveur revient à la première une fois le style
    /// parcouru.
    let page: Int
    let films: [CineMatchGalleryFilm]
    /// Faux quand le style tient sur une page : « Pas ceux-là » ramènerait
    /// les mêmes.
    let hasMore: Bool
}

/// Où en est l'histoire d'une série proposée. La carte l'écrit toujours :
/// commencer une série annulée, c'est savoir qu'elle n'aura pas de fin.
nonisolated enum CineMatchSeriesStatus: String, Sendable {
    case ended, returning, canceled
}

/// Un film de la galerie, montré en affiche : dans les comparaisons de la
/// Porte, sur les tuiles et parmi les films de départ.
nonisolated struct CineMatchGalleryFilm: Identifiable, Hashable, Sendable {
    let id: Int
    let title: String
    let posterPath: String?
    let releaseDate: String?
    let genreIDs: [Int]

    var posterURL: URL? {
        guard let posterPath, !posterPath.isEmpty else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w500\(posterPath)")
    }
}

/// Une comparaison de la Porte telle que le serveur la prépare : quatre
/// affiches pour la première question, quatre autres pour la seconde.
nonisolated struct CineMatchComparisonRound: Equatable, Sendable {
    /// Le nombre de comparaisons de la séance (0 à 4). Ignoré par la Porte.
    let total: Int
    let round: Int
    /// Vide quand `round` dépasse `total`.
    let films: [CineMatchGalleryFilm]
    /// Clé : l'id d'un des quatre films. Absent quand la galerie est épuisée.
    /// Ne sert plus que quand `excludeFilms` est vide.
    let replacements: [Int: CineMatchGalleryFilm]
    /// Les films de la seconde question, tous différents de `films`. Vide
    /// quand la galerie n'en a pas assez, ou face à un serveur plus ancien.
    let excludeFilms: [CineMatchGalleryFilm]
}

/// Une comparaison jouée. `pick` garde un film et en écarte un autre ;
/// `none` dit qu'aucune des affiches affichées ne tentait.
nonisolated enum CineMatchComparison: Equatable, Sendable {
    case pick(keptID: Int, excludedID: Int, latencyMs: Int)
    case none(shownIDs: [Int])
}

/// Un des cinq films proposés, ou la proposition du jour. Une série y entre
/// aussi : `item` en est alors le dossier, et la durée celle d'un épisode.
nonisolated struct CineMatchFilm: Identifiable, Hashable, Sendable {
    let item: MediaItem
    /// La durée du film, ou celle d'un épisode.
    let runtimeMinutes: Int?
    let providerIDs: [Int]
    let trailerKey: String?
    /// Séries seulement : épisodes des saisons sorties.
    var episodeCount: Int? = nil
    /// Séries seulement.
    var status: CineMatchSeriesStatus? = nil

    var id: Int { item.tmdbId }

    var isSeries: Bool { item.mediaType == .tv }

    /// La saison par laquelle on commence une série proposée : la première,
    /// toujours. CinéMatch ne propose jamais de reprendre en route.
    var firstSeason: MediaItem {
        MediaItem(
            tmdbId: item.tmdbId,
            mediaType: .tv,
            title: item.title,
            posterPath: item.posterPath,
            overview: item.overview,
            voteAverage: item.voteAverage,
            voteCount: item.voteCount,
            genreIds: item.genreIds,
            releaseDate: item.releaseDate,
            season: 1,
            seasonCount: item.seasonCount
        )
    }

    var trailerURL: URL? {
        guard let trailerKey, !trailerKey.isEmpty else { return nil }
        return URL(string: "https://www.youtube.com/watch?v=\(trailerKey)")
    }

    var trailerAppURL: URL? {
        guard let trailerKey, !trailerKey.isEmpty else { return nil }
        return URL(string: "youtube://www.youtube.com/watch?v=\(trailerKey)")
    }

    /// Les URLs d'app native à tenter, dans l'ordre. Les plateformes de la
    /// personne passent d'abord : ouvrir Netflix pour un film qui est aussi sur
    /// Prime Video, alors qu'elle n'a que Prime, l'enverrait vers un mur.
    func watchAppURLCandidates(preferring platformIDs: [String]) -> [URL] {
        orderedProviderIDs(preferring: platformIDs).flatMap {
            StreamingProviderLink.appURLs(forProviderID: $0, title: item.title)
        }
    }

    func watchWebURL(preferring platformIDs: [String]) -> URL? {
        orderedProviderIDs(preferring: platformIDs).lazy
            .compactMap(TMDBDetailWatchProviderItem.webURL(forProviderID:))
            .first
    }

    /// La plateforme à afficher : une des siennes si le film y est, sinon la
    /// première où il est.
    func providerID(preferring platformIDs: [String]) -> Int? {
        orderedProviderIDs(preferring: platformIDs).first
    }

    /// Ordre stable : celles de la personne d'abord, chacune gardant sa place
    /// relative dans la réponse du serveur.
    private func orderedProviderIDs(preferring platformIDs: [String]) -> [Int] {
        let preferred = Set(platformIDs.compactMap { Int($0) })
        let mine = providerIDs.filter { preferred.contains($0) }
        let others = providerIDs.filter { !preferred.contains($0) }
        return mine + others
    }
}

/// Ce que le serveur a dû relâcher pour trouver assez de films, pour que
/// l'app le dise.
nonisolated struct CineMatchWidening: Equatable, Sendable {
    let duration: Bool
    let platforms: Bool
}

nonisolated struct CineMatchFiveResponse: Equatable, Sendable {
    let films: [CineMatchFilm]
    /// `nil` : rien n'a été élargi.
    let widening: CineMatchWidening?
    /// La séance écrite côté serveur : un remplacement s'y raccroche.
    var sessionID: String? = nil
}

/// Remplacer les films déjà vus ou écartés d'une proposition, en un seul
/// calcul.
///
/// On peut en marquer plusieurs des cinq : chacun se marque d'abord, sans
/// rien recalculer, et le calcul part une fois, pour tous. Les films gardés
/// restent à leur place ; le serveur ne renvoie que les remplaçants, un par
/// film marqué.
nonisolated struct CineMatchReplacement: Equatable, Sendable {
    let sessionID: String?
    /// Les films restés dans la proposition : ils ne doivent pas revenir.
    let keepIDs: [Int]
    /// Les films déjà vus, à remplacer.
    let seenIDs: [Int]
    /// Les films écartés (« Pas celui-là »), à remplacer.
    var refusedIDs: [Int] = []
}

nonisolated enum CineMatchExposureKind: String, Sendable {
    case five, daily, poster
}
