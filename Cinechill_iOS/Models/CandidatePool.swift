//
//  CandidatePool.swift
//  Cinechill_iOS
//

import Foundation

/// Un jeu de valeurs indexé par axe, tel que le serveur l'envoie.
///
/// Les positions et les incertitudes voyagent dans cette même forme mais ne se
/// lisent pas pareil : une position absente vaut 0 (l'axe ne départage rien),
/// une incertitude absente vaut 1 (on ne sait pas) — jamais 0, qui voudrait dire
/// « parfaitement connu » et ferait exploser le score.
nonisolated struct AxisValues: Equatable, Hashable, Sendable, Codable {
    private var values: [String: Double]

    static let unknown = AxisValues(values: [:])

    private init(values: [String: Double]) {
        self.values = values
    }

    init(from decoder: Decoder) throws {
        values = try [String: Double](from: decoder)
    }

    func encode(to encoder: Encoder) throws {
        try values.encode(to: encoder)
    }

    /// La position sur un axe. Repli : 0.
    subscript(axis: Axis) -> Double {
        values[axis.rawValue] ?? 0
    }

    /// L'incertitude sur un axe. Repli : 1, et jamais en dessous d'un plancher
    /// strictement positif.
    func sigma(_ axis: Axis) -> Double {
        max(0.05, values[axis.rawValue] ?? 1)
    }

    var jsonPayload: [String: Double] { values }
}

/// Un candidat tel que renvoyé par `getCandidatePool` — les champs "bon marché" que TMDB
/// donne déjà sur ses endpoints de liste, plus la position que le serveur en a déduite
/// sur les huit axes.
///
/// Le client ne calcule jamais cette position lui-même : elle dépend de la distribution
/// du vivier entier, que seul le serveur a eue en main. Il la reçoit, s'en sert pour
/// classer localement entre deux questions, et la lui renvoie telle quelle.
nonisolated struct CandidateRow: Identifiable, Hashable, Sendable, Codable {
    let id: Int
    let title: String?
    let overview: String?
    let posterPath: String?
    let voteAverage: Double?
    let voteCount: Int?
    let popularity: Double?
    let genreIds: [Int]
    let releaseDate: String?
    let originCountry: [String]
    let axes: AxisValues
    let axisSigma: AxisValues

    enum CodingKeys: String, CodingKey {
        case id, title, overview
        case posterPath = "poster_path"
        case voteAverage = "vote_average"
        case voteCount = "vote_count"
        case popularity
        case genreIds = "genre_ids"
        case releaseDate = "release_date"
        case originCountry = "origin_country"
        case axes
        case axisSigma = "axis_sigma"
    }

    init(
        id: Int,
        title: String?,
        overview: String?,
        posterPath: String?,
        voteAverage: Double?,
        voteCount: Int?,
        popularity: Double?,
        genreIds: [Int],
        releaseDate: String?,
        originCountry: [String],
        axes: AxisValues = .unknown,
        axisSigma: AxisValues = .unknown
    ) {
        self.id = id
        self.title = title
        self.overview = overview
        self.posterPath = posterPath
        self.voteAverage = voteAverage
        self.voteCount = voteCount
        self.popularity = popularity
        self.genreIds = genreIds
        self.releaseDate = releaseDate
        self.originCountry = originCountry
        self.axes = axes
        self.axisSigma = axisSigma
    }

    /// Décodage explicite plutôt que synthétisé : les deux blocs d'axes doivent
    /// pouvoir manquer sans faire échouer toute la réponse, et retomber alors sur
    /// « position neutre, incertitude maximale » — ce qui neutralise le film dans
    /// le classement au lieu de le faire gagner par accident.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        overview = try container.decodeIfPresent(String.self, forKey: .overview)
        posterPath = try container.decodeIfPresent(String.self, forKey: .posterPath)
        voteAverage = try container.decodeIfPresent(Double.self, forKey: .voteAverage)
        voteCount = try container.decodeIfPresent(Int.self, forKey: .voteCount)
        popularity = try container.decodeIfPresent(Double.self, forKey: .popularity)
        genreIds = try container.decodeIfPresent([Int].self, forKey: .genreIds) ?? []
        releaseDate = try container.decodeIfPresent(String.self, forKey: .releaseDate)
        originCountry = try container.decodeIfPresent([String].self, forKey: .originCountry) ?? []
        axes = try container.decodeIfPresent(AxisValues.self, forKey: .axes) ?? .unknown
        axisSigma = try container.decodeIfPresent(AxisValues.self, forKey: .axisSigma) ?? .unknown
    }

    var posterURL: URL? {
        guard let posterPath, !posterPath.isEmpty else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w500\(posterPath)")
    }

    var releaseYear: Int? {
        guard let releaseDate, releaseDate.count >= 4 else { return nil }
        return Int(releaseDate.prefix(4))
    }

    /// Représentation JSON à renvoyer telle quelle vers `enrichCandidates`/`finalizeRecommendations`
    /// — le backend échange ce même schéma dans les deux sens plutôt que de le re-dériver.
    var jsonPayload: [String: Any] {
        [
            "id": id,
            "title": title as Any,
            "overview": overview as Any,
            "poster_path": posterPath as Any,
            "vote_average": voteAverage as Any,
            "vote_count": voteCount as Any,
            "popularity": popularity as Any,
            "genre_ids": genreIds,
            "release_date": releaseDate as Any,
            "origin_country": originCountry,
            "axes": axes.jsonPayload,
            "axis_sigma": axisSigma.jsonPayload,
        ]
    }
}

