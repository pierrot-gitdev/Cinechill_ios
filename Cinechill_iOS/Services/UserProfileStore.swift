import Combine
import Foundation
import FirebaseAuth
import SwiftUI

@MainActor
final class UserProfileStore: ObservableObject {
    /// Le nom à afficher sur ce téléphone, avec un repli quand le compte n'en
    /// a pas.
    @Published private(set) var displayName: String = ""
    /// Le nom que la personne s'est donné, et rien d'autre. C'est le seul qui
    /// part sur le profil public : le repli de `displayName` publiait le début
    /// de l'adresse e-mail, ou « Utilisateur », et l'indexait dans la recherche.
    @Published private(set) var chosenName: String?
    @Published private(set) var googlePhotoURL: URL? = nil
    @Published private(set) var customPhotoData: Data? = nil

    // Custom photo takes precedence; fallback to Google photo URL
    var avatarData: Data? { customPhotoData }
    var avatarURL: URL? { customPhotoData == nil ? googlePhotoURL : nil }

    func refresh() {
        guard let user = Auth.auth().currentUser else {
            displayName = ""
            chosenName = nil
            googlePhotoURL = nil
            customPhotoData = nil
            return
        }
        // Un nom vide n'est pas un nom : Apple le renvoie parfois tel quel, et
        // le profil s'ouvrait sur un titre blanc.
        chosenName = user.displayName.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
        displayName = chosenName
            ?? user.email?.components(separatedBy: "@").first.flatMap { $0.isEmpty ? nil : $0 }
            ?? String(localized: "Utilisateur", bundle: .app)
        googlePhotoURL = user.photoURL
        customPhotoData = UserDefaults.standard.data(forKey: Self.photoKey(uid: user.uid))
    }

    func updateDisplayName(_ name: String) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let user = Auth.auth().currentUser else { return }
        let request = user.createProfileChangeRequest()
        request.displayName = trimmed
        try await request.commitChanges()
        displayName = trimmed
        chosenName = trimmed
    }

    func setCustomPhoto(_ data: Data) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        UserDefaults.standard.set(data, forKey: Self.photoKey(uid: uid))
        customPhotoData = data
        Task { await publishAvatar(uid: uid) }
    }

    func removeCustomPhoto() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        UserDefaults.standard.removeObject(forKey: Self.photoKey(uid: uid))
        customPhotoData = nil
        Task { await publishAvatar(uid: uid) }
    }

    nonisolated static func photoKey(uid: String) -> String { "cinechill_avatar_\(uid)" }

    // MARK: - La photo publiée

    /// La photo ne vivait que sur ce téléphone : le profil public n'en avait
    /// aucune, et personne ne la voyait dans le Hall. Elle part désormais sur
    /// le profil public à chaque changement, et une fois au lancement pour
    /// les comptes qui en avaient déjà une. Sans photo choisie, le serveur
    /// publie celle du compte Google.
    private nonisolated static func publishedKey(uid: String) -> String { "avatar.published.v1.\(uid)" }

    /// Une fois par compte : publie la photo d'avant cette version.
    func publishAvatarIfNeeded() async {
        guard let uid = Auth.auth().currentUser?.uid,
              !UserDefaults.standard.bool(forKey: Self.publishedKey(uid: uid)) else { return }
        await publishAvatar(uid: uid)
    }

    /// Envoie la photo choisie, ou son absence. Un échec se retente au
    /// lancement suivant.
    private func publishAvatar(uid: String) async {
        let key = Self.publishedKey(uid: uid)
        UserDefaults.standard.set(false, forKey: key)
        let photo = UserDefaults.standard.data(forKey: Self.photoKey(uid: uid))
        let jpeg = photo.flatMap { Self.avatarJPEG($0) }
        // Une photo illisible ne part pas : mieux vaut aucune photo publiée
        // qu'un refus du serveur à chaque lancement.
        if photo != nil, jpeg == nil { return }
        do {
            try await AvatarClient().publish(jpeg)
            guard Auth.auth().currentUser?.uid == uid else { return }
            UserDefaults.standard.set(true, forKey: key)
        } catch {
            // Rien à dire à l'écran : la photo reste sur le téléphone, et
            // repartira au prochain lancement.
        }
    }

    /// 256 pixels au plus long : assez pour la plus grande pastille du Hall,
    /// une vingtaine de Ko.
    private static func avatarJPEG(_ data: Data) -> Data? {
        guard let image = UIImage(data: data),
              let resized = image.resized(toMaxDimension: 256) else { return nil }
        return resized.jpegData(compressionQuality: 0.75)
    }
}

/// L'appel qui publie la photo de profil.
nonisolated struct AvatarClient: Sendable {
    /// - Parameter jpeg: la photo, ou `nil` pour la retirer.
    func publish(_ jpeg: Data?) async throws {
        guard let url = await APIEndpoints.setAvatar() else { throw URLError(.badURL) }
        guard let user = Auth.auth().currentUser else { throw URLError(.userAuthenticationRequired) }
        let token = try await user.getIDToken()

        var request = await URLRequest(backend: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let body: [String: Any] = ["image": jpeg?.base64EncodedString() ?? NSNull()]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
}
