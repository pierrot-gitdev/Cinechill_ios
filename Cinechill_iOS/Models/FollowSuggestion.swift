//
//  FollowSuggestion.swift
//  Cinechill_iOS
//

import Foundation

/// Un profil proposé à suivre, avec ce qui le justifie.
///
/// Le nom n'est pas `Suggestion` : celui-ci désigne déjà un film recommandé par
/// quelqu'un qu'on suit. Ici, c'est une personne qu'on propose de suivre.
///
/// La raison est un fait qu'on peut vérifier en ouvrant le profil : « Te suit »,
/// « Léa suit ce profil », « 23 films en commun ». Un pourcentage d'affinité
/// aurait l'air précis sans dire sur quoi il repose. Le serveur classe, l'app
/// rédige : la raison suit la langue choisie dans les réglages.
nonisolated struct FollowSuggestion: Identifiable, Hashable, Sendable {
    let profile: PublicProfile
    let followsYou: Bool
    /// Combien des gens que je suis suivent ce profil.
    let mutualCount: Int
    /// Le premier d'entre eux, celui que la raison nomme.
    let mutualName: String?
    let commonCount: Int

    var id: String { profile.id }

    /// En dessous, « 2 films en commun » ne dit rien d'un goût partagé : deux
    /// comptes ont simplement vu le même film à succès.
    static let meaningfulCommonCount = 3

    /// Une seule raison, celle qui a classé la carte, dans l'ordre du serveur.
    ///
    /// « Suit ce profil » plutôt que « Suivi par » : on ne sait pas s'il faut
    /// accorder « suivi » ou « suivie ».
    var reason: String {
        if followsYou {
            return String(localized: "Te suit", bundle: .app)
        }
        if mutualCount > 0, let mutualName, !mutualName.isEmpty {
            // « et 1 autre », « et 14 autres » : l'accord vit dans le catalogue.
            return mutualCount == 1
                ? String(localized: "\(mutualName) suit ce profil", bundle: .app)
                : String(localized: "\(mutualName) et \(mutualCount - 1) autres suivent ce profil", bundle: .app)
        }
        if commonCount >= Self.meaningfulCommonCount {
            return String(localized: "\(commonCount) films en commun", bundle: .app)
        }
        return Self.seenCount(profile.galleryCount)
    }

    /// « 214 films vus », et « 2 847 films vus » avec le séparateur de la
    /// langue choisie : `%lld` n'en pose aucun. Au-delà de 999 le pluriel est
    /// acquis, et la clé formatée peut prendre le relais sans perdre l'accord.
    static func seenCount(_ count: Int) -> String {
        guard count >= 1000 else {
            return String(localized: "\(count) films vus", bundle: .app)
        }
        let formatted = count.formatted(.number.locale(AppLanguage.current.locale))
        return String(localized: "\(formatted) films vus", bundle: .app)
    }
}

/// Ce que renvoie le serveur : les profils classés, et de quoi décider où
/// poser la rangée sur l'accueil.
nonisolated struct FollowSuggestionsPage: Sendable {
    /// Le nombre de personnes suivies au moment du calcul. La place de la
    /// rangée se décide là-dessus une fois pour toutes au chargement : calculée
    /// en direct, elle sauterait d'un bloc sous le doigt au cinquième suivi.
    let followingCount: Int
    let suggestions: [FollowSuggestion]
}
