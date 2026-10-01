//
//  SeasonFacts.swift
//  Cinechill_iOS
//

import Foundation

/// Ce que la bibliothèque sait d'une saison. Absent pour un film.
///
/// Tout est écrit par le serveur, qui le lit lui-même chez TMDB au moment où la
/// saison est rangée : une saison peut entrer par sa fiche, par le deck ou par
/// la feuille « et les autres ? », et seule la première connaît ses épisodes.
nonisolated struct SeasonFacts: Hashable, Codable, Sendable {
    let season: Int
    /// « Saison 2 », ou le nom que la série a donné à la saison.
    let seasonName: String?
    /// Épisodes annoncés, sortis ou non.
    let episodes: Int?
    /// Durée médiane d'un épisode, en minutes.
    let episodeRuntime: Int?
    /// Épisodes sortis au moment où la saison a été rangée — ou rafraîchis
    /// depuis par la watchlist, qui seule en a besoin à jour.
    let airedEpisodes: Int?
    /// Date du prochain épisode à sortir, `YYYY-MM-DD`.
    let nextAirDate: String?
    /// Les plateformes françaises d'abonnement de la série.
    let providerIds: [Int]
    /// L'affiche de la série, distincte de celle de la saison. C'est elle que
    /// la frise montre quand plusieurs saisons d'une série partagent une bande.
    let seriesPosterPath: String?

    init(
        season: Int,
        seasonName: String? = nil,
        episodes: Int? = nil,
        episodeRuntime: Int? = nil,
        airedEpisodes: Int? = nil,
        nextAirDate: String? = nil,
        providerIds: [Int] = [],
        seriesPosterPath: String? = nil
    ) {
        self.season = season
        self.seasonName = seasonName
        self.episodes = episodes
        self.episodeRuntime = episodeRuntime
        self.airedEpisodes = airedEpisodes
        self.nextAirDate = nextAirDate
        self.providerIds = providerIds
        self.seriesPosterPath = seriesPosterPath
    }

    /// Lu depuis un document Firestore. `nil` si le document n'est pas une
    /// saison : c'est la présence de `season`, et non `mediaType`, qui décide.
    init?(document data: [String: Any]) {
        guard let season = data["season"] as? Int, season > 0 else { return nil }
        self.init(
            season: season,
            seasonName: data["seasonName"] as? String,
            episodes: data["episodes"] as? Int,
            episodeRuntime: data["episodeRuntime"] as? Int,
            airedEpisodes: data["airedEpisodes"] as? Int,
            nextAirDate: data["nextAirDate"] as? String,
            providerIds: data["providerIds"] as? [Int] ?? [],
            seriesPosterPath: data["seriesPosterPath"] as? String
        )
    }
}
