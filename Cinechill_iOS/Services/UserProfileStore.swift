import Combine
import Foundation
import FirebaseAuth
import SwiftUI

@MainActor
final class UserProfileStore: ObservableObject {
    @Published private(set) var displayName: String = ""
    @Published private(set) var googlePhotoURL: URL? = nil
    @Published private(set) var customPhotoData: Data? = nil

    // Custom photo takes precedence; fallback to Google photo URL
    var avatarData: Data? { customPhotoData }
    var avatarURL: URL? { customPhotoData == nil ? googlePhotoURL : nil }

    func refresh() {
        guard let user = Auth.auth().currentUser else {
            displayName = ""
            googlePhotoURL = nil
            customPhotoData = nil
            return
        }
        displayName = user.displayName
            ?? user.email?.components(separatedBy: "@").first
            ?? "Utilisateur"
        googlePhotoURL = user.photoURL
        customPhotoData = UserDefaults.standard.data(forKey: photoKey(uid: user.uid))
    }

    func updateDisplayName(_ name: String) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let user = Auth.auth().currentUser else { return }
        let request = user.createProfileChangeRequest()
        request.displayName = trimmed
        try await request.commitChanges()
        displayName = trimmed
    }

    func setCustomPhoto(_ data: Data) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        UserDefaults.standard.set(data, forKey: photoKey(uid: uid))
        customPhotoData = data
    }

    func removeCustomPhoto() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        UserDefaults.standard.removeObject(forKey: photoKey(uid: uid))
        customPhotoData = nil
    }

    private func photoKey(uid: String) -> String { "cinechill_avatar_\(uid)" }
}
