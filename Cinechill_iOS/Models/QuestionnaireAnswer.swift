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
        case .animated: String(localized: "contentFormat.animated", defaultValue: "Dessin animé", bundle: .app)
        case .liveAction: String(localized: "contentFormat.liveAction", defaultValue: "Film", bundle: .app)
        }
    }
}

// MARK: - Q2 · Genres (filtre)

nonisolated enum Genre: String, QuestionOption {
    /// L'ordre est celui des puces à l'écran, et il suit le volume de films
    /// réellement disponibles chez TMDB : on met devant ce qui a le plus de
    /// chances d'aboutir. `animation` et `documentary` n'y figurent plus.
    /// L'animation est déjà tranchée par `ContentFormat` à l'écran précédent ;
    /// le documentaire pesait 688 films au-dessus de cent votes, moins que
    /// n'importe quel genre resté dehors.
    ///
    /// `scifiFantasy` a été coupé en deux : la science-fiction et le
    /// fantastique répondent à des envies différentes, et les confondre
    /// obligeait à accepter l'un pour obtenir l'autre.
    case drama, comedy, thriller, action, romance, horror, crime, adventure, scifi, fantasy, family

    var label: String {
        switch self {
        case .drama: String(localized: "Drame", bundle: .app)
        case .comedy: String(localized: "Comédie", bundle: .app)
        case .thriller: String(localized: "Thriller", bundle: .app)
        case .action: String(localized: "Action", bundle: .app)
        case .romance: String(localized: "Romance", bundle: .app)
        case .horror: String(localized: "Horreur", bundle: .app)
        // TMDB nomme ce genre « Crime » en français ; l'application dit
        // « Policier », qui est le mot que les gens emploient. Le backend
        // écrit déjà la même chose dans les raisons du verdict.
        case .crime: String(localized: "Policier", bundle: .app)
        case .adventure: String(localized: "Aventure", bundle: .app)
        case .scifi: String(localized: "Science-fiction", bundle: .app)
        case .fantasy: String(localized: "Fantastique", bundle: .app)
        case .family: String(localized: "Familial", bundle: .app)
        }
    }

    /// Les identifiants TMDB derrière chaque slug, dupliqués à dessein depuis
    /// `GENRE_TMDB_IDS` côté backend — qui reste la source de vérité pour la
    /// requête. Le client n'en a besoin que pour une chose : vérifier qu'un genre
    /// qu'il s'apprête à déduire du cadran n'est pas un genre banni dans les
    /// réglages. Si la table backend change, garder celle-ci synchronisée.
    var tmdbIDs: Set<Int> {
        switch self {
        case .drama: [18]
        case .comedy: [35]
        case .thriller: [53]
        case .action: [28]
        case .romance: [10749]
        case .horror: [27]
        case .crime: [80]
        case .adventure: [12]
        case .scifi: [878]
        case .fantasy: [14]
        case .family: [10751]
        }
    }
}

// MARK: - Q4 · Avec qui (filtre)

nonisolated enum Audience: String, QuestionOption {
    case alone, couple, friends, family

    var label: String {
        switch self {
        case .alone: String(localized: "Seul·e", bundle: .app)
        case .couple: String(localized: "En couple", bundle: .app)
        case .friends: String(localized: "Entre amis", bundle: .app)
        case .family: String(localized: "En famille, avec des enfants", bundle: .app)
        }
    }
}

// MARK: - Q5 · Ambiance (score)

nonisolated enum Mood: String, QuestionOption {
    case lightFun, intense, emotional, scary, escapist, thoughtful

    var label: String {
        switch self {
        case .lightFun: String(localized: "Léger et drôle", bundle: .app)
        case .intense: String(localized: "Tendu, avec de l'action", bundle: .app)
        case .emotional: String(localized: "Émouvant", bundle: .app)
        case .scary: String(localized: "Qui fait peur", bundle: .app)
        case .escapist: String(localized: "Spectaculaire, qui fait voyager", bundle: .app)
        case .thoughtful: String(localized: "Qui fait réfléchir", bundle: .app)
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
        case .france: String(localized: "France", bundle: .app)
        case .unitedKingdom: String(localized: "Angleterre", bundle: .app)
        case .unitedStates: String(localized: "États-Unis", bundle: .app)
        case .japan: String(localized: "Japon", bundle: .app)
        case .elsewhere: String(localized: "Autre pays", bundle: .app)
        }
    }
}

