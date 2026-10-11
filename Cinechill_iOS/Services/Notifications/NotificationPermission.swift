//
//  NotificationPermission.swift
//  Cinechill_iOS
//

import Foundation
import Observation
import UIKit
import UserNotifications

/// L'autorisation des notifications, et les deux moments où on la demande.
///
/// L'ordre est celui du contrat : une autorisation **provisoire** à la fin de
/// l'onboarding (les notifications arrivent sans bruit, dans le centre de
/// notifications, sans qu'iOS ait rien demandé), puis une demande franche à
/// deux moments où elle se comprend d'elle-même. Chaque fois, une feuille
/// Cinechill passe d'abord : « Plus tard » n'ouvre pas la fenêtre d'iOS, qui
/// ne se présente qu'une fois dans la vie de l'app et qu'on ne gaspille pas.
@Observable
@MainActor
final class NotificationPermission {
    static let shared = NotificationPermission()

    /// Les deux moments de la demande franche.
    enum Moment: String, Identifiable, CaseIterable {
        /// Après la première recommandation envoyée.
        case firstSuggestion = "suggestion"
        /// Après le premier « Je le regarde ».
        case firstWatch = "watch"

        var id: String { rawValue }
    }

    private(set) var status: UNAuthorizationStatus = .notDetermined
    /// La feuille à présenter, lue par `MainTabView`.
    var pendingPrompt: Moment?

    private init() {}

    /// Les notifications arrivent-elles, même sans bruit ?
    var canDeliver: Bool {
        Self.delivers(status)
    }

    nonisolated static func delivers(_ status: UNAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .provisional, .ephemeral: true
        case .denied, .notDetermined: false
        @unknown default: false
        }
    }

    @discardableResult
    func refresh() async -> UNAuthorizationStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        status = settings.authorizationStatus
        return status
    }

    // MARK: - Demander

    /// L'autorisation provisoire : aucune fenêtre, les notifications arrivent
    /// en silence dans le centre de notifications. Sans effet si la personne
    /// a déjà répondu à iOS.
    func requestProvisional() async {
        guard await refresh() == .notDetermined else { return }
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge, .provisional])
        await didChangeAuthorization()
    }

    /// La vraie fenêtre d'iOS. Depuis une autorisation provisoire, elle se
    /// présente encore une fois ; après un refus, iOS ne la montre plus et il
    /// faut passer par ses réglages.
    @discardableResult
    func requestFull() async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        await didChangeAuthorization()
        return granted
    }

    /// Une autorisation qui change rouvre le canal des notifications
    /// distantes et rattache l'appareil au compte.
    private func didChangeAuthorization() async {
        await refresh()
        if canDeliver {
            UIApplication.shared.registerForRemoteNotifications()
        }
        await PushRegistration.shared.sync()
    }

    /// Avant de programmer une notification locale : sans réponse encore
    /// donnée à iOS, l'autorisation provisoire suffit et ne demande rien.
    func ensureDeliverable() async -> Bool {
        if await refresh() == .notDetermined {
            await requestProvisional()
        }
        return canDeliver
    }

    // MARK: - Les deux moments

    /// La feuille a-t-elle lieu d'être ? Une fois par moment, jamais si iOS a
    /// déjà eu sa réponse franche (oui ou non).
    func shouldOffer(_ moment: Moment) async -> Bool {
        guard !UserDefaults.standard.bool(forKey: Self.offeredKey(moment)) else { return false }
        switch await refresh() {
        case .notDetermined, .provisional, .ephemeral: return true
        case .authorized, .denied: return false
        @unknown default: return false
        }
    }

    /// Demande la feuille. Le délai laisse à ce qui se refermait (la feuille
    /// de recommandation) le temps de finir : iOS ne présente pas une feuille
    /// par-dessus une autre en train de partir.
    func offer(_ moment: Moment, after delay: Duration = .milliseconds(650)) {
        Task {
            guard await shouldOffer(moment) else { return }
            try? await Task.sleep(for: delay)
            guard pendingPrompt == nil else { return }
            pendingPrompt = moment
            // Une feuille qui n'a pas pu s'ouvrir (un plein écran la couvrait)
            // ne compte pas : le moment reste à venir.
            try? await Task.sleep(for: .seconds(2))
            if pendingPrompt == moment, !UserDefaults.standard.bool(forKey: Self.offeredKey(moment)) {
                pendingPrompt = nil
            }
        }
    }

    /// La feuille s'est montrée : ce moment est passé.
    func markOffered(_ moment: Moment) {
        UserDefaults.standard.set(true, forKey: Self.offeredKey(moment))
    }

    private static func offeredKey(_ moment: Moment) -> String {
        "notif.offered.\(moment.rawValue)"
    }

    // MARK: - « Je le regarde »

    /// Le film part sur la plateforme : on programme la question du lendemain
    /// et on propose la feuille du second moment. Rend `true` si la question
    /// est bien programmée.
    @discardableResult
    func filmStarted(_ item: MediaItem) async -> Bool {
        guard item.mediaType == .movie, NotificationPreference.afterFilm.isOn else { return false }
        guard await ensureDeliverable() else { return false }
        let scheduled = await LocalReminders.scheduleVerdict(for: item)
        if scheduled { offer(.firstWatch) }
        return scheduled
    }
}

/// Les catégories d'actions, enregistrées au lancement et à chaque changement
/// de langue : leurs libellés sont figés au moment de l'enregistrement.
enum NotificationCategories {
    static let suggestion = "SUGGESTION"
    static let filmVerdict = "FILM_VERDICT"

    enum Action {
        static let accept = "ACCEPT"
        static let view = "VIEW"
        static let loved = "LOVED"
        static let liked = "LIKED"
        static let disliked = "DISLIKED"
        static let notWatched = "NOT_WATCHED"
    }

    static func register() {
        // Les actions qui écrivent demandent un appareil déverrouillé : elles
        // modifient le compte, et les clés de session n'y sont lisibles qu'après.
        let write: UNNotificationActionOptions = [.authenticationRequired]

        let suggestion = UNNotificationCategory(
            identifier: suggestion,
            actions: [
                UNNotificationAction(
                    identifier: Action.accept,
                    title: String(localized: "Accepter", bundle: .app),
                    options: write
                ),
                UNNotificationAction(
                    identifier: Action.view,
                    title: String(localized: "Ouvrir", bundle: .app),
                    options: [.foreground]
                ),
            ],
            intentIdentifiers: [],
            options: []
        )

        let verdict = UNNotificationCategory(
            identifier: filmVerdict,
            actions: [
                UNNotificationAction(identifier: Action.loved, title: String(localized: "Je l'ai adoré", bundle: .app), options: write),
                UNNotificationAction(identifier: Action.liked, title: String(localized: "Il m'a plu", bundle: .app), options: write),
                UNNotificationAction(identifier: Action.disliked, title: String(localized: "Pas aimé", bundle: .app), options: write),
                UNNotificationAction(identifier: Action.notWatched, title: String(localized: "Pas regardé", bundle: .app), options: write),
            ],
            intentIdentifiers: [],
            options: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([suggestion, verdict])
    }
}
