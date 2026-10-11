//
//  SearchRecents.swift
//  Cinechill_iOS
//

import Foundation

/// Ce qu'on a ouvert depuis la recherche : films, séries, profils.
///
/// On garde ce qui a été ouvert, pas ce qui a été tapé : on y revient en un
/// toucher, alors qu'une requête retapée relance une recherche. Sur l'appareil,
/// par compte, quinze au plus : l'écran en montre huit par portée.
nonisolated enum SearchRecent: Codable, Hashable, Sendable, Identifiable {
    case title(RecentTitle)
    case profile(RecentProfile)

    var id: String {
        switch self {
        case .title(let title): "title-\(title.mediaType)-\(title.tmdbId)"
        case .profile(let profile): "profile-\(profile.uid)"
        }
    }

    /// Juste de quoi redessiner la ligne et rouvrir la fiche, qui recharge le
    /// reste elle-même.
    nonisolated struct RecentTitle: Codable, Hashable, Sendable {
        let tmdbId: Int
        let mediaType: String
        let title: String
        let posterPath: String?
        let releaseDate: String?
        let seasonCount: Int?

        init(_ item: MediaItem) {
            tmdbId = item.tmdbId
            mediaType = item.mediaType.rawValue
            title = item.title
            posterPath = item.posterPath
            releaseDate = item.releaseDate
            seasonCount = item.seasonCount
        }

        var item: MediaItem {
            MediaItem(
                tmdbId: tmdbId,
                mediaType: mediaType == MediaType.tv.rawValue ? .tv : .movie,
                title: title,
                posterPath: posterPath,
                overview: nil,
                voteAverage: nil,
                voteCount: nil,
                genreIds: [],
                releaseDate: releaseDate,
                seasonCount: seasonCount
            )
        }
    }

    nonisolated struct RecentProfile: Codable, Hashable, Sendable {
        let uid: String
        let handle: String
        let displayName: String
        let avatarURL: URL?
        let galleryCount: Int

        init(_ profile: PublicProfile) {
            uid = profile.id
            handle = profile.handle
            displayName = profile.displayName
            avatarURL = profile.avatarURL
            galleryCount = profile.galleryCount
        }

        var profile: PublicProfile {
            PublicProfile(
                id: uid,
                handle: handle,
                displayName: displayName,
                // Repassée au filtre : une URL gardée sur l'appareil n'est pas
                // plus sûre qu'une URL lue dans Firestore.
                avatarURL: PublicProfile.trustedAvatarURL(avatarURL?.absoluteString),
                badgeSignature: nil,
                followerCount: 0,
                followingCount: 0,
                galleryCount: galleryCount
            )
        }
    }
}

/// La liste des récents d'un compte, dans `UserDefaults`.
nonisolated struct SearchRecentsStore {
    private static let capacity = 15

    let uid: String?

    private var key: String? { uid.map { "cinechill_search_recents_\($0)" } }

    func load() -> [SearchRecent] {
        guard let key, let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([SearchRecent].self, from: data)) ?? []
    }

    /// Remonte l'élément en tête, sans doublon.
    func record(_ recent: SearchRecent) -> [SearchRecent] {
        var list = load()
        list.removeAll { $0.id == recent.id }
        list.insert(recent, at: 0)
        list = Array(list.prefix(Self.capacity))
        save(list)
        return list
    }

    func clear() {
        guard let key else { return }
        UserDefaults.standard.removeObject(forKey: key)
    }

    private func save(_ list: [SearchRecent]) {
        guard let key, let data = try? JSONEncoder().encode(list) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
