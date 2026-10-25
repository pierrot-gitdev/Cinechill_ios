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
    }

    func removeCustomPhoto() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        UserDefaults.standard.removeObject(forKey: Self.photoKey(uid: uid))
        customPhotoData = nil
    }

    nonisolated static func photoKey(uid: String) -> String { "cinechill_avatar_\(uid)" }
}
