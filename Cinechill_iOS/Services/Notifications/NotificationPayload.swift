//
//  NotificationPayload.swift
//  Cinechill_iOS
//

import Foundation

/// Ce qu'une notification transporte, réduit à des chaînes.
///
/// Les données FCM sont des chaînes, et celles des notifications locales le
/// sont aussi, par choix : un seul format à lire, et une valeur `Sendable` qu'on
/// peut faire passer du délégué de notification au main actor sans emporter le
/// `UNNotificationResponse` d'origine.
nonisolated struct NotificationPayload: Sendable, Equatable {
    /// Ce que la notification raconte : `suggestion`, `suggestionAccepted`,
    /// `recommendedSeen`, `follower`, `filmVerdict`, `tonight`, `nudge`.
    let type: String?
    /// Où mène un toucher : `suggestions`, `profile`, `item`, `followers`,
    /// `cinematch`, `decouvrir`, `verdict`.
    let route: String?
    /// L'autre personne, pour un profil à ouvrir.
    let uid: String?
    /// La recommandation, quand une seule est en jeu.
    let suggestionID: String?
    /// Le titre concerné, en JSON.
    let itemJSON: String?

    init(type: String?, route: String?, uid: String?, suggestionID: String?, itemJSON: String?) {
        self.type = type
        self.route = route
        self.uid = uid
        self.suggestionID = suggestionID
        self.itemJSON = itemJSON
    }

    /// Lit le `userInfo` d'une notification, locale ou distante. Les clés
    /// inconnues (celles de FCM, `aps`) sont ignorées.
    init(userInfo: [AnyHashable: Any]) {
        func string(_ key: String) -> String? {
            guard let value = userInfo[key] as? String, !value.isEmpty else { return nil }
            return value
        }
        self.init(
            type: string("type"),
            route: string("route"),
            uid: string("uid"),
            suggestionID: string("suggestionId"),
            itemJSON: string("item")
        )
    }

    /// Le titre, s'il est lisible.
    var item: MediaItem? {
        guard let itemJSON, let data = itemJSON.data(using: .utf8) else { return nil }
        return (try? JSONDecoder().decode(NotificationItem.self, from: data))?.mediaItem
    }
}

/// Un titre dans une notification.
///
/// Le serveur en envoie l'essentiel (`id`, `mediaType`, `tmdbId`, `title`,
/// `posterPath`, `year`) ; l'avis du lendemain, écrit par l'app, y ajoute de
/// quoi le ranger en galerie sans rien recharger (`overview`, `genreIds`,
/// `releaseDate`, `voteAverage`). Tout ce qui manque reste vide : la fiche
/// recharge son détail en s'ouvrant.
nonisolated struct NotificationItem: Codable, Sendable {
    var id: String?
    var mediaType: String
    var tmdbId: Int
    var title: String
    var posterPath: String?
    var year: String?
    var overview: String?
    var voteAverage: Double?
    var genreIds: [Int]?
    var releaseDate: String?

    init(_ item: MediaItem) {
        id = item.id
        mediaType = item.mediaType == .tv ? "tv" : "movie"
        tmdbId = item.tmdbId
        title = item.title
        posterPath = item.posterPath
        year = (item.releaseDate?.count ?? 0) >= 4 ? item.releaseDate.map { String($0.prefix(4)) } : nil
        overview = item.overview
        voteAverage = item.voteAverage
        genreIds = item.genreIds
        releaseDate = item.releaseDate
    }

    /// Les numéros sont parfois écrits en chaîne par le serveur (les données
    /// FCM n'ont que ce type) : on accepte les deux.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        mediaType = try container.decodeIfPresent(String.self, forKey: .mediaType) ?? "movie"
        if let number = try? container.decode(Int.self, forKey: .tmdbId) {
            tmdbId = number
        } else if let text = try? container.decode(String.self, forKey: .tmdbId), let number = Int(text) {
            tmdbId = number
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: .tmdbId, in: container, debugDescription: "tmdbId absent"
            )
        }
        title = try container.decode(String.self, forKey: .title)
        posterPath = try container.decodeIfPresent(String.self, forKey: .posterPath)
        if let text = try? container.decode(String.self, forKey: .year) {
            year = text
        } else if let number = try? container.decode(Int.self, forKey: .year) {
            year = String(number)
        } else {
            year = nil
        }
        overview = try container.decodeIfPresent(String.self, forKey: .overview)
        voteAverage = try? container.decode(Double.self, forKey: .voteAverage)
        genreIds = try? container.decode([Int].self, forKey: .genreIds)
        releaseDate = try container.decodeIfPresent(String.self, forKey: .releaseDate)
    }

    var json: String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Une saison se reconnaît à son identifiant (`tv-1399-s2`) : c'est elle
    /// qu'on range, et c'est elle que la fiche doit ouvrir.
    var mediaItem: MediaItem {
        let isSeries = mediaType == "tv"
        var season: Int?
        if isSeries, let id, let marker = id.range(of: "-s", options: .backwards) {
            season = Int(id[marker.upperBound...])
        }
        return MediaItem(
            tmdbId: tmdbId,
            mediaType: isSeries ? .tv : .movie,
            title: title,
            posterPath: posterPath,
            overview: overview,
            voteAverage: voteAverage,
            voteCount: nil,
            genreIds: genreIds ?? [],
            releaseDate: releaseDate ?? year,
            season: season
        )
    }
}
