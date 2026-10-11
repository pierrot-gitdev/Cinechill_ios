//
//  DebugFixtures.swift
//  Cinechill_iOS
//

#if DEBUG
import Foundation

/// Des données de test pour les profils à suivre, en Debug seulement.
///
/// Pas d'interrupteur à l'écran : on le pose dans le schéma Xcode, en argument
/// de lancement, `-debugData worst` ou `-debugData empty`. iOS range les
/// arguments de lancement dans `UserDefaults`, d'où la lecture ci-dessous. Sans
/// argument, tout passe par le serveur.
///
/// Le pire cas tient ce qu'on voit en vrai : un nom de trente caractères, un
/// pseudo au maximum de vingt, un profil sans nom, 0 et 1 pour les pluriels,
/// des diacritiques vietnamiens.
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
}
#endif
