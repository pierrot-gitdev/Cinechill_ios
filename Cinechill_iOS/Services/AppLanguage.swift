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
/// **Deux langues, pas trois.** Il y a eu un cas `.system` — l'absence de choix,
/// qui laissait iOS trancher. Il ne proposait rien que les deux autres ne
/// proposent déjà, et il coûtait cher : la langue effective n'était plus lisible
/// dans le réglage lui-même, `localeIdentifier` devait rendre un optionnel, et
/// `bundle` retombait sur `Bundle.main`, c'est-à-dire précisément sur ce que ce
/// sélecteur a vocation à contredire. Ce que `.system` apportait vraiment — ne
/// rien imposer au premier lancement — est conservé par `systemDefault`, qui est
/// la valeur de départ tant que rien n'a été choisi.
nonisolated enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case french
    case english

    var id: String { rawValue }

    /// Le libellé se lit toujours dans sa propre langue : on ne traduit pas
    /// « English » en « Anglais » dans un sélecteur, sans quoi il faut déjà
    /// comprendre la langue courante pour en sortir.
    var label: String {
        switch self {
        case .french: "Français"
        case .english: "English"
        }
    }

    var localeIdentifier: String {
        switch self {
        case .french: "fr"
        case .english: "en"
        }
    }

    /// Ce qu'on annonce au backend, qui le passe tel quel à TMDB. Le pays est
    /// nécessaire : TMDB ne renvoie rien pour un `fr` nu.
    var tmdbTag: String {
        switch self {
        case .french: "fr-FR"
        case .english: "en-US"
        }
    }

    var locale: Locale { Locale(identifier: localeIdentifier) }

    /// Le paquet de ressources à interroger. C'est lui, et rien d'autre, qui
    /// décide de la langue rendue à l'écran — d'où sa présence explicite dans
    /// chaque appel de localisation de l'app.
    var bundle: Bundle {
        guard let path = Bundle.main.path(forResource: localeIdentifier, ofType: "lproj"),
              let bundle = Bundle(path: path)
        else { return .main }
        return bundle
    }

    /// Celle des deux dont la langue du système est la plus proche. C'est le point
    /// de départ, tant que l'utilisateur n'a rien choisi — et il n'est pas
    /// enregistré, donc l'application suit l'appareil aussi longtemps qu'on ne
    /// l'a pas contredite.
    static var systemDefault: AppLanguage {
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

    /// Une valeur enregistrée qu'on ne sait plus lire vaut absence de choix : les
    /// installations qui portent l'ancien `"system"` retombent donc sur la langue
    /// de leur appareil — exactement ce que ce réglage faisait pour elles.
    private static func load() -> AppLanguage {
        UserDefaults.standard.string(forKey: storageKey)
            .flatMap(AppLanguage.init(rawValue:)) ?? systemDefault
    }
}

nonisolated extension Bundle {
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

nonisolated extension URLRequest {
    /// Une requête vers le backend Cinechill.
    ///
    /// Elle annonce toujours la langue choisie : c'est elle qui décide des
    /// titres, des synopsis, des noms de genres et de plateformes que TMDB
    /// renverra en bout de chaîne. Sans cet en-tête, une interface anglaise
    /// resterait posée sur des résumés français.
    ///
    /// L'en-tête plutôt qu'un paramètre : il vaut pour les `GET` comme pour les
    /// `POST`, et il n'oblige aucun corps de requête à se rallonger d'un champ.
    ///
    /// Elle joint aussi l'attestation de l'app. C'est ce qui distingue notre
    /// application d'un client fabriqué, et c'est la seule protection des points
    /// d'entrée que le backend laisse ouverts : le jeton utilisateur dit qui
    /// appelle, jamais depuis quoi, et un compte Firebase est gratuit à créer.
    ///
    /// `async` pour cette seule raison : obtenir le jeton peut demander un
    /// aller-retour au réseau. Il est mis en cache par le SDK et renouvelé bien
    /// avant son expiration, donc l'attente est nulle en régime établi.
    /// Une attestation indisponible ne bloque pas la requête : elle part sans
    /// l'en-tête, et c'est le serveur qui tranche selon son mode.
    init(backend url: URL) async {
        self.init(url: url)
        setValue(AppLanguage.current.tmdbTag, forHTTPHeaderField: "Accept-Language")
        if let attestation = await AppAttestation.token() {
            setValue(attestation, forHTTPHeaderField: "X-Firebase-AppCheck")
        }
    }
}
