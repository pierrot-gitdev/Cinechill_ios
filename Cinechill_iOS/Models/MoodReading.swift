//
//  MoodReading.swift
//  Cinechill_iOS
//

import Foundation

/// Un point d'humeur sur le cadran — deux dimensions, pas six étiquettes.
///
/// `valence` va du désagréable (−1) à l'agréable (+1), `activation` du calme (−1)
/// à l'activé (+1). C'est le modèle circumplexe de l'affect : deux axes suffisent
/// à situer un état là où une liste d'adjectifs se recouvre et se rate.
nonisolated struct MoodPoint: Equatable, Hashable, Sendable {
    var valence: Double
    var activation: Double

    static let neutral = MoodPoint(valence: 0, activation: 0)

    init(valence: Double, activation: Double) {
        self.valence = min(1, max(-1, valence))
        self.activation = min(1, max(-1, activation))
    }
}

/// Le trajet demandé pour la soirée : où l'on est, où l'on veut finir.
///
/// C'est la pièce que le questionnaire précédent ne savait pas exprimer. Deux
/// personnes rentrent tristes le même soir : l'une veut un film qui reste avec
/// elle, l'autre veut en sortir. Même point de départ, recommandations opposées —
/// seul le vecteur les distingue.
nonisolated struct MoodTrajectory: Equatable, Hashable, Sendable {
    var now: MoodPoint
    var goal: MoodPoint

    /// De combien on veut remonter.
    var valenceShift: Double { goal.valence - now.valence }
    /// De combien on veut se réveiller.
    var activationShift: Double { goal.activation - now.activation }
}

// MARK: - Les stratégies

/// Ce que le vecteur veut dire, nommé. Ces cas ne sont pas des branches de code :
/// ils se déduisent du signe et de l'amplitude du trajet, et ne servent qu'à
/// écrire la lecture montrée à l'utilisateur.
nonisolated enum MoodStrategy: String, Hashable, Sendable {
    case accompagnement, reparation, reparationDouce
    case decompression, stimulation, descenteAssumee, prolongation

    /// Le seuil en deçà duquel un déplacement n'en est pas un.
    private static let deadband = 0.25

    static func from(_ trajectory: MoodTrajectory) -> MoodStrategy {
        let dv = trajectory.valenceShift
        let da = trajectory.activationShift

        // Remonter *en se posant* : les deux mouvements sont francs et opposés, et
        // c'est leur conjonction qui décrit l'intention. Testé en premier, sinon la
        // règle de dominance ci-dessous n'en retiendrait qu'une moitié.
        if dv > deadband, da < -deadband { return .reparationDouce }

        if abs(dv) < deadband, abs(da) < deadband {
            return trajectory.now.valence < -0.2 ? .accompagnement : .prolongation
        }

        // Sinon c'est le déplacement le plus ample qui nomme l'intention. Comparer
        // les amplitudes plutôt que tester la valence d'abord : une valence qui monte
        // à peine ne doit pas éclipser une activation qui bondit — sans quoi on
        // annonce « on écarte le lourd » à quelqu'un qui demande du nerf.
        if abs(dv) >= abs(da) { return dv > 0 ? .reparation : .descenteAssumee }
        return da > 0 ? .stimulation : .decompression
    }

    /// La lecture : une ligne, jamais un paragraphe. Elle dit ce que le système a
    /// compris — c'est le seul endroit où CinéMatch prend la parole.
    var reading: String {
        switch self {
        case .accompagnement: "On reste là où vous êtes, mais accompagné·e."
        case .reparation: "Vous cherchez à remonter — on écarte le lourd."
        case .reparationDouce: "Remonter en se posant : rien de lourd, rien de bruyant."
        case .decompression: "On redescend : quelque chose qui prend son temps."
        case .stimulation: "Il vous faut du nerf — on cherche ce qui réveille."
        case .descenteAssumee: "Vous allez bien et vous voulez du dur. Noté."
        case .prolongation: "Rien à déplacer — on suit simplement votre goût."
        }
    }
}

// MARK: - Le profil recherché