/// Un candidat enrichi par `enrichCandidates` — les champs qui n'existent que sur l'endpoint de
/// détail TMDB (un appel par film), disponibles seulement pour le sous-ensemble réduit envoyé en
/// phase B. Ses axes sont ceux du candidat grossier, resserrés par ce que le détail a appris.
nonisolated struct EnrichedCandidateRow: Identifiable, Hashable, Sendable, Codable {
    let base: CandidateRow
    let runtimeMinutes: Int?
    let belongsToCollection: Bool
    let castPopularities: [Double]
    let providerIDs: [Int]
    let trailerKey: String?
    let budget: Double?

    var id: Int { base.id }
    var axes: AxisValues { base.axes }
    var axisSigma: AxisValues { base.axisSigma }

    enum CodingKeys: String, CodingKey {
        case runtimeMinutes = "runtime_minutes"
        case belongsToCollection = "belongs_to_collection"
        case castPopularities = "cast_popularities"
        case providerIDs = "provider_ids"
        case trailerKey = "trailer_key"
        case budget
    }

    init(from decoder: Decoder) throws {
        base = try CandidateRow(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        runtimeMinutes = try container.decodeIfPresent(Int.self, forKey: .runtimeMinutes)
        belongsToCollection = try container.decodeIfPresent(Bool.self, forKey: .belongsToCollection) ?? false
        castPopularities = try container.decodeIfPresent([Double].self, forKey: .castPopularities) ?? []
        providerIDs = try container.decodeIfPresent([Int].self, forKey: .providerIDs) ?? []
        trailerKey = try container.decodeIfPresent(String.self, forKey: .trailerKey)
        budget = try container.decodeIfPresent(Double.self, forKey: .budget)
    }

    init(
        base: CandidateRow,
        runtimeMinutes: Int?,
        belongsToCollection: Bool,
        castPopularities: [Double],
        providerIDs: [Int],
        trailerKey: String?,
        budget: Double? = nil
    ) {
        self.base = base
        self.runtimeMinutes = runtimeMinutes
        self.belongsToCollection = belongsToCollection
        self.castPopularities = castPopularities
        self.providerIDs = providerIDs
        self.trailerKey = trailerKey
        self.budget = budget
    }

    func encode(to encoder: Encoder) throws {
        try base.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(runtimeMinutes, forKey: .runtimeMinutes)
        try container.encode(belongsToCollection, forKey: .belongsToCollection)
        try container.encode(castPopularities, forKey: .castPopularities)
        try container.encode(providerIDs, forKey: .providerIDs)
        try container.encodeIfPresent(trailerKey, forKey: .trailerKey)
        try container.encodeIfPresent(budget, forKey: .budget)
    }

    var jsonPayload: [String: Any] {
        var payload = base.jsonPayload
        payload["runtime_minutes"] = runtimeMinutes as Any
        payload["belongs_to_collection"] = belongsToCollection
        payload["cast_popularities"] = castPopularities
        payload["provider_ids"] = providerIDs
        payload["trailer_key"] = trailerKey as Any
        payload["budget"] = budget as Any
        return payload
    }
}
