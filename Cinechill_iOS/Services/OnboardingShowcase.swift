//
//  OnboardingShowcase.swift
//  Cinechill_iOS
//

import Foundation

/// Les films d'exemple de la prise en main.
///
/// Un compte qui vient d'être créé a une galerie vide et une watchlist vide :
/// deux étapes sur six se joueraient donc sur des écrans qui ne montrent rien,
/// et présenter « votre collection » devant un état vide n'explique rien du
/// tout. Ces quatorze titres remplissent les écrans le temps de la visite.
///
/// Trois décisions les gouvernent :
///
/// - **Des films que tout le monde connaît**, choisis pour ça et pour rien
///   d'autre. On ne recommande pas ici, on illustre : un titre qu'il faut
///   reconnaître avant de comprendre l'écran est un titre raté.
/// - **Étalés sur cinq décennies.** La galerie se range par décennie et la
///   taille des affiches encode le volume de chaque bande — un exemple
///   concentré sur trois ans donnerait une frise plate, c'est-à-dire une
///   démonstration qui contredit ce qu'elle démontre.
/// - **Rien n'est écrit nulle part.** Ces entrées ne passent ni par
///   `LibraryStore`, ni par Firestore : elles n'existent que dans la vue, le
///   temps de l'étape. La visite ne laisse aucune trace dans la bibliothèque.
///
/// Les titres sont localisés comme le reste de l'application — un film porte un
/// nom différent en français et en anglais, et l'exemple perdrait sa raison
/// d'être s'il fallait le reconnaître dans l'autre langue.
///
/// ⚠️ Les chemins d'affiche sont ceux de TMDB à la date d'écriture. S'il en
/// manque un, `PosterTile` retombe sur le titre posé sur une vignette de nuit :
/// l'écran reste juste, il perd seulement son image.
/// Isolée au `MainActor` — c'est-à-dire non annotée, l'isolation par défaut du
/// projet. `GalleryEntry` et `WatchlistEntry` le sont aussi, et leurs
/// initialiseurs ne sont donc pas appelables depuis un contexte `nonisolated`.
/// La contrainte tombe d'elle-même : cette vitrine n'est lue que par des vues.
enum OnboardingShowcase {

    /// **Tout est calculé, jamais `static let`.** Une propriété statique n'est
    /// initialisée qu'une fois par processus : les titres y seraient résolus au
    /// premier accès et n'en bougeraient plus. Changer de langue reconstruit
    /// bien la hiérarchie de vues, mais la mémoire d'un `static` survit à cette
    /// reconstruction — les exemples resteraient dans la langue du tout premier
    /// affichage. C'est exactement le défaut qu'avait la barre d'onglets.
    ///
    /// Seule exception, et elle ne dépend d'aucune langue : l'instant de
    /// référence des dates d'ajout. Le figer est même nécessaire — des entrées
    /// reconstruites avec une date neuve à chaque lecture ne seraient jamais
    /// égales à elles-mêmes, et la galerie se rebâtirait à chaque image.
    private static let epoch = Date.now

    /// Un film d'exemple, réduit à ce que les trois écrans affichent.
    struct Film {
        let tmdbID: Int
        let title: String
        let posterPath: String
        let year: String
        let genreIDs: [Int]
        let voteAverage: Double
        let voteCount: Int
        let overview: String?
    }

    // MARK: - La galerie

    /// Huit films, du plus récent au plus ancien. La frise en tire quatre
    /// bandes de volumes très différents — 2010, 2000, 1990, 1970 — donc quatre
    /// tailles d'affiche : c'est la mise en page qui devient le graphique, et
    /// c'est précisément ce que l'étape a à montrer.
    static var galleryFilms: [Film] { [
        Film(tmdbID: 157336, title: String(localized: "Interstellar", bundle: .app),
             posterPath: "/gEU2QniE6E77NI6lCU6MxlNBvIx.jpg", year: "2014-11-05",
             genreIDs: [878, 12, 18], voteAverage: 8.4, voteCount: 35_000, overview: nil),
        Film(tmdbID: 27205, title: String(localized: "Inception", bundle: .app),
             posterPath: "/9gk7adGmEUnbnP4mvWJTnj2G4jI.jpg", year: "2010-07-16",
             genreIDs: [28, 878, 12], voteAverage: 8.4, voteCount: 36_000, overview: nil),
        Film(tmdbID: 120, title: String(localized: "Le Seigneur des anneaux : La Communauté de l'anneau", bundle: .app),
             posterPath: "/6oom5QYQ2yQTMJIbnvbkBL9cHo6.jpg", year: "2001-12-19",
             genreIDs: [12, 14, 28], voteAverage: 8.4, voteCount: 25_000, overview: nil),
        Film(tmdbID: 603, title: String(localized: "Matrix", bundle: .app),
             posterPath: "/f89U3ADr1oiB1s9GkdPOEpXUk5H.jpg", year: "1999-03-31",
             genreIDs: [28, 878], voteAverage: 8.2, voteCount: 25_000, overview: nil),
        Film(tmdbID: 597, title: String(localized: "Titanic", bundle: .app),
             posterPath: "/9xjZS2rlVxm8SFx8kPC3aIGCOYQ.jpg", year: "1997-11-18",
             genreIDs: [18, 10749], voteAverage: 7.9, voteCount: 24_000, overview: nil),
        Film(tmdbID: 680, title: String(localized: "Pulp Fiction", bundle: .app),
             posterPath: "/d5iIlFn5s0ImszYzBPb8JPIfbXD.jpg", year: "1994-09-10",
             genreIDs: [53, 80], voteAverage: 8.5, voteCount: 27_000, overview: nil),
        Film(tmdbID: 8587, title: String(localized: "Le Roi lion", bundle: .app),
             posterPath: "/sKCr78MXSLixwmZ8DyJLrpMsd15.jpg", year: "1994-06-24",
             genreIDs: [16, 18, 10751], voteAverage: 8.3, voteCount: 17_000, overview: nil),
        Film(tmdbID: 238, title: String(localized: "Le Parrain", bundle: .app),
             posterPath: "/3bhkrj58Vtu7enYsRolD1fZdja1.jpg", year: "1972-03-14",
             genreIDs: [18, 80], voteAverage: 8.7, voteCount: 20_000, overview: nil),
    ] }

