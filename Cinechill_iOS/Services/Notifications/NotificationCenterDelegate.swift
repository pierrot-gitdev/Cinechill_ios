//
//  NotificationCenterDelegate.swift
//  Cinechill_iOS
//

import Foundation
import UserNotifications

/// Le délégué du centre de notifications, posé au lancement par `AppDelegate`.
///
/// Il reçoit trois choses : une notification qui arrive pendant que l'app est
/// ouverte, un toucher, et une action choisie sous la notification. Les
/// actions qui n'ouvrent pas l'app (accepter une recommandation, répondre à la
/// question du lendemain) font leur appel réseau **avant** de rendre la main :
/// iOS suspend l'app dès que la méthode a fini, et un appel lancé sans être
/// attendu mourrait avec elle.
///
/// Rien n'est isolé au main actor ici : iOS appelle ces méthodes depuis le fil
/// qu'il veut. Chacune réduit la notification à un `NotificationPayload` de
/// chaînes, puis passe au main actor pour le reste.
nonisolated final class NotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate, Sendable {
    static let shared = NotificationCenterDelegate()

    /// App ouverte : la notification s'affiche quand même. Un rappel « avant
    /// CinéMatch » n'a rien à dire à quelqu'un qui est déjà dans l'app.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let payload = NotificationPayload(userInfo: notification.request.content.userInfo)
        if payload.type == "nudge" { return [] }
        return [.banner, .list, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let payload = NotificationPayload(userInfo: response.notification.request.content.userInfo)
        let action = response.actionIdentifier
        await Self.handle(action: action, payload: payload)
    }

    @MainActor
    private static func handle(action: String, payload: NotificationPayload) async {
        switch action {
        case UNNotificationDefaultActionIdentifier:
            NotificationRouter.shared.handleTap(payload)

        case UNNotificationDismissActionIdentifier:
            return

        case NotificationCategories.Action.view:
            // « Ouvrir » sur une recommandation : la fiche si le serveur l'a
            // jointe, sinon le panneau des recommandations.
            if let item = payload.item {
                NotificationRouter.shared.open(.item(item))
            } else {
                NotificationRouter.shared.open(.suggestions)
            }

        case NotificationCategories.Action.accept:
            guard let id = payload.suggestionID else {
                NotificationRouter.shared.open(.suggestions)
                return
            }
            // Un échec ne se rattrape pas d'ici : la recommandation reste en
            // attente dans le panneau, où l'on pourra l'accepter.
            _ = try? await SocialClient().respond(to: id, accept: true)

        case NotificationCategories.Action.loved:
            await answer(.loved, payload: payload)
        case NotificationCategories.Action.liked:
            await answer(.liked, payload: payload)
        case NotificationCategories.Action.disliked:
            await answer(.disliked, payload: payload)
        case NotificationCategories.Action.notWatched:
            await answer(.notWatched, payload: payload)

        default:
            NotificationRouter.shared.handleTap(payload)
        }
    }

    @MainActor
    private static func answer(_ verdict: LibraryStore.FilmVerdict, payload: NotificationPayload) async {
        guard let item = payload.item else { return }
        do {
            try await LibraryStore.sendFilmVerdict(item: item, verdict: verdict)
        } catch {
            // Sans réseau, la réponse se perdrait en silence. On la redemande
            // plutôt en ouvrant la fiche au prochain passage dans l'app.
            NotificationRouter.shared.open(.verdict(item))
        }
    }
}
