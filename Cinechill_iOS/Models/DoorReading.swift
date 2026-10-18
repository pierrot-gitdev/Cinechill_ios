//
//  DoorReading.swift
//  Cinechill_iOS
//

import Foundation

/// Ce que le serveur mesure des deux Portes de CinéMatch, sur la galerie et la
/// watchlist. `nil` pour une Porte que le serveur n'a pas mesurée.
nonisolated struct DoorReading: Equatable, Sendable {
    var door: DoorState?
    var seriesDoor: DoorState?
}
