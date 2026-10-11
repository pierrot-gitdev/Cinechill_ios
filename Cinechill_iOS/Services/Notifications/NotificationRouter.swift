//
//  NotificationRouter.swift
//  Cinechill_iOS
//

import Foundation
import Observation

/// Traduit le toucher d'une notification en navigation.
///
/// Il ne navigue pas lui-même : il pose une destination, et `MainTabView`, qui
/// tient les onglets et les feuilles, la prend dès qu'elle peut. « Dès qu'elle
/// peut » est tout l'objet de ce type : un toucher arrive souvent dans une app
/// qui se lance, avant que le compte soit connu ou pendant l'onboarding. La
/// destination attend alors, puis se rejoue.
@Observable
@MainActor
final class NotificationRouter {
    static let shared = NotificationRouter()

    enum Destination: Equatable {
        /// Le panneau des recommandations reçues.
        case suggestions
        /// Le profil public d'une personne.
        case profile(uid: String)
        /// La fiche d'un titre.
        case item(MediaItem)
        /// La fiche d'un film, avec les quatre réponses du lendemain en tête.
        case verdict(MediaItem)
        /// La liste de ses abonnés.
        case followers
        /// L'onglet CinéMatch.
        case cinematch
        /// L'onglet Découvrir.
        case decouvrir
    }

    /// La destination qui attend d'être prise.
    private(set) var pending: Destination?

    /// La demande d'ouvrir le panneau des recommandations, et son heure. Le
    /// panneau appartient à l'en-tête de chaque onglet ; celui de l'onglet
    /// affiché la prend. Passé quelques secondes, elle ne vaut plus rien : un
    /// panneau qui s'ouvrirait longtemps après le toucher surprendrait.
    private(set) var panelRequest: Date?

    private init() {}

    func open(_ destination: Destination) {
        pending = destination
    }

    /// `MainTabView` prend la destination en charge.
    func consume() -> Destination? {
        defer { pending = nil }
        return pending
    }

    func requestPanel() {
        panelRequest = .now
    }

    /// Vrai une seule fois par demande, et seulement si elle est fraîche.
    func consumePanelRequest() -> Bool {
        guard let requested = panelRequest else { return false }
        panelRequest = nil
        return Date.now.timeIntervalSince(requested) < 6
    }

    // MARK: - Lire une notification

    /// Le toucher sur la notification elle-même, ou une action qui ouvre l'app.
    func handleTap(_ payload: NotificationPayload) {
        guard let destination = Self.destination(for: payload) else { return }
        open(destination)
    }

    /// La destination d'une notification. Une route inconnue (une version
    /// plus récente du serveur) ouvre l'app sans rien de plus.
    static func destination(for payload: NotificationPayload) -> Destination? {
        switch payload.route {
        case "suggestions":
            return .suggestions
        case "profile":
            guard let uid = payload.uid else { return nil }
            return .profile(uid: uid)
        case "item":
            guard let item = payload.item else { return nil }
            return .item(item)
        case "verdict":
            guard let item = payload.item else { return nil }
            return .verdict(item)
        case "followers":
            return .followers
        case "cinematch":
            return .cinematch
        case "decouvrir":
            return .decouvrir
        default:
            return nil
        }
    }
}