/// La position recherchée sur les huit axes du film, produite par la fonction de
/// transfert. Le scoring actuel n'en consomme qu'une partie (voir
/// `QuestionnaireAnswers.applying(_:)`) — les huit sont calculés dès maintenant
/// parce que ce sont eux, et non les champs d'aujourd'hui, qui sont la cible.
nonisolated struct DesiredProfile: Equatable, Hashable, Sendable {
    /// Léger (−1) ↔ éprouvant (+1).
    var charge: Double
    /// Contemplatif (−1) ↔ haletant (+1).
    var rythme: Double
    /// Terrain connu (−1) ↔ inconnu (+1).
    var familiarite: Double
    /// Limpide (−1) ↔ exigeant (+1).
    var densite: Double
    /// Réel (−1) ↔ imaginaire (+1).
    var ancrage: Double
    /// Distancié (−1) ↔ chaleureux (+1).
    var ton: Double
    /// Intime (−1) ↔ épique (+1).
    var echelle: Double
    /// Peu (−1) ↔ beaucoup (+1).
    var investissement: Double
}

// MARK: - La fonction de transfert

/// Traduit un trajet d'humeur en profil de film recherché.
///
/// Volontairement lisible plutôt qu'opaque : chaque ligne est un jugement qu'on
/// peut discuter, et qui sera révisé quand on saura quel film a réellement été
/// lancé. Deux d'entre elles encodent des décisions et non des évidences —
/// voir `charge` et `familiarite` ci-dessous.
nonisolated enum MoodTransfer {
    static func profile(for trajectory: MoodTrajectory) -> DesiredProfile {
        let dv = trajectory.valenceShift
        let da = trajectory.activationShift
        let v0 = trajectory.now.valence
        let v1 = trajectory.goal.valence
        let a1 = trajectory.goal.activation

        /// Le creux d'humeur d'où l'on part, borné à sa part positive.
        let lowNow = max(0, -v0)
        /// S'éteint dès que le trajet pointe vers le haut.
        let staysPut = 1 - min(1, abs(dv))

        return DesiredProfile(
            // La charge n'est autorisée que si la personne ne cherche pas à
            // remonter : on n'envoie pas un film éprouvant à quelqu'un qui a
            // demandé à aller mieux — surtout s'il part de bas.
            charge: clamp(-0.85 * dv + 0.55 * lowNow * staysPut),
            rythme: clamp(0.55 * a1 + 0.45 * da),
            // L'appétit pour le risque baisse avec l'humeur : ce n'est pas le
            // soir de tenter le film que personne ne connaît.
            familiarite: clamp(0.50 * a1 - 0.40 * lowNow),
            densite: clamp(0.70 * a1),
            ancrage: clamp(0.70 * dv),
            ton: clamp(0.75 * dv + 0.35 * max(0, v1)),
            echelle: clamp(0.45 * dv + 0.35 * a1),
            investissement: clamp(0.75 * a1)
        )
    }

    private static func clamp(_ value: Double) -> Double {
        min(1, max(-1, value))
    }
}

// MARK: - Le pont vers les champs d'aujourd'hui

