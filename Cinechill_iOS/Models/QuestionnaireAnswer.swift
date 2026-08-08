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
        case .alone: "Seul(e)"
        case .couple: "En couple"
        case .friends: "Entre amis"
        case .family: "En famille (enfants)"
        }
    }
}

// MARK: - Q5 · Ambiance (score)

nonisolated enum Mood: String, QuestionOption {
    case lightFun, intense, emotional, scary, escapist, thoughtful

    var label: String {
        switch self {
        case .lightFun: "Léger & drôle"
        case .intense: "Intense & haletant"
        case .emotional: "Émotion & larmes"
        case .scary: "Frissons & peur"
        case .escapist: "Évasion & spectaculaire"
        case .thoughtful: "Réflexion & mystère"
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

// MARK: - Q7 · État d'esprit (score, surprise)

nonisolated enum Mindset: String, QuestionOption {
    case noThinking, beSurprised, seeMyself, learnSomething

    var label: String {
        switch self {
        case .noThinking: "Ne penser à rien"
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
        case .mainstream: "Grand public populaire"
        case .wellRatedKnown: "Bien noté et connu"
        case .hiddenGem: "Pépite à découvrir"
        case .any: "Peu importe"
        }
    }
}

// MARK: - Q10 · Casting (score)

nonisolated enum CastPreference: String, QuestionOption {
    case familiarFaces, any, discovery

    var label: String {
        switch self {
        case .familiarFaces: "Visages connus"
        case .any: "Peu importe"
        case .discovery: "Découverte"
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
        case .suspense: "Tension qui monte"
        case .visceral: "Sensations fortes"
        }
    }
}

nonisolated enum ComedyFlavor: String, QuestionOption {
    case family, edgy

    var label: String {
        switch self {
        case .family: "Familiale et bienveillante"
        case .edgy: "Plus corrosive"
        }
    }
}

nonisolated enum DramaFlavor: String, QuestionOption {
    case social, intimate

    var label: String {
        switch self {
        case .social: "Grande fresque"
        case .intimate: "Histoire intime"
        }
    }
}

// MARK: - Question projective (score)

nonisolated enum CognitiveMode: String, QuestionOption {
    case understand, feel

    var label: String {
        switch self {
        case .understand: "Comprendre"
        case .feel: "Ressentir"
        }
    }
}

// MARK: - Les arbitrages forcés
//
// Deux options, il faut trancher. Le refus du « peu importe » est délibéré : un
// dilemme produit un indice net là où une question ouverte produit du milieu.
// Ces deux-là visent l'ancrage et l'échelle — les deux axes que le cadran laisse
// volontairement ouverts, parce qu'ils relèvent du goût durable et non de la soirée.

nonisolated enum StoryOrigin: String, QuestionOption {
    case trueStory, onlyInCinema

    var label: String {
        switch self {
        case .trueStory: "Une histoire vraie"
        case .onlyInCinema: "Une histoire qui ne pourrait exister qu'au cinéma"
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
        case .weight: "Un poids dans la poitrine"
        case .smile: "Le sourire pendant deux jours"
        case .questions: "Des questions sans réponse"
        case .wantMore: "L'envie d'y retourner tout de suite"
        }
    }
}

/// Réponses collectées au fil du quiz CinéMatch. Sérialisé tel quel vers `getRecommendations` —
/// tout le mapping vers les paramètres TMDB (with_genres, mots-clés, seuils…) est fait côté backend.
nonisolated struct QuestionnaireAnswers: Equatable, Sendable {
    static let maxGenres = 2

    var contentFormat: ContentFormat?
    var genres: Set<Genre> = []
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
