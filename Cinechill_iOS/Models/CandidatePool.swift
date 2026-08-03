//
//  CandidatePool.swift
//  Cinechill_iOS
//

import Foundation

/// Un candidat tel que renvoyé par `getCandidatePool` — les champs "bon marché" que TMDB
/// donne déjà sur ses endpoints de liste, sans appel de détail par film. C'est sur ces champs
/// que tourne la phase grossière du moteur de sélection de questions (voir `QuestionEngine`).
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

    enum CodingKeys: String, CodingKey {
        case id, title, overview
        case posterPath = "poster_path"
        case voteAverage = "vote_average"
        case voteCount = "vote_count"
        case popularity
        case genreIds = "genre_ids"
        case releaseDate = "release_date"
        case originCountry = "origin_country"
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
        ]
    }
}

/// Un candidat enrichi par `enrichCandidates` — les champs qui n'existent que sur l'endpoint de
/// détail TMDB (un appel par film), disponibles seulement pour le sous-ensemble réduit envoyé en
/// phase B. Alimente la phase fine du moteur de sélection.
nonisolated struct EnrichedCandidateRow: Identifiable, Hashable, Sendable, Codable {
    let base: CandidateRow
    let runtimeMinutes: Int?
    let belongsToCollection: Bool
    let castPopularities: [Double]
    let providerIDs: [Int]
    let trailerKey: String?

    var id: Int { base.id }

    enum CodingKeys: String, CodingKey {
        case runtimeMinutes = "runtime_minutes"
        case belongsToCollection = "belongs_to_collection"
        case castPopularities = "cast_popularities"
        case providerIDs = "provider_ids"
        case trailerKey = "trailer_key"
    }

    init(from decoder: Decoder) throws {
        base = try CandidateRow(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        runtimeMinutes = try container.decodeIfPresent(Int.self, forKey: .runtimeMinutes)
        belongsToCollection = try container.decodeIfPresent(Bool.self, forKey: .belongsToCollection) ?? false
        castPopularities = try container.decodeIfPresent([Double].self, forKey: .castPopularities) ?? []
        providerIDs = try container.decodeIfPresent([Int].self, forKey: .providerIDs) ?? []
        trailerKey = try container.decodeIfPresent(String.self, forKey: .trailerKey)
    }

    init(
        base: CandidateRow,
        runtimeMinutes: Int?,
        belongsToCollection: Bool,
        castPopularities: [Double],
        providerIDs: [Int],
        trailerKey: String?
    ) {
        self.base = base
        self.runtimeMinutes = runtimeMinutes
        self.belongsToCollection = belongsToCollection
        self.castPopularities = castPopularities
        self.providerIDs = providerIDs
        self.trailerKey = trailerKey
    }

    func encode(to encoder: Encoder) throws {
        try base.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(runtimeMinutes, forKey: .runtimeMinutes)
        try container.encode(belongsToCollection, forKey: .belongsToCollection)
        try container.encode(castPopularities, forKey: .castPopularities)
        try container.encode(providerIDs, forKey: .providerIDs)
        try container.encodeIfPresent(trailerKey, forKey: .trailerKey)
    }

    var jsonPayload: [String: Any] {
        var payload = base.jsonPayload
        payload["runtime_minutes"] = runtimeMinutes as Any
        payload["belongs_to_collection"] = belongsToCollection
        payload["cast_popularities"] = castPopularities
        payload["provider_ids"] = providerIDs
        payload["trailer_key"] = trailerKey as Any
        return payload
    }
}
