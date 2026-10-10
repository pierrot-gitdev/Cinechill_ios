//
//  OnboardingFilms.swift
//  Cinechill_iOS
//

import Foundation

/// Un film montré par l'onboarding. Rien n'est écrit nulle part : ni la
/// bibliothèque ni Firestore ne voient ces films.
nonisolated struct OnboardingFilm: Identifiable, Hashable, Sendable {
    let id: Int
    let title: String
    let year: Int
    let genre: String
    let posterPath: String
    var runtimeMinutes: Int?

    /// La taille du mur et de la carte de démonstration : à 3x, une affiche
    /// d'un tiers d'écran demande à peine plus de 342 pixels de large.
    var posterURL: URL? { URL(string: "https://image.tmdb.org/t/p/w342\(posterPath)") }

    /// La carte de Découvrir, pour l'écran des gestes : la vraie, pas une
    /// imitation. Elle ne passe jamais par le deck.
    var swipeCard: SwipeCard {
        SwipeCard(
            tmdbId: id,
            title: title,
            posterPath: posterPath,
            overview: nil,
            voteAverage: nil,
            voteCount: nil,
            genreIds: [],
            releaseDate: "\(year)-01-01",
            source: "onboarding"
        )
    }
}

/// Des films que presque tout le monde a vus, sur cinq décennies.
///
/// Les chemins d'affiche ont été vérifiés un à un sur le serveur d'images de
/// TMDB le 11 octobre 2026. Tout est calculé, jamais `static let` : les titres
/// et les genres se traduisent, et une valeur statique figerait la langue du
/// premier affichage.
enum OnboardingFilms {
    static var interstellar: OnboardingFilm {
        OnboardingFilm(id: 157336, title: String(localized: "Interstellar", bundle: .app), year: 2014,
                       genre: String(localized: "Science-fiction", bundle: .app), posterPath: "/gEU2QniE6E77NI6lCU6MxlNBvIx.jpg")
    }

    static var inception: OnboardingFilm {
        OnboardingFilm(id: 27205, title: String(localized: "Inception", bundle: .app), year: 2010,
                       genre: String(localized: "Science-fiction", bundle: .app), posterPath: "/oYuLEt3zVCKq57qu2F8dT7NIa6f.jpg",
                       runtimeMinutes: 148)
    }

    static var lordOfTheRings: OnboardingFilm {
        OnboardingFilm(id: 120, title: String(localized: "Le Seigneur des anneaux : La Communauté de l'anneau", bundle: .app), year: 2001,
                       genre: String(localized: "Aventure", bundle: .app), posterPath: "/6oom5QYQ2yQTMJIbnvbkBL9cHo6.jpg")
    }

    static var matrix: OnboardingFilm {
        OnboardingFilm(id: 603, title: String(localized: "Matrix", bundle: .app), year: 1999,
                       genre: String(localized: "Science-fiction", bundle: .app), posterPath: "/f89U3ADr1oiB1s9GkdPOEpXUk5H.jpg")
    }

    static var titanic: OnboardingFilm {
        OnboardingFilm(id: 597, title: String(localized: "Titanic", bundle: .app), year: 1997,
                       genre: String(localized: "Romance", bundle: .app), posterPath: "/9xjZS2rlVxm8SFx8kPC3aIGCOYQ.jpg")
    }

    static var pulpFiction: OnboardingFilm {
        OnboardingFilm(id: 680, title: String(localized: "Pulp Fiction", bundle: .app), year: 1994,
                       genre: String(localized: "Policier", bundle: .app), posterPath: "/d5iIlFn5s0ImszYzBPb8JPIfbXD.jpg")
    }

    static var lionKing: OnboardingFilm {
        OnboardingFilm(id: 8587, title: String(localized: "Le Roi lion", bundle: .app), year: 1994,
                       genre: String(localized: "Animation", bundle: .app), posterPath: "/sKCr78MXSLixwmZ8DyJLrpMsd15.jpg")
    }

    static var godfather: OnboardingFilm {
        OnboardingFilm(id: 238, title: String(localized: "Le Parrain", bundle: .app), year: 1972,
                       genre: String(localized: "Drame", bundle: .app), posterPath: "/3bhkrj58Vtu7enYsRolD1fZdja1.jpg")
    }

    static var dune: OnboardingFilm {
        OnboardingFilm(id: 438631, title: String(localized: "Dune", bundle: .app), year: 2021,
                       genre: String(localized: "Science-fiction", bundle: .app), posterPath: "/d5NXSklXo0qyIYkgV94XAgMIckC.jpg")
    }

    static var parasite: OnboardingFilm {
        OnboardingFilm(id: 496243, title: String(localized: "Parasite", bundle: .app), year: 2019,
                       genre: String(localized: "Thriller", bundle: .app), posterPath: "/7IiTTgloJzvGI1TAYymCfbfl3vT.jpg")
    }

    static var jurassicPark: OnboardingFilm {
        OnboardingFilm(id: 329, title: String(localized: "Jurassic Park", bundle: .app), year: 1993,
                       genre: String(localized: "Aventure", bundle: .app), posterPath: "/oU7Oq2kFAAlGqbU4VoAE36g4hoI.jpg")
    }

    static var backToTheFuture: OnboardingFilm {
        OnboardingFilm(id: 105, title: String(localized: "Retour vers le futur", bundle: .app), year: 1985,
                       genre: String(localized: "Aventure", bundle: .app), posterPath: "/vN5B5WgYscRGcQpVhHl6p9DDTP0.jpg")
    }

    static var fightClub: OnboardingFilm {
        OnboardingFilm(id: 550, title: String(localized: "Fight Club", bundle: .app), year: 1999,
                       genre: String(localized: "Drame", bundle: .app), posterPath: "/pB8BM7pdSp6B6Ih7QZ4DrQ3PmJK.jpg")
    }

    static var forrestGump: OnboardingFilm {
        OnboardingFilm(id: 13, title: String(localized: "Forrest Gump", bundle: .app), year: 1994,
                       genre: String(localized: "Drame", bundle: .app), posterPath: "/arw2vcBveWOVZr6pxd9XTd1TdQa.jpg")
    }

    /// Le mur de l'accueil, colonne par colonne. Trois colonnes de quatre ou
    /// cinq affiches, chacune doublée à l'affichage pour boucler sans couture.
    static var wallColumns: [[OnboardingFilm]] {
        [
            [godfather, matrix, parasite, backToTheFuture, interstellar],
            [pulpFiction, dune, titanic, fightClub, lordOfTheRings],
            [lionKing, inception, jurassicPark, forrestGump],
        ]
    }

    /// Le film de l'écran CinéMatch.
    static var tonight: OnboardingFilm { inception }

    /// Les cartes de l'écran des gestes, dans l'ordre où elles passent.
    static var gestureDeck: [OnboardingFilm] {
        [backToTheFuture, titanic, lionKing, forrestGump, fightClub]
    }
}
