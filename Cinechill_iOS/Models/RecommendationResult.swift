//
//  RecommendationResult.swift
//  Cinechill_iOS
//

import Foundation

/// Un des trois films renvoyés par CinéMatch, avec son score de correspondance et les raisons
/// affichées à l'utilisateur ("Comédie", "< 2h", "Disponible sur Netflix"…).
nonisolated struct RecommendationResult: Identifiable, Hashable, Sendable {
    let item: MediaItem
    let matchScore: Int
    let reasons: [String]

    var id: String { item.id }

    var matchScoreText: String { "\(matchScore)%" }
}
