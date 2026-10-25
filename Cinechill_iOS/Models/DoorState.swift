//
//  DoorState.swift
//  Cinechill_iOS
//

import Foundation

/// Les quatre artéfacts de la porte, de bas en haut sur le montant : la jauge
/// se remplit en montant. L'ordre des cas est cet ordre-là : la jauge, le rang
/// « Étape n sur 4 » et le conduit le lisent tous ici. La Porte des séries n'a
/// pas « Tes déceptions » (voir `DoorState.keys`).
///
/// Il y en avait cinq jusqu'au 18 octobre 2026. Le cinquième, « Tes
/// préférences », faisait jouer douze comparaisons entre films vus ; il a été
/// retiré parce qu'il ne servait ni la personne (rien de visible au bout) ni le
/// moteur (douze duels pèsent peu face à une galerie de cent films et douze
/// coups de cœur, que les quatre autres étapes garantissent déjà).
///
/// Et quatre jusqu'au 25 octobre 2026 : « La Promesse » demandait dix films en
/// watchlist. La watchlist n'apprend rien au moteur, qui lit les goûts dans la
/// galerie ; un film de la watchlist garde son petit bonus dans les
/// propositions, qu'il y en ait un ou dix. L'étape bloquait CinéMatch sans le
/// rendre plus juste. « Tes déceptions » a pris sa place le même jour : le
/// moteur savait ce qu'on aime, il devinait ce qu'on n'aime pas.
nonisolated enum DoorArtifactKey: String, Codable, CaseIterable, Sendable {
    case memoire, eventail, coeur, deceptions

    /// Le PNG du médaillon, exporté à 1200 comme les badges : monture d'or,
    /// champ émaillé, emblème et halo intégrés. L'état éteint se dérive en
    /// code, comme pour les badges verrouillés.
    var assetName: String {
        switch self {
        case .memoire: "ArtefactMemoire"
        case .eventail: "ArtefactEventail"
        case .coeur: "ArtefactCoeur"
        // Le dessin de l'ancienne Promesse, en attendant le sien.
        case .deceptions: "ArtefactDeceptions"
        }
    }

    /// La teinte de l'artéfact — une couleur de **données**, comme la rareté
    /// des badges : elle ne sort jamais de la porte pour devenir du chrome.
    ///
    /// `UInt` et non `UInt32` : c'est le type de `Color(hex:)`, l'unique
    /// initialiseur de couleur du projet.
    var hue: UInt {
        switch self {
        case .memoire: 0xA98CE8
        case .eventail: 0xE0B24A
        case .coeur: 0xC25562
        case .deceptions: 0x35C4A8
        }
    }

    /// Le halo de l'allumage, plus clair que la teinte, comme celui des badges.
    var halo: UInt {
        switch self {
        case .memoire: 0xA854F7
        case .eventail: 0xFFA826
        case .coeur: 0xFF6B7E
        case .deceptions: 0x78FFDB
        }
    }
}

/// L'état d'un artéfact, mesuré par le serveur. Les seuils sont des constantes
/// serveur : la porte raconte toujours ce qui est réellement mesuré, et ils
/// s'ajustent sans release.
nonisolated struct DoorArtifact: Codable, Equatable, Sendable {
    let key: String
    let done: Bool
    let current: Int
    let target: Int

    var artifactKey: DoorArtifactKey? { DoorArtifactKey(rawValue: key) }
}

/// La porte, telle que `getDoors` la renvoie.
nonisolated struct DoorState: Codable, Equatable, Sendable {
    let unlocked: Bool
    let artifacts: [DoorArtifact]
    /// Vrai pour la Porte des séries : trois étapes, autres seuils, et
    /// d'autres mots. Absent de la réponse du serveur, posé par `DoorStore`.
    var isSeries: Bool? = nil

    var series: Bool { isSeries == true }

    /// Les étapes de cette porte, de bas en haut. Celle des séries n'a pas
    /// « Tes déceptions » : le moteur des séries ne lit pas les « Pas aimé ».
    var keys: [DoorArtifactKey] {
        DoorArtifactKey.allCases.filter { !(series && $0 == .deceptions) }
    }

    /// Nombre d'artéfacts allumés, parmi ceux que l'app connaît : un artéfact
    /// que le serveur enverrait en plus ne fausse ni la jauge ni le compte.
    var litCount: Int {
        keys.filter { artifact($0)?.done == true }.count
    }

    func artifact(_ key: DoorArtifactKey) -> DoorArtifact? {
        artifacts.first { $0.key == key.rawValue }
    }

    /// Le nombre d'étapes de la porte, dit à l'écran (« 2 étapes sur 4 »).
    var stepCount: Int { keys.count }

    /// La porte d'un compte que le serveur n'a pas encore raconté : tout à
    /// zéro, tout éteint. C'est l'état honnête d'un profil inconnu, et il
    /// évite de faire clignoter l'entrée avant de la refermer.
    ///
    /// Les seuils sont ceux du serveur : 100 films, 6 genres, 12 coups de
    /// cœur, 24 films passés en revue.
    static let initial = DoorState(
        unlocked: false,
        artifacts: DoorArtifactKey.allCases.map { key in
            DoorArtifact(key: key.rawValue, done: false, current: 0, target: initialTarget(key))
        }
    )

    /// La Porte des séries d'un compte que le serveur n'a pas encore racontée.
    /// Les seuils sont ceux du serveur : 15 séries, 4 genres, 4 saisons
    /// adorées.
    static let initialSeries = DoorState(
        unlocked: false,
        artifacts: DoorArtifactKey.allCases.filter { $0 != .deceptions }.map { key in
            DoorArtifact(key: key.rawValue, done: false, current: 0, target: initialSeriesTarget(key))
        },
        isSeries: true
    )

    private static func initialSeriesTarget(_ key: DoorArtifactKey) -> Int {
        switch key {
        case .memoire: 15
        case .eventail: 4
        case .coeur: 4
        case .deceptions: 0
        }
    }

    /// La même Porte, marquée comme celle des séries.
    func markedAsSeries() -> DoorState {
        var copy = self
        copy.isSeries = true
        return copy
    }

    /// Le seuil de chaque artéfact tant que le serveur ne l'a pas donné.
    private static func initialTarget(_ key: DoorArtifactKey) -> Int {
        switch key {
        case .memoire: 100
        case .eventail: 6
        case .coeur: 12
        case .deceptions: 24
        }
    }

    // MARK: - La mémoire locale

    /// La dernière porte racontée par le serveur, gardée d'un lancement à
    /// l'autre : l'onglet s'ouvre sur un état plausible au lieu d'attendre le
    /// réseau, et la réponse ne fait que le rafraîchir.
    ///
    /// Clés en `.v3` depuis le passage à trois étapes : une porte gardée avec
    /// une étape retirée compterait encore son médaillon allumé.
    private static let cacheKey = "cinematch.door.v3"
    private static let seriesCacheKey = "cinematch.seriesDoor.v3"

    /// Les deux caches, à effacer quand un autre compte se connecte.
    static var cacheKeys: [String] { [cacheKey, seriesCacheKey] }

    static var cached: DoorState? { read(cacheKey) }
    static var cachedSeries: DoorState? { read(seriesCacheKey)?.markedAsSeries() }

    static func cache(_ state: DoorState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: state.series ? seriesCacheKey : cacheKey)
    }

    private static func read(_ key: String) -> DoorState? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(DoorState.self, from: data)
    }
}
