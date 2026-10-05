//
//  SwipeCard.swift
//  Cinechill_iOS
//

import Foundation

/// Une carte du deck de swipe.
///
/// Superset de `MediaItem` sur un point : `source`, qui dit quelle stratégie de
/// recommandation a ramené le film.
///
/// `voteCount` était le second, du temps où `MediaItem` ne le portait pas. Il y
/// vit maintenant — le mur de l'entrée de CinéMatch s'en sert pour ne retenir
/// que des films que beaucoup de gens ont vus — et reste ici parce que c'est le
/// meilleur proxy de « combien de gens ont vraiment vu ce film », donc ce qui
/// permet au backend d'apprendre le niveau de « niche » de l'utilisateur au fil
/// des swipes.
nonisolated struct SwipeCard: Identifiable, Hashable, Sendable {
    let tmdbId: Int
    let title: String
    let posterPath: String?
    let overview: String?
    let voteAverage: Double?
    let voteCount: Int?
    let genreIds: [Int]
    let releaseDate: String?
    let source: String?
    /// La saga du film, quand le serveur la connaît. C'est elle qui déclenche
    /// la feuille de saga après un « vu » : voir `SagaSheet`.
    let collectionID: Int?
    /// Le nombre d'opus de cette saga. En dessous de deux, il n'y a rien à
    /// proposer, et la feuille ne s'ouvre pas.
    let collectionCount: Int?
    /// Film ou série. Le deck demande « tu connais ? » sur une série entière ;
    /// ce qu'il range, lui, est toujours une saison.
    let mediaType: MediaType
    /// Les saisons sorties d'une série : ce que la carte écrit à la place du
    /// mot « série », et ce que la feuille propose de ranger d'un tap.
    let seasonCount: Int?
    /// La saison que range une décision. `nil` sur une carte du deck, qui
    /// range toujours la première ; renseignée par la feuille des saisons.
    let season: Int?

    /// Explicite, et non synthétisé : les deux champs de saga sont arrivés
    /// après les autres, et leur valeur par défaut évite de reprendre les cinq
    /// endroits qui fabriquent une carte sans jamais connaître de saga.
    init(
        tmdbId: Int,
        title: String,
        posterPath: String?,
        overview: String?,
        voteAverage: Double?,
        voteCount: Int?,
        genreIds: [Int],
        releaseDate: String?,
        source: String?,
        collectionID: Int? = nil,
        collectionCount: Int? = nil,
        mediaType: MediaType = .movie,
        seasonCount: Int? = nil,
        season: Int? = nil
    ) {
        self.tmdbId = tmdbId
        self.title = title
        self.posterPath = posterPath
        self.overview = overview
        self.voteAverage = voteAverage
        self.voteCount = voteCount
        self.genreIds = genreIds
        self.releaseDate = releaseDate
        self.source = source
        self.collectionID = collectionID
        self.collectionCount = collectionCount
        self.mediaType = mediaType
        self.seasonCount = seasonCount
        self.season = season
    }

    /// L'identité de la carte dans le deck : `movie-603`, `tv-1399`. Le format
    /// en fait partie, parce que les identifiants TMDB des films et des séries
    /// se recoupent — la série 1399 n'est pas le film 1399.
    var id: String { "\(mediaType.rawValue)-\(tmdbId)" }

    var isSeries: Bool { mediaType == .tv }

    /// Y a-t-il une saga à proposer derrière ce film ?
    var hasSagaToOffer: Bool {
        collectionID != nil && (collectionCount ?? 0) >= 2
    }

    /// Y a-t-il d'autres saisons à proposer derrière celle qu'on vient de ranger ?
    var hasSeasonsToOffer: Bool {
        isSeries && (seasonCount ?? 0) >= 2
    }

    /// Ce que range une décision « vu » ou « à voir » : le film, ou une saison
    /// — la première, sauf si la feuille des saisons en désigne une autre.
    var mediaItem: MediaItem {
        MediaItem(
            tmdbId: tmdbId,
            mediaType: mediaType,
            title: title,
            posterPath: posterPath,
            overview: overview,
            voteAverage: voteAverage,
            voteCount: voteCount,
            genreIds: genreIds,
            releaseDate: releaseDate,
            season: isSeries ? (season ?? 1) : nil,
            seasonCount: seasonCount
        )
    }

    var posterURL: URL? {
        guard let posterPath, !posterPath.isEmpty else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w500\(posterPath)")
    }

    var displayYear: String {
        guard let releaseDate, releaseDate.count >= 4 else { return "—" }
        return String(releaseDate.prefix(4))
    }

    /// TMDB rend 0 pour un film que personne n'a noté : c'est une absence,
    /// pas une note, et elle ne s'affiche pas en « 0.0 ».
    var hasRating: Bool { (voteAverage ?? 0) > 0 && (voteCount ?? 1) > 0 }

    /// Formatée dans la langue de l'app : « 8,4 » en français, « 8.4 » en
    /// anglais. `String(format:)` écrivait toujours un point.
    var voteAverageText: String {
        guard hasRating, let voteAverage else { return "—" }
        return voteAverage.formatted(
            .number.precision(.fractionLength(1)).locale(AppLanguage.current.locale)
        )
    }

    /// Payload envoyé à `recordSwipes` — mêmes clés que `setMediaStatus`, plus
    /// `voteCount` que seul le swipe sait renseigner.
    ///
    /// Pour une série, la décision change l'objet : « vu » et « à voir » rangent
    /// une saison (`tv-1399-s1`), « pas vue » écarte la série entière
    /// (`tv-1399`) — le deck n'a jamais demandé une saison.
    func jsonPayload(for decision: SwipeDecision) -> [String: Any] {
        [
            "id": isSeries && decision == .skipped ? id : mediaItem.id,
            "tmdbId": tmdbId,
            "mediaType": mediaType.rawValue,
            "title": title,
            "posterPath": posterPath as Any,
            "overview": overview as Any,
            "voteAverage": voteAverage as Any,
            "voteCount": voteCount as Any,
            "genreIds": genreIds,
            "releaseDate": releaseDate as Any,
        ]
    }
}

/// Le verdict porté sur une carte. `skipped` n'est pas un rejet de goût : il dit
/// « je ne l'ai pas vu », ce qui met le film en cooldown et apprend au backend
/// où l'utilisateur n'a pas de vécu.
nonisolated enum SwipeDecision: String, Sendable, Hashable {
    case seen
    case skipped
    case watchlist
}

/// Une décision en attente d'envoi, gardée telle quelle pour pouvoir être
/// rejouée si le réseau échoue.
nonisolated struct PendingSwipe: Sendable, Hashable {
    let card: SwipeCard
    let decision: SwipeDecision
    /// Le double tap sur l'affiche : vu ET adoré. Un modificateur de
    /// `seen`, jamais un quatrième verbe — le serveur garde sa liste fermée.
    let loved: Bool

    init(card: SwipeCard, decision: SwipeDecision, loved: Bool = false) {
        self.card = card
        self.decision = decision
        self.loved = loved && decision == .seen
    }

    var jsonPayload: [String: Any] {
        [
            "decision": decision.rawValue,
            "loved": loved,
            "item": card.jsonPayload(for: decision),
        ]
    }
}
