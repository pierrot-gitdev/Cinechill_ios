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
/// `RecommendationClient.fetchRecommendations`, appelé hors MainActor).
nonisolated protocol QuestionOption: CaseIterable, Hashable, Identifiable, RawRepresentable, Sendable where RawValue == String {
    var label: String { get }
}

nonisolated extension QuestionOption {
    var id: String { rawValue }

    static var chipOptions: [ChipOption] {
        allCases.map { ChipOption(id: $0.rawValue, label: $0.label) }
    }
}

// MARK: - Q1 · Genres (filtre)

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
}

// MARK: - Q3 · Avec qui (filtre)

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

// MARK: - Q4 · Ambiance (score)

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

// MARK: - Q5 · Origine (score)

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

// MARK: - Q6 · État d'esprit (score, surprise)

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

// MARK: - Q7 · Décrocheur (filtre, surprise)

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

// MARK: - Q8 · Blockbuster ou pépite (score)

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

// MARK: - Q9 · Casting (score)

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

// MARK: - Q10 · Durée (score)

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

// MARK: - Q11 · Récent ou vintage (score)

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

/// Réponses collectées au fil du quiz CinéMatch. Sérialisé tel quel vers `getRecommendations` —
/// tout le mapping vers les paramètres TMDB (with_genres, mots-clés, seuils…) est fait côté backend.
nonisolated struct QuestionnaireAnswers: Equatable, Sendable {
    static let maxGenres = 3

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
}
