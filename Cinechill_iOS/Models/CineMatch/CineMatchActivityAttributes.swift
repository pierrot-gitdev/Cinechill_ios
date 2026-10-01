//
//  CineMatchActivityAttributes.swift
//  Cinechill_iOS
//

import ActivityKit
import Foundation

/// L'activité en direct d'un film ou d'une série lancé depuis CinéMatch.
///
/// Fichier membre de deux cibles : l'app, qui la démarre, et l'extension
/// `CinechillWidgets`, qui la dessine.
///
/// **Toutes les chaînes y arrivent déjà résolues.** L'extension est un autre
/// processus : elle n'a pas accès au sélecteur de langue des réglages, et
/// `bundle: .app` n'y existe pas. Résoudre ici, dans l'app, garde la langue
/// choisie et dispense l'extension de tout catalogue.
///
/// On ne sait pas où la personne en est dans son film : l'activité dit
/// seulement qu'il est lancé. Aucune progression, aucune heure de fin.
nonisolated struct CineMatchActivityAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable {
        /// Le fichier de l'affiche dans le conteneur partagé.
        ///
        /// Absent au départ : une activité ne se demande que l'app au premier
        /// plan, c'est-à-dire avant d'ouvrir la plateforme, et l'affiche se
        /// télécharge après. Elle arrive par une mise à jour.
        var posterFileName: String?
    }

    let tmdbID: Int
    let title: String
    /// « 2023 · Drame · 1h46 · Netflix », ou « Saison 1 · épisode 1 · … ».
    let details: String
    /// « En cours », tant que la durée du film n'est pas écoulée.
    let playingLabel: String
    /// Ce qui le remplace une fois la durée passée, quand l'activité est
    /// périmée : on ne peut plus affirmer que le film tourne encore.
    let staleLabel: String
}

/// Le dossier que l'app et l'extension partagent.
///
/// L'extension ne peut pas télécharger l'affiche : une activité en direct se
/// dessine sans réseau, `AsyncImage` y reste vide. L'app la dépose donc ici,
/// réduite, et l'extension la lit sur le disque.
nonisolated enum CineMatchActivityStore {
    /// À déclarer dans la capacité App Groups des deux cibles.
    static let appGroup = "group.com.devpierre.Cinechill-iOS"

    static var directory: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent("LiveActivity", isDirectory: true)
    }

    static func posterURL(named name: String) -> URL? {
        directory?.appendingPathComponent(name)
    }
}
