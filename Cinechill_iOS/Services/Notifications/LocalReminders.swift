//
//  LocalReminders.swift
//  Cinechill_iOS
//

import Foundation
import UIKit
import UserNotifications
import FirebaseAuth

/// Les réglages de notification tenus par l'appareil, compte par compte.
///
/// Seul « Recommandations et abonnés » vit sur le serveur, qui envoie ces
/// notifications-là. Les trois autres sont programmées ici même : le serveur
/// n'a pas à les connaître.
nonisolated enum NotificationPreference: String, CaseIterable, Sendable {
    /// N5, le lendemain d'un « Je le regarde ».
    case afterFilm = "notif.afterFilm"
    /// N9, ce qu'il reste à faire avant CinéMatch.
    case reminders = "notif.reminders"
    /// N6, « Ce soir ? » le lundi et le mercredi.
    case tonight = "notif.tonight"

    /// N6 est désactivé tant qu'on ne l'a pas demandé : une notification qui
    /// pousse à ouvrir l'app sans rien apporter de neuf n'est acceptée par
    /// l'App Store (4.5.4) qu'avec l'accord explicite de la personne.
    var defaultValue: Bool { self != .tonight }

    private static var uid: String { Auth.auth().currentUser?.uid ?? "anonymous" }

    var isOn: Bool {
        let key = "\(rawValue).\(Self.uid)"
        guard UserDefaults.standard.object(forKey: key) != nil else { return defaultValue }
        return UserDefaults.standard.bool(forKey: key)
    }

    func set(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: "\(rawValue).\(Self.uid)")
    }
}

/// Les notifications que l'app programme elle-même : N5, N6 et N9.
///
/// Chacune est rédigée au moment où on la programme, dans la langue de l'app
/// (`bundle: .app`). Changer de langue réécrit celle qui attend
/// (`relocalizeVerdict`) ; N6 et N9 se réécrivent d'elles-mêmes à chaque
/// passage en arrière-plan.
enum LocalReminders {
    // MARK: - Les identifiants

    static let verdictID = "verdict"
    static let tonightIDs = ["tonight-mon", "tonight-wed"]
    static let nudgeIDs = ["nudge-1", "nudge-2"]

    /// Le film dont la question du lendemain attend, pour l'annuler sans
    /// relire la file du système à chaque mouvement de la galerie.
    private static let pendingVerdictKey = "notif.pendingVerdictItem"

    private static var center: UNUserNotificationCenter { .current() }

    // MARK: - N5, le lendemain d'un film

    /// Programme la question du lendemain pour ce film. Une seule à la fois :
    /// le dernier « Je le regarde » remplace le précédent.
    ///
    /// Rend `false` quand rien n'a été programmé (réglage coupé, série,
    /// refus du système) : la watchlist garde alors son ancien geste et range
    /// le film tout de suite.
    @discardableResult
    static func scheduleVerdict(for item: MediaItem, now: Date = .now) async -> Bool {
        guard item.mediaType == .movie, NotificationPreference.afterFilm.isOn else { return false }
        guard let fireDate = verdictDate(after: now) else { return false }
        guard let request = verdictRequest(for: item, at: fireDate) else { return false }

        center.removePendingNotificationRequests(withIdentifiers: [verdictID])
        do {
            try await center.add(request)
        } catch {
            return false
        }
        UserDefaults.standard.set(item.id, forKey: pendingVerdictKey)
        return true
    }

