//
//  DebugFixtures.swift
//  Cinechill_iOS
//

#if DEBUG
import Foundation

/// Des données de test pour la recherche et les profils à suivre, en Debug
/// seulement.
///
/// Pas d'interrupteur à l'écran : on le pose dans le schéma Xcode, en argument
/// de lancement, `-debugData worst` ou `-debugData empty`. iOS range les
/// arguments de lancement dans `UserDefaults`, d'où la lecture ci-dessous. Sans
/// argument, tout passe par le serveur.
///
/// Le pire cas tient ce qu'on voit en vrai : un nom de trente caractères, un
/// pseudo au maximum de vingt, un profil sans nom, 0 et 1 pour les pluriels,
/// des diacritiques vietnamiens, un titre de film de quatre-vingts caractères,
/// une affiche et une année absentes.
nonisolated enum DebugFixtures {
    enum Mode: String {
        case worst
        case empty
    }

    static var mode: Mode? {
        UserDefaults.standard.string(forKey: "debugData").flatMap(Mode.init(rawValue:))
    }

    static var followSuggestions: FollowSuggestionsPage? {
        switch mode {
        case nil: nil
        case .empty: FollowSuggestionsPage(followingCount: 0, suggestions: [])
        case .worst: FollowSuggestionsPage(followingCount: 2, suggestions: worstSuggestions)
        }
    }

    /// Les titres trouvés, filtrés comme le ferait TMDB, en gros.
    static func titles(matching query: String) -> [MediaItem]? {
        switch mode {
        case nil: return nil
        case .empty: return []
        case .worst:
            let needle = SocialStore.normalize(query)
            return worstTitles.filter { SocialStore.normalize($0.title).contains(needle) }
        }
    }

    static func profiles(matching query: String) -> [PublicProfile]? {
        switch mode {
        case nil: return nil
        case .empty: return []
        case .worst:
            let words = SocialStore.searchWords(SocialStore.normalize(query))
            return worstSuggestions.map(\.profile).filter { profile in
                let haystack = SocialStore.searchWords(SocialStore.normalize(profile.displayName + " " + profile.handle))
                return words.allSatisfy { word in haystack.contains { $0.hasPrefix(word) } }
            }
        }
    }

    // MARK: - Les données

    private static func profile(_ id: String, _ handle: String, _ name: String?, seen: Int) -> PublicProfile {
        PublicProfile(
            id: id,
            handle: handle,
            displayName: PublicProfile.nameOrHandle(name, handle),
            avatarURL: nil,
            badgeSignature: nil,
            followerCount: 0,
            followingCount: 0,
            galleryCount: seen
        )
    }

    private static let worstSuggestions: [FollowSuggestion] = [
        FollowSuggestion(
            profile: profile("debug-1", "cinephile.nocturne_", nil, seen: 0),
            followsYou: true, mutualCount: 0, mutualName: nil, commonCount: 0
        ),
        FollowSuggestion(
            profile: profile("debug-2", "aleksandra.wisniewsk", "Aleksandra Wiśniewska-Kowalczyk", seen: 2847),
            followsYou: false, mutualCount: 15, mutualName: "Marie-Charlotte", commonCount: 0
        ),
        FollowSuggestion(
            profile: profile("debug-3", "phuong.thao", "Nguyễn Thị Phương Thảo", seen: 58),
            followsYou: false, mutualCount: 2, mutualName: "Léa", commonCount: 0
        ),
        FollowSuggestion(
            profile: profile("debug-4", "jbdlr", "Jean-Baptiste de La Rochefoucauld-Montmorency", seen: 312),
            followsYou: false, mutualCount: 0, mutualName: nil, commonCount: 47
        ),
        FollowSuggestion(
            profile: profile("debug-5", "jo", "Jo", seen: 1),
            followsYou: false, mutualCount: 0, mutualName: nil, commonCount: 1
        ),
        FollowSuggestion(
            profile: profile("debug-6", "soren.k", "Søren Lindqvist", seen: 1203),
            followsYou: false, mutualCount: 1, mutualName: "Léa", commonCount: 0
        ),
    ]

    private static func title(
        _ id: Int, _ title: String, _ type: MediaType, year: String?, poster: String?, seasons: Int? = nil
    ) -> MediaItem {
        MediaItem(
            tmdbId: id,
            mediaType: type,
            title: title,
            posterPath: poster,
            overview: nil,
            voteAverage: nil,
            voteCount: nil,
            genreIds: [],
            releaseDate: year.map { "\($0)-01-01" },
            seasonCount: seasons
        )
    }

    private static let worstTitles: [MediaItem] = [
        title(935, "Docteur Folamour ou : comment j'ai appris à ne plus m'en faire et à aimer la bombe",
              .movie, year: "1964", poster: "/7SixLzxcqezsXDFAlGu1cv6vMAu.jpg"),
        title(999_001, "Dunes", .movie, year: nil, poster: nil),
        title(27_022, "Les Aventures extraordinaires d'Adèle Blanc-Sec", .movie, year: "2010", poster: nil),
        title(45_016, "Bron/Broen", .tv, year: "2011", poster: nil, seasons: 4),
        title(90_228, "Dune : Prophecy", .tv, year: "2024", poster: nil, seasons: 1),
        title(693_134, "Dune : Deuxième partie", .movie, year: "2024", poster: nil),
    ]
}
#endif
