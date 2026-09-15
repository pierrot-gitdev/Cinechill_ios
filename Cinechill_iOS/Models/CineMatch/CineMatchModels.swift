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

/// Le scénario de la soirée : ce qui ne change pas d'une question à l'autre.
nonisolated struct CineMatchSituation: Equatable, Codable, Sendable {
    var company: CineMatchCompany = .alone
    var duration: CineMatchDuration = .any
    /// Les ids provider TMDB en chaîne (« 8 », « 119 »…). Vide : pas de filtre.
    var platformIDs: [String] = []
}

/// La question 1. `everyone` n'a de sens qu'à plusieurs : le serveur l'ignore
/// pour quelqu'un seul, et le ViewModel ne la propose pas.
nonisolated enum CineMatchWant: String, CaseIterable, Sendable {
    case light, soft, suspense, think, feelgood, everyone
}

/// La question 2. Elle ne règle que l'exigence et la part de découverte.
nonisolated enum CineMatchEnergy: String, CaseIterable, Sendable {
    case low, high
}

/// Un film de la galerie, montré en affiche pendant les comparaisons.
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

/// Une comparaison telle que le serveur la prépare : quatre affiches, et pour
/// chacune le film qui prendra sa place si elle est gardée.
nonisolated struct CineMatchComparisonRound: Equatable, Sendable {
    /// Le nombre de comparaisons de la séance (0 à 4). Ignoré par la Porte.
    let total: Int
    let round: Int
    /// Vide quand `round` dépasse `total`.
    let films: [CineMatchGalleryFilm]
    /// Clé : l'id d'un des quatre films. Absent quand la galerie est épuisée.
    let replacements: [Int: CineMatchGalleryFilm]
}

/// Une comparaison jouée. `pick` garde un film et en écarte un autre ;
/// `none` dit qu'aucune des affiches affichées ne tentait.
nonisolated enum CineMatchComparison: Equatable, Sendable {
    case pick(keptID: Int, excludedID: Int, latencyMs: Int)
    case none(shownIDs: [Int])
}

/// Un des cinq films proposés, ou la proposition du jour.
nonisolated struct CineMatchFilm: Identifiable, Hashable, Sendable {
    let item: MediaItem
    let runtimeMinutes: Int?
    let providerIDs: [Int]
    let trailerKey: String?

    var id: Int { item.tmdbId }

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
}

nonisolated enum CineMatchExposureKind: String, Sendable {
    case five, daily, poster
}