    /// Le lendemain à 19 h. Un film lancé après minuit appartient encore à la
    /// soirée de la veille : la question vient alors le jour même, sinon
    /// « hier » serait faux.
    static func verdictDate(after now: Date) -> Date? {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: now)
        let dayOffset = hour < 5 ? 0 : 1
        guard let day = calendar.date(byAdding: .day, value: dayOffset, to: now) else { return nil }
        return calendar.date(bySettingHour: 19, minute: 0, second: 0, of: day)
    }

    private static func verdictRequest(for item: MediaItem, at date: Date) -> UNNotificationRequest? {
        guard let json = NotificationItem(item).json else { return nil }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Tu as regardé \(item.title) hier ?", bundle: .app)
        content.body = String(localized: "Ta réponse compte pour tes prochains films.", bundle: .app)
        content.sound = .default
        content.categoryIdentifier = NotificationCategories.filmVerdict
        content.threadIdentifier = "verdict"
        content.userInfo = ["type": "filmVerdict", "route": "verdict", "item": json]

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(identifier: verdictID, content: content, trigger: trigger)
    }

    /// Annule la question du lendemain si son film fait partie de ceux-là :
    /// rangé en galerie entre-temps, il a déjà sa réponse.
    static func cancelVerdict(ifAnyOf itemIDs: Set<String>) {
        guard let pending = UserDefaults.standard.string(forKey: pendingVerdictKey),
              itemIDs.contains(pending) else { return }
        cancelVerdict()
    }

    static func cancelVerdict() {
        center.removePendingNotificationRequests(withIdentifiers: [verdictID])
        UserDefaults.standard.removeObject(forKey: pendingVerdictKey)
    }

    /// Réécrit la question qui attend dans la langue de l'app, à la même heure.
    static func relocalizeVerdict() async {
        let pending = await center.pendingNotificationRequests()
        guard let request = pending.first(where: { $0.identifier == verdictID }),
              let trigger = request.trigger as? UNCalendarNotificationTrigger,
              let date = trigger.nextTriggerDate(),
              let item = NotificationPayload(userInfo: request.content.userInfo).item,
              let fresh = verdictRequest(for: item, at: date) else { return }
        try? await center.add(fresh)
    }

    // MARK: - N6, « Ce soir ? »

    /// Lundi et mercredi à 20 h, si la Porte des films est ouverte et que la
    /// personne l'a demandé. Sinon, retire ce qui serait resté programmé.
    static func scheduleTonight(doorOpen: Bool) async {
        center.removePendingNotificationRequests(withIdentifiers: tonightIDs)
        guard doorOpen, NotificationPreference.tonight.isOn else { return }

        // Calendrier grégorien : 2 = lundi, 4 = mercredi.
        for (identifier, weekday) in zip(tonightIDs, [2, 4]) {
            let content = UNMutableNotificationContent()
            content.title = String(localized: "Tu regardes quoi ce soir ?", bundle: .app)
            content.body = String(localized: "CinéMatch te trouve ton film.", bundle: .app)
            content.sound = .default
            content.threadIdentifier = "tonight"
            content.userInfo = ["type": "tonight", "route": "cinematch"]

            var components = DateComponents()
            components.weekday = weekday
            components.hour = 20
            components.minute = 0
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
        }
    }

    static func cancelTonight() {
        center.removePendingNotificationRequests(withIdentifiers: tonightIDs)
    }

    // MARK: - N9, avant CinéMatch

    /// Deux rappels, à J+3 et J+7 à 19 h, tant que la Porte des films est
    /// fermée et que la galerie compte au moins 20 films : en dessous, la
    /// marche est trop haute pour qu'un rappel aide.
    static func scheduleNudges(door: DoorState, galleryFilmCount: Int, now: Date = .now) async {
        cancelNudges()
        guard NotificationPreference.reminders.isOn,
              !door.unlocked,
              galleryFilmCount >= 20,
              let text = nudgeText(for: door) else { return }

        let calendar = Calendar.current
        for (identifier, days) in zip(nudgeIDs, [3, 7]) {
            guard let day = calendar.date(byAdding: .day, value: days, to: now),
                  let date = calendar.date(bySettingHour: 19, minute: 0, second: 0, of: day) else { continue }
            let content = UNMutableNotificationContent()
            content.title = text.title
            content.body = text.body
            content.sound = .default
            content.threadIdentifier = "nudge"
            content.userInfo = ["type": "nudge", "route": text.route]

            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
        }
    }

    static func cancelNudges() {
        center.removePendingNotificationRequests(withIdentifiers: nudgeIDs)
    }

    /// Ce que dit le rappel. Tant que l'étape des films vus n'est pas faite,
    /// c'est elle qu'on nomme : c'est la plus longue, et Découvrir la remplit.
    /// Ensuite, le nombre d'étapes, et CinéMatch montre lesquelles.
    static func nudgeText(for door: DoorState) -> (title: String, body: String, route: String)? {
        if let memory = door.artifact(.memoire), !memory.done {
            let missing = max(1, memory.target - memory.current)
            let title = missing == 1
                ? String(localized: "Plus qu'un film avant CinéMatch", bundle: .app)
                : String(localized: "Plus que \(missing) films avant CinéMatch", bundle: .app)
            return (title, String(localized: "Ajoute ceux que tu as déjà vus, en quelques swipes.", bundle: .app), "decouvrir")
        }
        let steps = DoorArtifactKey.allCases.filter { door.artifact($0)?.done != true }.count
        guard steps > 0 else { return nil }
        let title = steps == 1
            ? String(localized: "Plus qu'une étape avant CinéMatch", bundle: .app)
            : String(localized: "Plus que \(steps) étapes avant CinéMatch", bundle: .app)
        return (title, String(localized: "Touche pour voir ce qu'il reste.", bundle: .app), "cinematch")
    }

    // MARK: - Les passages de l'app

    /// À l'arrière-plan : N6 et N9 se réécrivent sur l'état du moment. Le
    /// système laisse quelques secondes à l'app ; la tâche de fond les garantit.
    static func appDidEnterBackground(door: DoorState, doorKnown: Bool, galleryFilmCount: Int) {
        let task = BackgroundTask()
        task.begin()
        Task {
            await scheduleTonight(doorOpen: doorKnown && door.unlocked)
            if doorKnown {
                await scheduleNudges(door: door, galleryFilmCount: galleryFilmCount)
            }
            task.end()
        }
    }

    /// Au retour : les rappels n'ont plus lieu d'être, on les reprogrammera
    /// au prochain départ.
    static func appDidBecomeActive() {
        cancelNudges()
    }

    /// À la déconnexion : tout ce qui est programmé parle du compte qui s'en va.
    static func cancelAll() {
        cancelVerdict()
        cancelTonight()
        cancelNudges()
    }
}

/// Quelques secondes de plus accordées par iOS après le départ de l'app,
/// rendues dès que le travail est fait, ou quand iOS les reprend.
final class BackgroundTask {
    private var identifier = UIBackgroundTaskIdentifier.invalid

    func begin(name: String = "notifications") {
        identifier = UIApplication.shared.beginBackgroundTask(withName: name) { [self] in
            end()
        }
    }

    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}
