//
//  QuestionnaireAnswer.swift
//  Cinechill_iOS
//

import Foundation

/// Un choix affichable sous forme de chip dans le quiz CinéMatch.
nonisolated struct ChipOption: Identifiable, Hashable, Sendable {
    let id: String
    let label: String
}

/// Enum de réponse pour une question à choix (un cas par chip). `rawValue` sert d'identifiant
/// stable envoyé au backend — le mapping vers les paramètres TMDB (with_genres, mots-clés…)
/// reste entièrement côté Cloud Function, jamais sur le client.
///
/// Marqué `nonisolated` (comme chaque type conforme) car le projet a `SWIFT_DEFAULT_ACTOR_ISOLATION
/// = MainActor` : sans ça, ces types de données purs hériteraient de l'isolation MainActor et ne
/// pourraient plus satisfaire `Sendable`, requis pour traverser les frontières d'acteurs (ex.
/// `BackendRecommendationClient`, appelé hors MainActor).
nonisolated protocol QuestionOption: CaseIterable, Hashable, Identifiable, RawRepresentable, Sendable where RawValue == String {
    var label: String { get }
}

nonisolated extension QuestionOption {
    var id: String { rawValue }

    static var chipOptions: [ChipOption] {
        allCases.map { ChipOption(id: $0.rawValue, label: $0.label) }
    }
}

// MARK: - Q1 · Dessin animé ou film (filtre)

nonisolated enum ContentFormat: String, QuestionOption {
    case animated, liveAction

    /// L'opposition n'est pas logique — un dessin animé est un film — mais c'est
    /// celle que tout le monde emploie, et elle se comprend sans y penser. Les
    /// formulations exactes essayées ici (« un film avec de vrais acteurs »)
    /// demandaient plus d'attention qu'elles n'en faisaient gagner.
    var label: String {
        switch self {
        case .animated: "Dessin animé"
        case .liveAction: "Film"
        }
    }
}

// MARK: - Q2 · Genres (filtre)

nonisolated enum Genre: String, QuestionOption {
    case action, comedy, drama, thriller, scifiFantasy, horror, romance, animation, documentary

    var label: String {
        switch self {
        case .action: "Action"
        case .comedy: "Comédie"
        case .drama: "Drame"
        case .thriller: "Thriller"
        case .scifiFantasy: "SF / Fantastique"
        case .horror: "Horreur"
        case .romance: "Romance"
        case .animation: "Animation"
        case .documentary: "Documentaire"
        }
    }

    /// Les identifiants TMDB derrière chaque slug, dupliqués à dessein depuis
    /// `GENRE_TMDB_IDS` côté backend — qui reste la source de vérité pour la
    /// requête. Le client n'en a besoin que pour une chose : vérifier qu'un genre
    /// qu'il s'apprête à déduire du cadran n'est pas un genre banni dans les
    /// réglages. Si la table backend change, garder celle-ci synchronisée.
    var tmdbIDs: Set<Int> {
        switch self {
        case .action: [28]
        case .comedy: [35]
        case .drama: [18]
        case .thriller: [53]
        case .scifiFantasy: [878, 14]
        case .horror: [27]
        case .romance: [10749]
        case .animation: [16]
        case .documentary: [99]
        }
    }
}

// MARK: - Q4 · Avec qui (filtre)

nonisolated enum Audience: String, QuestionOption {
    case alone, couple, friends, family

    var label: String {
        switch self {
        case .alone: "Seul·e"
        case .couple: "En couple"
        case .friends: "Entre amis"
        case .family: "En famille, avec des enfants"
        }
    }
}

// MARK: - Q5 · Ambiance (score)

nonisolated enum Mood: String, QuestionOption {
    case lightFun, intense, emotional, scary, escapist, thoughtful

    var label: String {
        switch self {
        case .lightFun: "Léger et drôle"
        case .intense: "Tendu, avec de l'action"
        case .emotional: "Émouvant"
        case .scary: "Qui fait peur"
        case .escapist: "Spectaculaire, qui fait voyager"
        case .thoughtful: "Qui fait réfléchir"
        }
    }
}

// MARK: - Q6 · Origine (score)

nonisolated enum OriginPreference: String, QuestionOption {
    case french, international, any

    var label: String {
        switch self {
        case .french: "Français"
        case .international: "International"
        case .any: "Peu importe"
        }
    }
}