    /// Les entrées de galerie correspondantes.
    ///
    /// Les dates d'ajout sont échelonnées de trois jours à partir d'`epoch` :
    /// la signature affiche « + N ce mois », et une date gravée à la
    /// compilation la ferait mentir un peu plus chaque semaine.
    static var gallery: [GalleryEntry] {
        galleryFilms.enumerated().map { index, film in
            GalleryEntry(
                id: "showcase-\(film.tmdbID)",
                tmdbId: film.tmdbID,
                mediaType: .movie,
                title: film.title,
                posterPath: film.posterPath,
                overview: film.overview,
                voteAverage: film.voteAverage,
                genreIds: film.genreIDs,
                releaseDate: film.year,
                addedAt: epoch.addingTimeInterval(-Double(index) * 3 * 86_400)
            )
        }
    }

    // MARK: - La watchlist

    /// Trois films seulement : la watchlist se lit d'un coup d'œil, et une
    /// liste d'exemple qui déborde de l'écran ne montrerait plus le tri par
    /// temps disponible, qui est tout ce que l'étape a à dire.
    static var watchlistFilms: [Film] { [
        Film(tmdbID: 438631, title: String(localized: "Dune", bundle: .app),
             posterPath: "/d5NXSklXo0qyIYkgV94XAgMIckC.jpg", year: "2021-09-15",
             genreIDs: [878, 12], voteAverage: 7.8, voteCount: 11_000, overview: nil),
        Film(tmdbID: 496243, title: String(localized: "Parasite", bundle: .app),
             posterPath: "/7IiTTgloJzvGI1TAYymCfbfl3vT.jpg", year: "2019-05-30",
             genreIDs: [35, 53, 18], voteAverage: 8.5, voteCount: 17_000, overview: nil),
        Film(tmdbID: 329, title: String(localized: "Jurassic Park", bundle: .app),
             posterPath: "/oU7Oq2kFAAlGqbU4VoAE36g4hoI.jpg", year: "1993-06-11",
             genreIDs: [12, 878], voteAverage: 8.0, voteCount: 15_000, overview: nil),
    ] }

    static var watchlist: [WatchlistEntry] {
        watchlistFilms.enumerated().map { index, film in
            WatchlistEntry(
                id: "showcase-\(film.tmdbID)",
                tmdbId: film.tmdbID,
                mediaType: .movie,
                title: film.title,
                posterPath: film.posterPath,
                overview: film.overview,
                voteAverage: film.voteAverage,
                genreIds: film.genreIDs,
                releaseDate: film.year,
                addedAt: epoch.addingTimeInterval(-Double(index) * 86_400),
                recommendedBy: []
            )
        }
    }

    // MARK: - Le deck

    /// Trois cartes : celle du dessus et les deux qu'on voit dépasser dessous.
    /// Le deck n'en montre jamais davantage.
    ///
    /// Le synopsis est renseigné ici, à la différence des deux autres écrans :
    /// la plaque de la carte affiche une poignée « Résumé » qui n'apparaît que
    /// s'il y a quelque chose à déplier, et une carte d'exemple sans elle ne
    /// serait pas la carte qu'on aura.
    static var deck: [SwipeCard] { [
        SwipeCard(
            tmdbId: 105,
            title: String(localized: "Retour vers le futur", bundle: .app),
            posterPath: "/vN5B5WgYscRGcQpVhHl6p9DDTP0.jpg",
            overview: String(localized: "Marty McFly, 17 ans, est propulsé trente ans en arrière par la machine à voyager dans le temps d'un savant excentrique. Il y croise ses parents adolescents et compromet sans le vouloir leur rencontre.", bundle: .app),
            voteAverage: 8.3,
            voteCount: 20_000,
            genreIds: [12, 35, 878],
            releaseDate: "1985-07-03",
            source: "showcase"
        ),
        SwipeCard(
            tmdbId: 550,
            title: String(localized: "Fight Club", bundle: .app),
            posterPath: "/pB8BM7pdSp6B6Ih7QZ4DrQ3PmJK.jpg",
            overview: nil,
            voteAverage: 8.4,
            voteCount: 29_000,
            genreIds: [18, 53],
            releaseDate: "1999-10-15",
            source: "showcase"
        ),
        SwipeCard(
            tmdbId: 13,
            title: String(localized: "Forrest Gump", bundle: .app),
            posterPath: "/arw2vcBveWOVZr6pxd9XTd1TdQa.jpg",
            overview: nil,
            voteAverage: 8.5,
            voteCount: 27_000,
            genreIds: [35, 18, 10749],
            releaseDate: "1994-06-23",
            source: "showcase"
        ),
    ] }
}