nonisolated extension QuestionnaireAnswers {
    /// Verse le profil recherché dans les champs que le backend sait déjà lire.
    ///
    /// Le scoring n'a pas encore d'espace latent (c'est le jalon suivant) : en
    /// attendant, le trajet d'humeur alimente `mood`, `genres` et
    /// `surpriseIntensity`. L'utilisateur ne voit plus aucune de ces trois
    /// questions — elles sont déduites de deux appuis.
    ///
    /// `runtime` n'est délibérément pas touché : il porte le budget annoncé au
    /// cadre, c'est-à-dire une contrainte, et une contrainte ne se laisse pas
    /// récrire par une envie. `investissement` reste donc inexploité jusqu'au
    /// jalon où les huit axes deviennent la cible du scoring.
    mutating func apply(_ profile: DesiredProfile) {
        surpriseIntensity = (profile.familiarite + 1) / 2

        // Un profil sans relief — « rien à déplacer » — ne désigne aucune ambiance :
        // il tomberait mécaniquement sur l'ancre la plus proche de l'origine, ce qui
        // est un artefact de la mesure, pas une préférence. On laisse alors `mood` nul
        // (le backend rend un score d'ambiance neutre) et le vivier large, et ce sont
        // les questions adaptatives qui trancheront.
        guard Self.hasRelief(profile) else {
            mood = nil
            genres = []
            return
        }

        let closest = Self.closestMood(to: profile)
        mood = closest
        genres = Self.genres(for: closest, profile: profile, avoiding: avoidedGenreIDs)
    }

    private static func hasRelief(_ profile: DesiredProfile) -> Bool {
        let amplitudes = [
            profile.charge, profile.rythme, profile.ton, profile.ancrage, profile.echelle,
        ].map(abs)
        return (amplitudes.max() ?? 0) >= 0.2
    }

    /// Le `Mood` existant le plus proche du profil recherché — chaque cas de
    /// l'énumération est posé dans le même espace, et on prend le plus court.
    private static func closestMood(to profile: DesiredProfile) -> Mood {
        let anchors: [(Mood, DesiredProfile)] = [
            (.lightFun, anchor(charge: -0.7, rythme: 0.1, ton: 0.8, ancrage: 0.1, echelle: -0.2)),
            (.intense, anchor(charge: 0.4, rythme: 0.9, ton: -0.3, ancrage: 0.2, echelle: 0.5)),
            (.emotional, anchor(charge: 0.8, rythme: -0.4, ton: 0.4, ancrage: -0.6, echelle: -0.6)),
            (.scary, anchor(charge: 0.6, rythme: 0.6, ton: -0.7, ancrage: 0.3, echelle: -0.2)),
            (.escapist, anchor(charge: -0.3, rythme: 0.6, ton: 0.2, ancrage: 0.9, echelle: 0.9)),
            (.thoughtful, anchor(charge: 0.3, rythme: -0.7, ton: -0.2, ancrage: 0.1, echelle: -0.3)),
        ]
        return anchors.min { distance(profile, $0.1) < distance(profile, $1.1) }?.0 ?? .lightFun
    }

    /// Les genres qui cadrent la requête de vivier — dérivés **du mood retenu**, et
    /// non du profil directement.
    ///
    /// C'est une contrainte de cohérence, pas une commodité : côté backend, le score
    /// d'ambiance pèse 30 % et récompense les films dont les genres recoupent ceux du
    /// mood (`MOOD_GENRES`). Choisir les genres du vivier indépendamment du mood
    /// produirait un vivier que le plus gros poids du score pénalise en bloc — le
    /// critère deviendrait une constante au lieu de trancher. Le profil ne sert donc
    /// qu'à départager *à l'intérieur* de la famille du mood.
    ///
    /// Les genres bannis dans les réglages sont retirés **avant** l'envoi : côté
    /// backend, `avoidedGenreIds` n'est qu'un malus de score, pas un filtre. Sans ce
    /// retrait, un profil qui pointe vers un genre exclu ferait interroger TMDB pour
    /// exactement ce que la personne a dit ne pas vouloir voir. Il vaut mieux un
    /// vivier large qu'un vivier juste mais indésirable — d'où le repli sur une liste
    /// vide, que le backend accepte sans broncher.
    private static func genres(
        for mood: Mood, profile: DesiredProfile, avoiding banned: Set<Int>
    ) -> Set<Genre> {
        let family: [Genre]
        switch mood {
        case .lightFun:
            family = [.comedy]
        case .intense:
            family = profile.echelle > 0.25 ? [.action, .thriller] : [.thriller, .action]
        case .emotional:
            family = profile.echelle < -0.3 ? [.drama, .romance] : [.drama]
        case .scary:
            family = [.horror, .thriller]
        case .escapist:
            family = [.scifiFantasy, .action]
        case .thoughtful:
            family = profile.densite > 0.4 ? [.documentary, .drama] : [.drama, .scifiFantasy]
        }

        // Deux genres au maximum : au-delà, le OU de TMDB élargit le vivier au lieu
        // de le cadrer, ce qui est exactement l'inverse de l'effet recherché.
        let allowed = family.filter { $0.tmdbIDs.isDisjoint(with: banned) }
        return Set(allowed.prefix(QuestionnaireAnswers.maxGenres))
    }

    private static func anchor(
        charge: Double, rythme: Double, ton: Double, ancrage: Double, echelle: Double
    ) -> DesiredProfile {
        DesiredProfile(
            charge: charge, rythme: rythme, familiarite: 0, densite: 0,
            ancrage: ancrage, ton: ton, echelle: echelle, investissement: 0
        )
    }

    /// Distance sur les seules dimensions que les ancres renseignent — inclure
    /// les axes laissés à zéro fausserait la comparaison en les traitant comme
    /// une position revendiquée.
    private static func distance(_ a: DesiredProfile, _ b: DesiredProfile) -> Double {
        let terms = [
            a.charge - b.charge,
            a.rythme - b.rythme,
            a.ton - b.ton,
            a.ancrage - b.ancrage,
            a.echelle - b.echelle,
        ]
        return terms.reduce(0) { $0 + $1 * $1 }
    }
}
