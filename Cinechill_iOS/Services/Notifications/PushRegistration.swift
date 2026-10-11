//
//  PushRegistration.swift
//  Cinechill_iOS
//

import Foundation
import UIKit
import UserNotifications
import FirebaseAuth
import FirebaseMessaging

/// Le rattachement de l'appareil au compte, pour les notifications envoyées
/// par le serveur.
///
/// C'est le **seul** fichier qui importe FirebaseMessaging : tout le reste de
/// l'app ne connaît que `sync()` et `signingOut(_:)`, et se vérifie sans lui.
///
/// Le serveur tient, pour chaque compte, la liste de ses appareils : le jeton
/// FCM, la langue choisie dans l'app (il rédige chaque notification dans
/// celle-ci) et le fuseau (il rend muettes celles qui partent la nuit). Dès
/// que l'un des trois change, ou que le compte change, l'appareil se
/// réenregistre. Une fois par semaine aussi, pour que le serveur sache
/// l'appareil vivant.
@MainActor
final class PushRegistration: NSObject, MessagingDelegate {
    static let shared = PushRegistration()

    /// Ce qui a été envoyé au serveur la dernière fois, et quand.
    private static let signatureKey = "push.registration.signature"
    private static let dateKey = "push.registration.date"
    private static let refreshInterval: TimeInterval = 7 * 24 * 3600

    private var fcmToken: String?
    private var authHandle: AuthStateDidChangeListenerHandle?
    private var isSyncing = false
    private var needsAnotherSync = false

    private override init() {
        super.init()
    }

    /// Au lancement, après `FirebaseApp.configure()`.
    func start() {
        Messaging.messaging().delegate = self
        fcmToken = Messaging.messaging().fcmToken
        // Le jeton APNs n'arrive qu'après cette demande, que l'autorisation
        // soit déjà donnée ou non : iOS le délivre de toute façon, et c'est
        // l'autorisation qui décide ensuite de ce qui s'affiche.
        UIApplication.shared.registerForRemoteNotifications()
        authHandle = Auth.auth().addStateDidChangeListener { _, _ in
            Task { @MainActor in await PushRegistration.shared.sync() }
        }
    }

    /// Le jeton APNs, que FCM associe à son propre jeton.
    func didReceiveAPNsToken(_ deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }

    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        Task { @MainActor in
            PushRegistration.shared.fcmToken = fcmToken
            await PushRegistration.shared.sync()
        }
    }

    // MARK: - Le rattachement

    /// Met le serveur à jour si quelque chose a changé : jeton, compte, langue,
    /// fuseau, version, autorisation. Ne fait rien sinon.
    func sync() async {
        // Deux changements rapprochés (le jeton et le compte au lancement) ne
        // doivent pas envoyer deux requêtes croisées : la seconde attend.
        guard !isSyncing else {
            needsAnotherSync = true
            return
        }
        isSyncing = true
        defer { isSyncing = false }

        repeat {
            needsAnotherSync = false
            await syncOnce()
        } while needsAnotherSync
    }

    private func syncOnce() async {
        guard let user = Auth.auth().currentUser, let token = fcmToken else { return }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        let defaults = UserDefaults.standard
        let stored = defaults.string(forKey: Self.signatureKey)

        // Notifications coupées dans iOS : inutile que le serveur en envoie.
        guard NotificationPermission.delivers(settings.authorizationStatus) else {
            if let stored, stored.hasPrefix(user.uid + "|") {
                try? await post(APIEndpoints.unregisterDevice(), body: ["token": token], as: user)
                defaults.removeObject(forKey: Self.signatureKey)
                defaults.removeObject(forKey: Self.dateKey)
            }
            return
        }

        let language = AppLanguage.current.localeIdentifier
        let timeZone = TimeZone.current.identifier
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let signature = [user.uid, token, language, timeZone, version].joined(separator: "|")

        if stored == signature,
           let last = defaults.object(forKey: Self.dateKey) as? Date,
           Date.now.timeIntervalSince(last) < Self.refreshInterval {
            return
        }

        do {
            try await post(APIEndpoints.registerDevice(), body: [
                "token": token,
                "language": language,
                "timeZone": timeZone,
                "appVersion": version,
            ], as: user)
            defaults.set(signature, forKey: Self.signatureKey)
            defaults.set(Date.now, forKey: Self.dateKey)
        } catch {
            // Rien d'enregistré : le prochain passage au premier plan réessaie.
        }
    }

    /// À la déconnexion, juste avant `signOut` : le compte qui s'en va ne doit
    /// plus rien recevoir sur ce téléphone.
    ///
    /// La requête part avec le compte sortant, capturé ici. Firebase sait
    /// encore en tirer un jeton après la déconnexion (il ne l'écrit simplement
    /// plus dans le trousseau), si bien que la déconnexion n'a pas à attendre
    /// le réseau.
    func signingOut(_ user: User) {
        let token = fcmToken
        UserDefaults.standard.removeObject(forKey: Self.signatureKey)
        UserDefaults.standard.removeObject(forKey: Self.dateKey)
        LocalReminders.cancelAll()
        guard let token else { return }
        Task {
            try? await post(APIEndpoints.unregisterDevice(), body: ["token": token], as: user)
        }
    }

    private func post(_ url: URL?, body: [String: String], as user: User) async throws {
        guard let url else { throw URLError(.badURL) }
        let idToken = try await user.getIDToken()
        var request = await URLRequest(backend: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
}
