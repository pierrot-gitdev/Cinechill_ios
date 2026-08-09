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
        case .common: String(localized: "Commun", bundle: .app)
        case .rare: String(localized: "Rare", bundle: .app)
        case .epic: String(localized: "Épique", bundle: .app)
        case .legendary: String(localized: "Légendaire", bundle: .app)
        case .mythic: String(localized: "Secret", bundle: .app)
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
        isSecret && !unlocked ? String(localized: "Un badge reste à découvrir.", bundle: .app) : condition
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
            id: "first_reel", name: String(localized: "Première Bobine", bundle: .app),
            condition: String(localized: "Votre tout premier film enregistré.", bundle: .app),
            rarity: .common, isSecret: false
        ),
        Badge(
            id: "centenary", name: String(localized: "Le Centenaire", bundle: .app),
            condition: String(localized: "100 films dans la galerie.", bundle: .app),
            rarity: .rare, isSecret: false
        ),
        Badge(
            id: "cinematheque", name: String(localized: "La Cinémathèque", bundle: .app),
            condition: String(localized: "500 films. Une vie de spectateur, archivée.", bundle: .app),
            rarity: .legendary, isSecret: false
        ),
        Badge(
            id: "archaeologist", name: String(localized: "Archéologue", bundle: .app),
            condition: String(localized: "25 films sortis avant 1970.", bundle: .app),
            rarity: .epic, isSecret: false
        ),
        Badge(
            id: "traveler", name: String(localized: "Le Voyageur", bundle: .app),
            condition: String(localized: "Au moins un film dans 8 décennies différentes.", bundle: .app),
            rarity: .epic, isSecret: false
        ),
        Badge(
            id: "steel_heart", name: String(localized: "Cœur d'Acier", bundle: .app),
            condition: String(localized: "75 films d'action.", bundle: .app),
            rarity: .rare, isSecret: false
        ),
        Badge(
            id: "sleepless", name: String(localized: "Sans Dormir", bundle: .app),
            condition: String(localized: "40 films d'horreur.", bundle: .app),
            rarity: .rare, isSecret: false
        ),
        Badge(
            id: "panoramic", name: String(localized: "L'Œil Panoramique", bundle: .app),
            condition: String(localized: "Au moins 10 films dans 8 genres différents.", bundle: .app),
            rarity: .epic, isSecret: false
        ),
        Badge(
            id: "marathon", name: String(localized: "Marathon", bundle: .app),
            condition: String(localized: "7 jours d'affilée à enrichir votre galerie.", bundle: .app),
            rarity: .common, isSecret: false
        ),
        Badge(
            id: "ritual", name: String(localized: "Le Rituel", bundle: .app),
            condition: String(localized: "60 jours d'affilée. Sans une seule absence.", bundle: .app),
            rarity: .legendary, isSecret: false
        ),
        Badge(
            id: "clean_list", name: String(localized: "Liste Nette", bundle: .app),
            condition: String(localized: "Ramener une watchlist d'au moins 15 films à zéro.", bundle: .app),
            rarity: .rare, isSecret: false
        ),
        Badge(
            id: "sorter", name: String(localized: "Le Trieur", bundle: .app),
            condition: String(localized: "500 cartes tranchées dans le deck.", bundle: .app),
            rarity: .common, isSecret: false
        ),
        Badge(
            id: "signature", name: String(localized: "Signature", bundle: .app),
            condition: String(localized: "8 films d'un même réalisateur.", bundle: .app),
            rarity: .epic, isSecret: false
        ),
        Badge(
            id: "integral", name: String(localized: "L'Intégrale", bundle: .app),
            condition: String(localized: "Une saga entière, sans en manquer un seul épisode.", bundle: .app),
            rarity: .legendary, isSecret: false
        ),
        Badge(
            id: "night_owl", name: String(localized: "Le Noctambule", bundle: .app),
            condition: String(localized: "15 films enregistrés entre 2 h et 5 h du matin.", bundle: .app),
            rarity: .mythic, isSecret: true
        ),
    ]

    static func badge(id: String) -> Badge? {
        all.first { $0.id == id }
    }
}
