//
//  AppAttestation.swift
//  Cinechill_iOS
//

import Foundation
import FirebaseAppCheck
import FirebaseCore

/// Choisit de quoi l'app se sert pour prouver qu'elle est bien elle.
///
/// App Attest est le mécanisme fort : le Secure Enclave signe une attestation
/// qu'Apple contresigne, et qu'aucun client fabriqué ne peut produire. Il
/// demande iOS 14, une vraie puce, et donc un vrai appareil. La cible de l'app
/// étant iOS 17, il est toujours disponible : pas de repli sur DeviceCheck,
/// qui aurait en plus demandé de confier une clé privée à Firebase.
///
/// Le simulateur, lui, n'a pas de Secure Enclave. Sans le fournisseur de
/// débogage, tout le développement se ferait contre un backend qui refuse :
/// c'est la raison de la branche `DEBUG`, et la raison pour laquelle elle ne
/// doit jamais en sortir.
///
/// Le jeton de débogage n'est pas fixe. Il est tiré au hasard au premier
/// lancement et vit dans les préférences de l'app : réinstaller, changer
/// d'appareil ou d'équipe de signature en produit un nouveau, que la console
/// Firebase ne connaît pas. Le symptôme est un 403 « App attestation failed »
/// sur `exchangeDebugToken`, qui ressemble à une panne mais n'en est pas une.
/// Pour ressortir le jeton courant et le réenregistrer dans la console : lancer
/// avec l'argument `-FIRDebugEnabled`, la ligne « Firebase App Check Debug
/// Token » revient dans Xcode.
final class CinechillAppCheckProviderFactory: NSObject, AppCheckProviderFactory {
    func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
        #if DEBUG
        return AppCheckDebugProvider(app: app)
        #else
        return AppAttestProvider(app: app)
        #endif
    }
}

enum AppAttestation {
    /// À appeler **avant** `FirebaseApp.configure()`.
    ///
    /// L'ordre n'est pas un détail de style : Firebase instancie son fournisseur
    /// au moment de la configuration. Posé après, le réglage est ignoré sans
    /// bruit, et l'app envoie des requêtes sans attestation en croyant en
    /// envoyer.
    static func install() {
        AppCheck.setAppCheckProviderFactory(CinechillAppCheckProviderFactory())
    }

    /// Le jeton d'attestation à joindre à une requête backend, ou `nil`.
    ///
    /// Ne propage jamais son erreur. Un appareil hors ligne, une attestation
    /// refusée par Apple ou un jeton expiré ne doivent pas empêcher la requête
    /// de partir : c'est au serveur de décider quoi faire d'une requête sans
    /// jeton, et lui seul sait dans quel mode il tourne. Rendre l'app muette
    /// ici transformerait un durcissement côté serveur en panne côté client.
    static func token() async -> String? {
        do {
            return try await AppCheck.appCheck().token(forcingRefresh: false).token
        } catch {
            return nil
        }
    }
}