// MARK: - Q7 · État d'esprit (score, surprise)

nonisolated enum Mindset: String, QuestionOption {
    case noThinking, beSurprised, seeMyself, learnSomething

    var label: String {
        switch self {
        case .noThinking: String(localized: "Me vider la tête", bundle: .app)
        case .beSurprised: String(localized: "Être surpris·e", bundle: .app)
        case .seeMyself: String(localized: "Me reconnaître dans l'histoire", bundle: .app)
        case .learnSomething: String(localized: "Apprendre quelque chose", bundle: .app)
        }
    }
}

// MARK: - Q8 · Décrocheur (filtre, surprise)

nonisolated enum Dealbreaker: String, QuestionOption {
    case slowPace, predictablePlot, tooLong, heavyMood

    var label: String {
        switch self {
        case .slowPace: String(localized: "Rythme trop lent", bundle: .app)
        case .predictablePlot: String(localized: "Scénario trop prévisible", bundle: .app)
        case .tooLong: String(localized: "Film trop long", bundle: .app)
        case .heavyMood: String(localized: "Ambiance trop lourde", bundle: .app)
        }
    }
}

// MARK: - Q9 · Blockbuster ou pépite (score)

/// Le « peu importe » a été retiré de ces deux questions, et c'est le même
/// raisonnement que pour les arbitrages forcés plus bas : une option qui ne
/// dépose aucun indice fait payer un écran pour rien. Elle était pire encore
/// ici, où elle était la valeur par défaut — la puce apparaissait déjà cochée,
/// et « Suivant » suffisait à brûler la question sans y répondre. Ces deux-là
/// ne sont posées que si elles valent la peine de l'être ; alors autant
/// qu'elles rapportent.
nonisolated enum PopularityPreference: String, QuestionOption {
    case mainstream, wellRatedKnown, hiddenGem

    var label: String {
        switch self {
        case .mainstream: String(localized: "Un grand succès", bundle: .app)
        case .wellRatedKnown: String(localized: "Un film reconnu", bundle: .app)
        case .hiddenGem: String(localized: "Un film peu connu", bundle: .app)
        }
    }
}

// MARK: - Q10 · Casting (score)

nonisolated enum CastPreference: String, QuestionOption {
    case familiarFaces, discovery

    var label: String {
        switch self {
        case .familiarFaces: String(localized: "Des acteurs que je connais", bundle: .app)
        case .discovery: String(localized: "Des visages nouveaux", bundle: .app)
        }
    }
}

// MARK: - Q11 · Durée (score)

nonisolated enum RuntimePreference: String, QuestionOption {
    case short, medium, long, any

    var label: String {
        switch self {
        case .short: String(localized: "< 1h30", bundle: .app)
        case .medium: String(localized: "1h30 – 2h", bundle: .app)
        case .long: String(localized: "2h +", bundle: .app)
        case .any: String(localized: "Peu importe", bundle: .app)
        }
    }
}

// MARK: - Nuances par genre (score) — seulement posées si le genre correspondant a été choisi

nonisolated enum HorrorFlavor: String, QuestionOption {
    case suspense, visceral

    var label: String {
        switch self {
        case .suspense: String(localized: "La tension qui monte lentement", bundle: .app)
        case .visceral: String(localized: "Les sensations fortes", bundle: .app)
        }
    }
}

nonisolated enum ComedyFlavor: String, QuestionOption {
    case family, edgy

    var label: String {
        switch self {
        case .family: String(localized: "Gentille, bon enfant", bundle: .app)
        case .edgy: String(localized: "Grinçante, qui ne s'interdit rien", bundle: .app)
        }
    }
}

nonisolated enum DramaFlavor: String, QuestionOption {
    case social, intimate

    var label: String {
        switch self {
        case .social: String(localized: "Une grande histoire, sur fond d'époque ou de société", bundle: .app)
        case .intimate: String(localized: "L'histoire de quelques personnes", bundle: .app)
        }
    }
}

// MARK: - Le rythme (score)

