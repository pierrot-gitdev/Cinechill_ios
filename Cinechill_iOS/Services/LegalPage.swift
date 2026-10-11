//
//  LegalPage.swift
//  Cinechill_iOS
//

import Foundation

/// Les deux pages publiques que l'App Store et la loi demandent de pouvoir lire
/// avant de s'inscrire. Elles ne vivent pas dans l'app : Firebase Hosting les
/// sert depuis le dépôt du backend (`hosting/public`), pour qu'une correction
/// de texte ne demande pas une nouvelle version sur l'App Store.
nonisolated enum LegalPage {
    case terms
    case privacy

    private static let host = "https://cinechill-a762b.web.app"

    /// La page dans la langue choisie dans les réglages, pas celle d'iOS : on
    /// vient de lire l'app dans cette langue, la page suit.
    var url: URL {
        let path: String
        switch (self, AppLanguage.current) {
        case (.terms, .french): path = "conditions"
        case (.terms, .english): path = "terms"
        case (.privacy, .french): path = "confidentialite"
        case (.privacy, .english): path = "privacy"
        }
        return URL(string: "\(Self.host)/\(path)")!
    }
}
