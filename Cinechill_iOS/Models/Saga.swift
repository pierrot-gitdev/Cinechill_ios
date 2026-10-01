//
//  Saga.swift
//  Cinechill_iOS
//

import Foundation

/// Un opus d'une saga, tel que le serveur le renvoie.
///
/// Les champs sont exactement ceux d'une carte du deck, et ce n'est pas un
/// hasard : la feuille de saga **est** un deck en lot. Elle n'a donc pas
/// d'écriture propre, elle parle la langue de `recordSwipes` — un « vu » posé
/// depuis la feuille est le même événement qu'un balayage à droite.
nonisolated struct SagaPart: Identifiable, Hashable, Sendable {
    let tmdbId: Int
    let title: String
    let posterPath: String?
    let overview: String?
    let voteAverage: Double?
    let voteCount: Int?
    let genreIds: [Int]
    let releaseDate: String?

    var id: Int { tmdbId }

    var displayYear: String {
        guard let releaseDate, releaseDate.count >= 4 else { return "—" }
        return String(releaseDate.prefix(4))
    }

    /// La même ligne, dans le vocabulaire du deck.
    var swipeCard: SwipeCard {
        SwipeCard(
            tmdbId: tmdbId,
            title: title,
            posterPath: posterPath,
            overview: overview,
            voteAverage: voteAverage,
            voteCount: voteCount,
            genreIds: genreIds,
            releaseDate: releaseDate,
            source: nil
        )
    }
}

/// Une saga et ses opus sortis, dans l'ordre des sorties.
nonisolated struct Saga: Hashable, Sendable {
    let id: Int
    let name: String
    let parts: [SagaPart]

    /// Le nom de la saga, débarrassé du suffixe de catalogue.
    ///
    /// TMDB nomme ses collections « Harry Potter - Saga » en français et
    /// « Harry Potter Collection » en anglais. Ces suffixes-là appartiennent à
    /// une base de données, pas à une phrase qu'on montre à quelqu'un.
    var displayName: String {
        var cleaned = name.trimmingCharacters(in: .whitespaces)
        for suffix in [" - Saga", " – Saga", " : Saga", " Saga", " Collection"] {
            if cleaned.hasSuffix(suffix) {
                cleaned = String(cleaned.dropLast(suffix.count))
                break
            }
        }
        let trimmed = cleaned.trimmingCharacters(in: .whitespaces)
        // Une saga qui ne s'appelait *que* « Saga » n'existe pas, mais un nom
        // vide casserait l'en-tête de la feuille : on garde l'original.
        return trimmed.isEmpty ? name : trimmed
    }
}
