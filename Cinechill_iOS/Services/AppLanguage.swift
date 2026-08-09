//
//  AppLanguage.swift
//  Cinechill_iOS
//

import Foundation
import SwiftUI

/// La langue de l'application — celle de l'interface **et** celle des films.
///
/// Les deux ne se séparent pas : une interface anglaise posée sur des synopsis
/// français n'est traduite qu'à moitié, et c'est la moitié qui compte le moins.
/// Le choix fait ici décide donc à la fois du catalogue de chaînes lu en local
/// et de l'en-tête `Accept-Language` envoyé au backend, qui le répercute à TMDB.
///
/// `.system` n'est pas une troisième langue : c'est l'absence de choix, qui
/// laisse iOS trancher. On la garde en tête de liste parce que c'est le
/// comportement attendu tant qu'on n'a rien demandé.
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case french
    case english

    var id: String { rawValue }

    /// Le libellé se lit toujours dans sa propre langue : on ne traduit pas
    /// « English » en « Anglais » dans un sélecteur, sans quoi il faut déjà
    /// comprendre la langue courante pour en sortir.
    var label: String {
        switch self {
        case .system: String(localized: "Système", bundle: .app)
        case .french: "Français"
        case .english: "English"
        }
    }

    /// Le code BCP 47 retenu, ou `nil` quand on suit le système.
    var localeIdentifier: String? {
        switch self {
        case .system: nil
        case .french: "fr"
        case .english: "en"
        }
    }

    /// Ce qu'on annonce au backend, qui le passe tel quel à TMDB. Le pays est
    /// nécessaire : TMDB ne renvoie rien pour un `fr` nu.
    var tmdbTag: String {
        switch self {
        case .system: AppLanguage.resolvedFromSystem.tmdbTag
        case .french: "fr-FR"
        case .english: "en-US"
        }
    }

    var locale: Locale {
        localeIdentifier.map(Locale.init(identifier:)) ?? .autoupdatingCurrent
    }

    /// Le paquet de ressources à interroger. C'est lui, et rien d'autre, qui
    /// décide de la langue rendue à l'écran — d'où sa présence explicite dans
    /// chaque appel de localisation de l'app.
    var bundle: Bundle {
        guard let identifier = localeIdentifier,
              let path = Bundle.main.path(forResource: identifier, ofType: "lproj"),
              let bundle = Bundle(path: path)
        else { return .main }
        return bundle
    }

    /// Celle des deux langues traduites dont le système est le plus proche.
    /// Sert uniquement à choisir ce qu'on demande à TMDB : pour l'interface,
    /// `Bundle.main` fait déjà ce travail tout seul.
    private static var resolvedFromSystem: AppLanguage {
        Locale.preferredLanguages.first?.hasPrefix("fr") == true ? .french : .english
    }

    // MARK: - L'état courant

    /// La langue en vigueur, lisible de partout.
    ///
    /// Les modèles, les services et les vues formatent tous du texte, et aucun
    /// n'a de raison de connaître `LanguageStore` pour ça. La valeur n'est
    /// écrite que par le store, sur le main actor, et lue partout ailleurs —
    /// une écriture rare pour des lectures constantes.
    nonisolated(unsafe) private(set) static var current: AppLanguage = load()

    static func apply(_ language: AppLanguage) {
        current = language
        UserDefaults.standard.set(language.rawValue, forKey: storageKey)
    }

    private static let storageKey = "app.language"

    private static func load() -> AppLanguage {
        UserDefaults.standard.string(forKey: storageKey)
            .flatMap(AppLanguage.init(rawValue:)) ?? .system
    }
}

extension Bundle {
    /// Le paquet de la langue choisie. Tous les appels de localisation de
    /// l'application passent par lui : `Bundle.main` suivrait le réglage
    /// système, que le sélecteur des réglages a précisément vocation à
    /// contredire.
    static var app: Bundle { AppLanguage.current.bundle }
}

/// Le choix de langue, observable par les vues.
///
/// Il ne détient pas la valeur — c'est `AppLanguage.current` qui la porte, pour
/// rester lisible depuis les modèles et les services, qui formatent du texte
/// sans rien connaître de SwiftUI. Le store en est la façade observable, et le
/// seul endroit d'où la valeur s'écrit.
///
/// Un exemplaire partagé plutôt qu'une valeur d'environnement : les réglages
/// s'ouvrent à travers deux `fullScreenCover` empilés, et la langue est de
/// toute façon un réglage de processus — la même pour tout le monde, comme
/// `Bundle.main` dont elle décide.
@Observable
@MainActor
final class LanguageStore {
    static let shared = LanguageStore()

    private(set) var selection: AppLanguage = AppLanguage.current

    private init() {}

    func select(_ language: AppLanguage) {
        guard language != selection else { return }
        AppLanguage.apply(language)
        selection = language
    }
}

extension URLRequest {
    /// Une requête vers le backend Cinechill.
    ///
    /// Elle annonce toujours la langue choisie : c'est elle qui décide des
    /// titres, des synopsis, des noms de genres et de plateformes que TMDB
    /// renverra en bout de chaîne. Sans cet en-tête, une interface anglaise
    /// resterait posée sur des résumés français.
    ///
    /// L'en-tête plutôt qu'un paramètre : il vaut pour les `GET` comme pour les
    /// `POST`, et il n'oblige aucun corps de requête à se rallonger d'un champ.
    init(backend url: URL) {
        self.init(url: url)
        setValue(AppLanguage.current.tmdbTag, forHTTPHeaderField: "Accept-Language")
    }
}