// MARK: - Origine du film (filtre)

/// D'où vient le film : les quatre pays qui pèsent le plus dans ce qui se
/// regarde en France, plus un « ailleurs » qui couvre tout le reste du monde.
///
/// `elsewhere` n'est pas un pays mais un complément, et c'est ce qui le rend
/// particulier : TMDB ne sait pas exprimer « tous les pays sauf ceux-là ». La
/// requête l'approche en interrogeant les grandes cinématographies hors de ces
/// quatre-là, et c'est un filtre serveur qui garantit ensuite l'exactitude —
/// voir `matchesRequestedOrigins` côté backend.
nonisolated enum OriginCountry: String, QuestionOption {
    case france, unitedKingdom, unitedStates, japan, elsewhere

    var label: String {
        switch self {
        case .france: "France"
        case .unitedKingdom: "Angleterre"
        case .unitedStates: "États-Unis"
        case .japan: "Japon"
        case .elsewhere: "Autre pays"
        }
    }
}

// MARK: - Q7 · État d'esprit (score, surprise)

nonisolated enum Mindset: String, QuestionOption {
    case noThinking, beSurprised, seeMyself, learnSomething

    var label: String {
        switch self {
        case .noThinking: "Me vider la tête"
        case .beSurprised: "Être surpris·e"
        case .seeMyself: "Me reconnaître dans l'histoire"
        case .learnSomething: "Apprendre quelque chose"
        }
    }
}

// MARK: - Q8 · Décrocheur (filtre, surprise)

nonisolated enum Dealbreaker: String, QuestionOption {
    case slowPace, predictablePlot, tooLong, heavyMood

    var label: String {
        switch self {
        case .slowPace: "Rythme trop lent"
        case .predictablePlot: "Scénario trop prévisible"
        case .tooLong: "Film trop long"
        case .heavyMood: "Ambiance trop lourde"
        }
    }
}

// MARK: - Q9 · Blockbuster ou pépite (score)

nonisolated enum PopularityPreference: String, QuestionOption {
    case mainstream, wellRatedKnown, hiddenGem, any

    var label: String {
        switch self {
        case .mainstream: "Un grand succès"
        case .wellRatedKnown: "Un film reconnu"
        case .hiddenGem: "Un film peu connu"
        case .any: "Peu importe"
        }
    }
}

// MARK: - Q10 · Casting (score)

nonisolated enum CastPreference: String, QuestionOption {
    case familiarFaces, any, discovery

    var label: String {
        switch self {
        case .familiarFaces: "Des acteurs que je connais"
        case .any: "Peu importe"
        case .discovery: "Des visages nouveaux"
        }
    }
}

// MARK: - Q11 · Durée (score)

nonisolated enum RuntimePreference: String, QuestionOption {
    case short, medium, long, any

    var label: String {
        switch self {
        case .short: "< 1h30"
        case .medium: "1h30 – 2h"
        case .long: "2h +"
        case .any: "Peu importe"
        }
    }
}

// MARK: - Q12 · Récent ou vintage (score)

nonisolated enum EraPreference: String, QuestionOption {
    case thisYear, lastFiveYears, any, cultClassic

    var label: String {
        switch self {
        case .thisYear: "Sorti cette année"
        case .lastFiveYears: "5 dernières années"
        case .any: "Peu importe l'époque"
        case .cultClassic: "Classique culte"
        }
    }
}

// MARK: - Nuances par genre (score) — seulement posées si le genre correspondant a été choisi

nonisolated enum HorrorFlavor: String, QuestionOption {
    case suspense, visceral

    var label: String {
        switch self {
        case .suspense: "La tension qui monte lentement"
        case .visceral: "Les sensations fortes"
        }
    }
}

nonisolated enum ComedyFlavor: String, QuestionOption {
    case family, edgy

    var label: String {
        switch self {
        case .family: "Gentille, bon enfant"
        case .edgy: "Grinçante, qui ne s'interdit rien"
        }
    }
}

nonisolated enum DramaFlavor: String, QuestionOption {
    case social, intimate

    var label: String {
        switch self {
        case .social: "Une grande histoire, sur fond d'époque ou de société"
        case .intimate: "L'histoire de quelques personnes"
        }
    }
}

// MARK: - Question projective (score)

