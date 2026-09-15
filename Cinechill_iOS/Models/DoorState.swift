//
//  DoorState.swift
//  Cinechill_iOS
//

import Foundation

/// Les cinq artéfacts de la porte, de bas en haut sur le montant : la jauge se
/// remplit en montant.
nonisolated enum DoorArtifactKey: String, Codable, CaseIterable, Sendable {
    case memoire, eventail, coeur, horizons, promesse

    /// Le PNG du médaillon, exporté à 1200 comme les badges : monture d'or,
    /// champ émaillé, emblème et halo intégrés. L'état éteint se dérive en
    /// code, comme pour les badges verrouillés.
    var assetName: String {
        switch self {
        case .memoire: "ArtefactMemoire"
        case .eventail: "ArtefactEventail"
        case .coeur: "ArtefactCoeur"
        case .horizons: "ArtefactHorizons"
        case .promesse: "ArtefactPromesse"
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
        case .horizons: 0x5996FF
        case .promesse: 0x35C4A8
        }
    }

    /// Le halo de l'allumage, plus clair que la teinte, comme celui des badges.
    var halo: UInt {
        switch self {
        case .memoire: 0xA854F7
        case .eventail: 0xFFA826
        case .coeur: 0xFF6B7E
        case .horizons: 0x5996FF
        case .promesse: 0x78FFDB
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

/// L'ancien détail des Horizons : décennies et pays. L'artéfact de clé
/// `horizons` est devenu « Tes préférences » et se mesure en comparaisons ;
/// le serveur renvoie encore cet objet pour ne pas casser les anciennes
/// versions de l'app, mais il n'entre plus dans la porte.
nonisolated struct DoorHorizons: Codable, Equatable, Sendable {
    let decades: Int
    let decadesTarget: Int
    let countries: Int
    let countriesTarget: Int
}

/// La porte, telle que `getTasteProfile` la renvoie.
nonisolated struct DoorState: Codable, Equatable, Sendable {
    let unlocked: Bool
    let artifacts: [DoorArtifact]
    let horizons: DoorHorizons

    /// Nombre d'artéfacts allumés.
    var litCount: Int { artifacts.filter(\.done).count }

    func artifact(_ key: DoorArtifactKey) -> DoorArtifact? {
        artifacts.first { $0.key == key.rawValue }
    }

    /// Les comparaisons de « Tes préférences » n'ouvrent qu'après la Mémoire :
    /// sous ce nombre de films, les mêmes affiches reviendraient d'un tour à
    /// l'autre et le choix ne dirait plus rien. Le serveur tient la même règle.
    var canCompare: Bool { artifact(.memoire)?.done == true }

    /// La porte d'un compte que le serveur n'a pas encore raconté : tout à
    /// zéro, tout éteint. C'est l'état honnête d'un profil inconnu, et il
    /// évite de faire clignoter l'entrée avant de la refermer.
    ///
    /// Les seuils sont ceux du serveur : la Mémoire à 100 films, et l'artéfact
    /// de clé `horizons`, devenu « Tes préférences », à 12 comparaisons entre
    /// des films vus. Les deux se tiennent : chaque comparaison consomme cinq
    /// films (quatre affiches et le remplaçant du film gardé), soit 60 sur les
    /// douze tours ; à 100, aucune affiche ne revient d'un tour à l'autre.
    static let initial = DoorState(
        unlocked: false,
        artifacts: DoorArtifactKey.allCases.map { key in
            DoorArtifact(key: key.rawValue, done: false, current: 0, target: initialTarget(key))
        },
        horizons: DoorHorizons(
            decades: 0, decadesTarget: 4, countries: 0, countriesTarget: 3
        )
    )

    /// Le seuil de chaque artéfact tant que le serveur ne l'a pas donné.
    private static func initialTarget(_ key: DoorArtifactKey) -> Int {
        switch key {
        case .memoire: 100
        case .eventail: 6
        case .coeur: 12
        case .horizons: 12
        case .promesse: 10
        }
    }

    // MARK: - La mémoire locale

    /// La dernière porte racontée par le serveur, gardée d'un lancement à
    /// l'autre : l'onglet s'ouvre sur un état plausible au lieu d'attendre le
    /// réseau, et la réponse ne fait que le rafraîchir.
    private static let cacheKey = "cinematch.door"

    static var cached: DoorState? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return nil }
        return try? JSONDecoder().decode(DoorState.self, from: data)
    }

    static func cache(_ state: DoorState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey)
    }
}