/// Le rythme était le seul des huit axes qu'aucune question ne visait
/// directement : il ne se lisait qu'en creux, dans un décrocheur (« rythme trop
/// lent ») et dans une nuance d'horreur. L'ambiance l'observe, mais faiblement,
/// et deux personnes qui demandent la même ambiance n'attendent pas la même
/// allure.
///
/// Les autres axes pauvres de la table n'ont pas eu droit au même traitement,
/// et c'est délibéré : l'ampleur est déjà tranchée par `AttachmentMode` (un
/// personnage ou un monde), le réalisme par `StoryOrigin` (une histoire vraie
/// ou inventée). Leur ajouter une question de plus aurait reposé la même
/// question deux fois.
nonisolated enum PaceWish: String, QuestionOption {
    case takeItsTime, neverLetsGo

    var label: String {
        switch self {
        case .takeItsTime: String(localized: "Qu'il prenne son temps", bundle: .app)
        case .neverLetsGo: String(localized: "Qu'il ne te lâche pas une seconde", bundle: .app)
        }
    }
}

// MARK: - Question projective (score)

nonisolated enum CognitiveMode: String, QuestionOption {
    case understand, feel

    var label: String {
        switch self {
        case .understand: String(localized: "Un film qui me fait réfléchir", bundle: .app)
        case .feel: String(localized: "Un film qui me fait ressentir", bundle: .app)
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
        case .trueStory: String(localized: "Une histoire vraie", bundle: .app)
        case .onlyInCinema: String(localized: "Une histoire complètement inventée", bundle: .app)
        }
    }
}

nonisolated enum AttachmentMode: String, QuestionOption {
    case character, world

    var label: String {
        switch self {
        case .character: String(localized: "Un personnage auquel s'attacher", bundle: .app)
        case .world: String(localized: "Un monde où se perdre", bundle: .app)
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
        case .silence: String(localized: "Personne ne parle pendant une minute", bundle: .app)
        case .discuss: String(localized: "Tu veux en parler tout de suite", bundle: .app)
        case .contentment: String(localized: "Tu es bien, c'est tout", bundle: .app)
        case .keepGoing: String(localized: "Tu enchaînes sur la suite", bundle: .app)
        }
    }
}

nonisolated enum LastingTrace: String, QuestionOption {
    case weight, smile, questions, wantMore

    var label: String {
        switch self {
        case .weight: String(localized: "Un poids, longtemps après", bundle: .app)
        case .smile: String(localized: "Le sourire pendant deux jours", bundle: .app)
        case .questions: String(localized: "Des questions sans réponse", bundle: .app)
        case .wantMore: String(localized: "L'envie d'en voir plus tout de suite", bundle: .app)
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
    /// L'ambiance a reçu une réponse — y compris « peu importe », qui laisse
    /// `mood` à nil. Jamais sérialisé : le backend lit l'absence d'ambiance
    /// dans `mood` lui-même, et le prior du trait fait alors le travail seul.
    var moodDecided = false
    var mindset: Mindset?
    var dealbreaker: Dealbreaker?
    var popularity: PopularityPreference?
    var cast: CastPreference?
    var runtime: RuntimePreference = .any
    /// La durée a-t-elle été choisie, ou seulement présélectionnée d'après
    /// l'heure ? Une présélection est une supposition : elle vaut moins qu'une
    /// réponse, et c'est `AnswerObservations.fromBudget` qui en tire les
    /// conséquences.
    var runtimeDecided = false
    var paceWish: PaceWish?
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

    /// Les genres exclus dans les réglages. Ils ne sont jamais demandés à TMDB
    /// (voir `availableGenres`) et le backend leur applique un malus.
    ///
    /// Il y avait ici un `preferredGenreIDs` jumeau, documenté comme alimenté
    /// par les duels et les éliminations. Il ne l'était nulle part, et son seul
    /// lecteur côté serveur était la formule de score de repli — celle qui ne
    /// s'exécute que si le client n'envoie pas de croyance, ce qu'il fait
    /// toujours. Le remplir aurait été décoratif ; il est parti, avec `origin`
    /// et `era` qui vivaient la même vie.
    var avoidedGenreIDs: Set<Int> = []
}
