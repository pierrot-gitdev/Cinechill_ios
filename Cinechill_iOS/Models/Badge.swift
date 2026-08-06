//
//  Badge.swift
//  Cinechill_iOS
//

import SwiftUI

/// La rareté d'un badge. Elle ne se lit pas d'abord en toutes lettres mais au
/// halo projeté derrière la monture.
nonisolated enum BadgeRarity: String, Sendable, Hashable {
    case common
    case rare
    case epic
    case legendary
    case mythic

    var label: String {
        switch self {
        case .common: "Commun"
        case .rare: "Rare"
        case .epic: "Épique"
        case .legendary: "Légendaire"
        case .mythic: "Secret"
        }
    }

    var halo: Color {
        switch self {
        case .common: .clear
        case .rare: Color(red: 0.35, green: 0.59, blue: 1).opacity(0.45)
        case .epic: Color(red: 0.66, green: 0.33, blue: 0.97).opacity(0.5)
        case .legendary: Color(red: 1, green: 0.66, blue: 0.15).opacity(0.55)
        case .mythic: Color(red: 0.47, green: 1, blue: 0.86).opacity(0.5)
        }
    }

    var accent: Color {
        switch self {
        case .common: Color(.systemGray)
        case .rare: Color(red: 0.29, green: 0.52, blue: 0.91)
        case .epic: Color(red: 0.62, green: 0.36, blue: 0.82)
        case .legendary: Color(red: 0.66, green: 0.45, blue: 0.07)
        case .mythic: Color(red: 0.07, green: 0.63, blue: 0.53)
        }
    }

    /// Les deux raretés les plus hautes respirent lentement.
    var breathes: Bool { self == .legendary || self == .mythic }
}

/// Un badge de la collection. L'illustration elle-même vit dans l'asset
/// catalog — `imageName` pointe vers un artwork PNG déjà composé (monture,
/// champ, scène, halo baked in), plutôt que d'être recomposée à l'écran.
nonisolated struct Badge: Identifiable, Sendable, Hashable {
    let id: String
    let name: String
    /// Condition affichée. Masquée tant qu'un badge secret n'est pas obtenu.
    let condition: String
    let rarity: BadgeRarity
    let isSecret: Bool

    /// Nom de l'image dans Assets.xcassets — identique à `id`.
    var imageName: String { id }

    /// Ce que l'utilisateur voit avant d'avoir découvert un badge secret.
    func displayName(unlocked: Bool) -> String {
        isSecret && !unlocked ? "???" : name
    }

    func displayCondition(unlocked: Bool) -> String {
        isSecret && !unlocked ? "Un badge reste à découvrir." : condition
    }
}

/// L'état d'un badge pour un utilisateur donné, tel que renvoyé par
/// `evaluateBadges`.
nonisolated struct BadgeProgress: Identifiable, Sendable, Hashable {
    let id: String
    let unlocked: Bool
    let unlockedAt: Date?
    let current: Int
    let target: Int
    /// Ce qui manque précisément, quand le serveur sait le dire.
    let detail: String?

    var fraction: Double {
        guard target > 0 else { return 0 }
        return min(1, Double(current) / Double(target))
    }

    static func locked(id: String) -> BadgeProgress {
        BadgeProgress(id: id, unlocked: false, unlockedAt: nil, current: 0, target: 1, detail: nil)
    }
}

// MARK: - Le catalogue

nonisolated enum BadgeCatalog {
    /// Les quinze badges de la première collection, dans l'ordre d'affichage
    /// de la galerie — familles regroupées, progression croissante. Les noms
    /// d'image correspondants (`Assets.xcassets`) sont les quinze PNG exportés
    /// depuis la planche de design : first_reel, centenary, cinematheque,
    /// archaeologist, traveler, steel_heart, sleepless, panoramic, marathon,
    /// ritual, clean_list, sorter, signature, integral, night_owl.
    static let all: [Badge] = [
        Badge(
            id: "first_reel", name: "Première Bobine",
            condition: "Votre tout premier film enregistré.",
            rarity: .common, isSecret: false
        ),
        Badge(
            id: "centenary", name: "Le Centenaire",
            condition: "100 films dans la galerie.",
            rarity: .rare, isSecret: false
        ),
        Badge(
            id: "cinematheque", name: "La Cinémathèque",
            condition: "500 films. Une vie de spectateur, archivée.",
            rarity: .legendary, isSecret: false
        ),
        Badge(
            id: "archaeologist", name: "Archéologue",
            condition: "25 films sortis avant 1970.",
            rarity: .epic, isSecret: false
        ),
        Badge(
            id: "traveler", name: "Le Voyageur",
            condition: "Au moins un film dans 8 décennies différentes.",
            rarity: .epic, isSecret: false
        ),
        Badge(
            id: "steel_heart", name: "Cœur d'Acier",
            condition: "75 films d'action.",
            rarity: .rare, isSecret: false
        ),
        Badge(
            id: "sleepless", name: "Sans Dormir",
            condition: "40 films d'horreur.",
            rarity: .rare, isSecret: false
        ),
        Badge(
            id: "panoramic", name: "L'Œil Panoramique",
            condition: "Au moins 10 films dans 8 genres différents.",
            rarity: .epic, isSecret: false
        ),
        Badge(
            id: "marathon", name: "Marathon",
            condition: "7 jours d'affilée à enrichir votre galerie.",
            rarity: .common, isSecret: false
        ),
        Badge(
            id: "ritual", name: "Le Rituel",
            condition: "60 jours d'affilée. Sans une seule absence.",
            rarity: .legendary, isSecret: false
        ),
        Badge(
            id: "clean_list", name: "Liste Nette",
            condition: "Ramener une watchlist d'au moins 15 films à zéro.",
            rarity: .rare, isSecret: false
        ),
        Badge(
            id: "sorter", name: "Le Trieur",
            condition: "500 cartes tranchées dans le deck.",
            rarity: .common, isSecret: false
        ),
        Badge(
            id: "signature", name: "Signature",
            condition: "8 films d'un même réalisateur.",
            rarity: .epic, isSecret: false
        ),
        Badge(
            id: "integral", name: "L'Intégrale",
            condition: "Une saga entière, sans en manquer un seul épisode.",
            rarity: .legendary, isSecret: false
        ),
        Badge(
            id: "night_owl", name: "Le Noctambule",
            condition: "15 films enregistrés entre 2 h et 5 h du matin.",
            rarity: .mythic, isSecret: true
        ),
    ]

    static func badge(id: String) -> Badge? {
        all.first { $0.id == id }
    }
}
