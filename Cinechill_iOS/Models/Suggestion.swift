//
//  Suggestion.swift
//  Cinechill_iOS
//

import Foundation

/// Un film recommandé par quelqu'un qu'on suit, en attente de réponse.
///
/// Le nom évite délibérément « Recommendation » : `RecommendationResult` et
/// `BackendRecommendationClient` désignent déjà l'algorithme CinéMatch. Deux
/// concepts sans rapport sous un même mot rendraient le code illisible.
nonisolated struct Suggestion: Identifiable, Hashable, Sendable {
    /// `{fromUid}_{itemId}` — déterministe, ce qui rend « déjà recommandé »
    /// vérifiable sans requête côté serveur.
    let id: String
    let fromUid: String
    let fromHandle: String?
    let fromDisplayName: String
    let fromAvatarURL: URL?
    let item: MediaItem
    let createdAt: Date

    var senderInitial: String {
        guard let first = fromDisplayName.first else { return "?" }
        return String(first).uppercased()
    }
}

extension Suggestion {
    /// Décode un document `users/{uid}/suggestions`. Renvoie `nil` si le film
    /// ou l'expéditeur manquent — une recommandation à moitié lisible ne peut
    /// pas être présentée comme un choix à trancher.
    init?(id: String, data: [String: Any]) {
        guard
            let fromUid = data["fromUid"] as? String,
            let itemData = data["item"] as? [String: Any],
            let tmdbId = itemData["tmdbId"] as? Int,
            let mediaTypeRaw = itemData["mediaType"] as? String,
            let mediaType = MediaType(rawValue: mediaTypeRaw),
            let title = itemData["title"] as? String
        else {
            return nil
        }

        self.id = id
        self.fromUid = fromUid
        self.fromHandle = data["fromHandle"] as? String
        self.fromDisplayName = (data["fromDisplayName"] as? String)
            ?? (data["fromHandle"] as? String)
            ?? "Quelqu'un"
        self.fromAvatarURL = (data["fromAvatarURL"] as? String)
            .flatMap(URL.init(string:))
        self.item = MediaItem(
            tmdbId: tmdbId,
            mediaType: mediaType,
            title: title,
            posterPath: itemData["posterPath"] as? String,
            overview: itemData["overview"] as? String,
            voteAverage: itemData["voteAverage"] as? Double,
            genreIds: itemData["genreIds"] as? [Int] ?? [],
            releaseDate: itemData["releaseDate"] as? String
        )
        self.createdAt = (data["createdAt"] as? Date) ?? .distantPast
    }
}

/// Un abonnement, et ce qu'il peut recevoir pour un film donné.
///
/// L'état arrive du serveur avec la liste, pas après coup : c'est ce qui
/// permet de désactiver la ligne au lieu d'échouer à l'envoi. Le client ne
/// voit jamais la galerie d'autrui, seulement ces deux booléens.
nonisolated struct SuggestionTarget: Identifiable, Hashable, Sendable {
    let id: String
    let handle: String?
    let displayName: String
    let avatarURL: URL?
    let alreadySeen: Bool
    let alreadySuggested: Bool
    let suggestedAt: Date?

    /// Ni déjà vu, ni déjà recommandé : la seule combinaison sélectionnable.
    var canReceive: Bool { !alreadySeen && !alreadySuggested }

    var initial: String {
        guard let first = displayName.first else { return "?" }
        return String(first).uppercased()
    }

    /// La raison affichée sous le nom quand la ligne est bloquée — jamais un
    /// message générique, toujours l'état exact.
    var blockedReason: String? {
        if alreadySeen { return "A déjà vu ce film" }
        guard alreadySuggested else { return nil }
        guard let suggestedAt else { return "Déjà recommandé" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "d MMMM"
        return "Déjà recommandé le \(formatter.string(from: suggestedAt))"
    }
}
