//
//  DebugFixtures.swift
//  Cinechill_iOS
//

#if DEBUG
import Foundation

/// Des données de test pour la recherche, les profils à suivre et le départ
/// de CinéMatch, en Debug seulement.
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

    /// Les styles de CinéMatch. Le pire cas mêle un style à un seul film, un
    /// style à deux (une case reste vide), des affiches absentes, et quatre
    /// styles sans aucun film de la galerie sous « Un autre style ». Le vide
    /// rend les dix styles sans un film : une galerie qui n'a rien de classé.
    static func cineMatchStyles(format: MediaFormat) -> [CineMatchStyleTile]? {
        switch mode {
        case nil:
            return nil
        case .empty:
            return CineMatchStyle.allCases.map { CineMatchStyleTile(style: $0, count: 0, films: []) }
        case .worst:
            return [
                CineMatchStyleTile(style: .thriller, count: 48, films: Array(worstStarters.prefix(3))),
                CineMatchStyleTile(style: .scifi, count: 2, films: [worstStarters[6], worstStarters[7]]),
                CineMatchStyleTile(style: .drama, count: 31, films: [worstStarters[3], worstStarters[8], worstStarters[9]]),
                CineMatchStyleTile(style: .animation, count: 7, films: [worstStarters[10], worstStarters[11], worstStarters[2]]),
                CineMatchStyleTile(style: .history, count: 3, films: [worstStarters[12], worstStarters[2], worstStarters[13]]),
                CineMatchStyleTile(style: .comedy, count: 1, films: [worstStarters[9]]),
                CineMatchStyleTile(style: .action, count: 0, films: []),
                CineMatchStyleTile(style: .romance, count: 0, films: []),
                CineMatchStyleTile(style: .horror, count: 0, films: []),
                CineMatchStyleTile(style: .documentary, count: 0, films: []),
            ]
        }
    }

    /// Les films de départ d'un style. Le pire cas : un titre de
    /// quatre-vingts caractères, un titre d'un mot, une affiche absente, une
    /// seconde page de quatre films seulement, et un style d'un seul film
    /// (« Pas ceux-là » n'a alors rien à montrer). Le vide : aucun film.
    static func cineMatchStarters(style: CineMatchStyle, page: Int, format: MediaFormat) -> CineMatchStarterPage? {
        switch mode {
        case nil:
            return nil
        case .empty:
            return CineMatchStarterPage(style: style, page: 0, films: [], hasMore: false)
        case .worst:
            if style == .comedy {
                return CineMatchStarterPage(style: style, page: 0, films: [worstStarters[9]], hasMore: false)
            }
            let current = page % 2
            let films = current == 0 ? Array(worstStarters.prefix(6)) : Array(worstStarters[6 ..< 10])
            return CineMatchStarterPage(style: style, page: current, films: films, hasMore: true)
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

    private static func starter(_ id: Int, _ title: String, poster: String?, genres: [Int]) -> CineMatchGalleryFilm {
        CineMatchGalleryFilm(id: id, title: title, posterPath: poster, releaseDate: nil, genreIDs: genres)
    }

    private static let worstStarters: [CineMatchGalleryFilm] = [
        starter(935, "Docteur Folamour ou : comment j'ai appris à ne plus m'en faire et à aimer la bombe",
                poster: "/7SixLzxcqezsXDFAlGu1cv6vMAu.jpg", genres: [35, 10752]),
        starter(949, "Heat", poster: "/umSVjVdbVwtx5ryCA2QXL44Durm.jpg", genres: [80, 18, 28]),
        starter(999_002, "Les Aventures extraordinaires d'Adèle Blanc-Sec", poster: nil, genres: [12, 14]),
        starter(146_233, "Prisoners", poster: "/uhviyknTT5cEQXbn6vWIqfM4vGm.jpg", genres: [18, 53, 80]),
        starter(807, "Se7en", poster: "/191nKfP0ehp3uIvWqgPbFmI4lv9.jpg", genres: [80, 9648, 53]),
        starter(11_423, "Memories of Murder", poster: "/jcgUjx1QcupGzjntTVlnQ15lHqy.jpg", genres: [80, 18, 53]),
        starter(157_336, "Interstellar", poster: "/yQvGrMoipbRoddT0ZR8tPoR7NfX.jpg", genres: [12, 18, 878]),
        starter(832, "M", poster: nil, genres: [80, 53]),
        starter(64_690, "Drive", poster: "/602vevIURmpDfzbnv5Ubi6wIkQm.jpg", genres: [18, 53, 80]),
        starter(112_198, "Le Prénom", poster: "/5xKkDkv506CiSp99SxmHLsnaoFs.jpg", genres: [35]),
        starter(129, "Le Voyage de Chihiro", poster: "/39wmItIWsg5sZMyRUHLkWBcuVCM.jpg", genres: [16, 10751, 14]),
        starter(999_004, "Ernest et Célestine : le voyage en Charabie", poster: nil, genres: [16, 10751]),
        starter(999_005, "Nguyễn Trãi và Những Ngày Tháng Cuối Cùng Của Đời Ông", poster: nil, genres: [36, 10752]),
        starter(999_006, "1917", poster: nil, genres: [10752, 36]),
    ]

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