nonisolated enum CognitiveMode: String, QuestionOption {
    case understand, feel

    var label: String {
        switch self {
        case .understand: "Un film qui me fait réfléchir"
        case .feel: "Un film qui me fait ressentir"
        }
    }
}

// MARK: - Les arbitrages forcés
//
// Deux options, il faut trancher. Le refus du « peu importe » est délibéré : un
// dilemme produit un indice net là où une question ouverte produit du milieu.
// Ces deux-là visent le réalisme et l'ampleur — les deux axes que l'écran
// d'humeur laisse volontairement ouverts, parce qu'ils relèvent du goût durable
// et non de la soirée.

nonisolated enum StoryOrigin: String, QuestionOption {
    case trueStory, onlyInCinema

    var label: String {
        switch self {
        case .trueStory: "Une histoire vraie"
        case .onlyInCinema: "Une histoire complètement inventée"
        }
    }
}

nonisolated enum AttachmentMode: String, QuestionOption {
    case character, world

    var label: String {
        switch self {
        case .character: "Un personnage auquel s'attacher"
        case .world: "Un monde où se perdre"
        }
    }
}

// MARK: - La projection et la trace
//
// On fait imaginer l'après-film plutôt que le film, et on interroge la mémoire
// plutôt que l'intention : les gens se connaissent mieux au passé qu'au futur.

nonisolated enum CreditsMoment: String, QuestionOption {
    case silence, discuss, contentment, keepGoing

    var label: String {
        switch self {
        case .silence: "Personne ne parle pendant une minute"
        case .discuss: "Vous voulez en parler tout de suite"
        case .contentment: "Vous êtes bien, c'est tout"
        case .keepGoing: "Vous enchaînez sur la suite"
        }
    }
}

nonisolated enum LastingTrace: String, QuestionOption {
    case weight, smile, questions, wantMore

    var label: String {
        switch self {
        case .weight: "Un poids, longtemps après"
        case .smile: "Le sourire pendant deux jours"
        case .questions: "Des questions sans réponse"
        case .wantMore: "L'envie d'en voir plus tout de suite"
        }
    }
}

/// Réponses collectées au fil du quiz CinéMatch. Sérialisé tel quel vers `getRecommendations` —
/// tout le mapping vers les paramètres TMDB (with_genres, mots-clés, seuils…) est fait côté backend.
nonisolated struct QuestionnaireAnswers: Equatable, Sendable {
    static let maxGenres = 2
    /// Trois origines sur cinq, c'est le dernier cran où la réponse dit encore
    /// quelque chose : au-delà on n'exclut plus qu'une catégorie, et la question
    /// ne trie plus rien. Ne rien cocher vaut « peu importe ».
    static let maxOriginCountries = 3

    var contentFormat: ContentFormat?
    var genres: Set<Genre> = []
    var originCountries: Set<OriginCountry> = []
    var platformIDs: Set<String> = []
    var audience: Audience?
    var mood: Mood?
    var origin: OriginPreference = .any
    var mindset: Mindset?
    var dealbreaker: Dealbreaker?
    var popularity: PopularityPreference = .any
    var cast: CastPreference = .any
    var runtime: RuntimePreference = .any
    var era: EraPreference = .any
    var horrorFlavor: HorrorFlavor?
    var comedyFlavor: ComedyFlavor?
    var dramaFlavor: DramaFlavor?
    var cognitiveMode: CognitiveMode?
    var storyOrigin: StoryOrigin?
    var attachment: AttachmentMode?
    var creditsMoment: CreditsMoment?
    var lastingTrace: LastingTrace?

    /// 0 = valeurs sûres, 1 = surprise totale. Curseur continu plutôt qu'un choix à puces — voir
    /// `IntensitySliderView` — pour capturer une intensité plutôt qu'une catégorie.
    var surpriseIntensity: Double = 0.5

    /// Alimentés par les comparaisons directes entre affiches (voir `PairwiseComparisonView`) et
    /// par l'élimination (voir `EliminationView`) — les genres des films choisis/écartés, agrégés
    /// au fil du quiz. Contribue un léger boost/malus au score final côté backend, en plus (pas en
    /// remplacement) de `mood`.
    var preferredGenreIDs: Set<Int> = []
    var avoidedGenreIDs: Set<Int> = []
}
