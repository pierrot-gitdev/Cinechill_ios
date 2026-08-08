//
//  PublicProfile.swift
//  Cinechill_iOS
//

import Foundation

/// Ce qu'un autre utilisateur voit de vous — « Le Hall ».
///
/// Volontairement disjoint de `UserProfileStore`, qui ne connaît que le compte
/// courant et ses données locales : ici, tout vient de `publicProfiles/{uid}`
/// et rien n'est modifiable depuis cet écran. La watchlist n'y figure pas, et
/// c'est une décision de conception, pas un oubli : ce qu'on a l'intention de
/// voir est une note à soi-même, pas une déclaration publique.
nonisolated struct PublicProfile: Identifiable, Hashable, Sendable {
    /// L'uid Firebase — l'identité qui sert à suivre et à recommander.
    let id: String
    /// Le pseudo tel que saisi, avec sa casse d'origine.
    let handle: String
    let displayName: String
    let avatarURL: URL?
    /// L'identifiant du badge choisi comme signature, s'il y en a un.
    let badgeSignature: String?
    let followerCount: Int
    let followingCount: Int
    let galleryCount: Int

    /// Les initiales servent d'avatar de repli — jamais une silhouette
    /// générique, qui rendrait toutes les lignes d'une liste identiques.
    var initials: String {
        let source = displayName.isEmpty ? handle : displayName
        guard let first = source.first else { return "?" }
        return String(first).uppercased()
    }

    var handleDisplay: String { "@\(handle)" }
}

/// Une affiche de la galerie d'autrui — chemin et titre, rien d'autre. Ce
/// n'est pas une entrée de galerie : le serveur n'en renvoie qu'un aperçu.
nonisolated struct PublicPoster: Identifiable, Hashable, Sendable {
    let posterPath: String?
    let title: String

    var id: String { (posterPath ?? "") + title }
}

/// Le profil public complété de quoi décider de suivre quelqu'un.
///
/// Les agrégats viennent du serveur : la galerie d'autrui n'est jamais lue
/// depuis le client, les règles Firestore l'interdisent. On reçoit une
/// répartition et douze affiches, pas une collection.
nonisolated struct PublicProfileDetail: Hashable, Sendable {
    let profile: PublicProfile
    let genres: [GenreShare]
    let posters: [PublicPoster]
}

extension PublicProfile {
    /// Décode un document `publicProfiles`. Renvoie `nil` si l'identité de base
    /// manque : un profil sans pseudo n'est pas affichable, et vaut mieux être
    /// absent de la liste qu'y figurer en blanc.
    init?(id: String, data: [String: Any]) {
        guard let handle = data["handle"] as? String, !handle.isEmpty else {
            return nil
        }
        self.id = id
        self.handle = handle
        self.displayName = (data["displayName"] as? String) ?? handle
        self.avatarURL = (data["avatarURL"] as? String).flatMap(URL.init(string:))
        self.badgeSignature = data["badgeSignature"] as? String
        self.followerCount = (data["followerCount"] as? Int) ?? 0
        self.followingCount = (data["followingCount"] as? Int) ?? 0
        self.galleryCount = (data["galleryCount"] as? Int) ?? 0
    }
}
