//
//  AuthService.swift
//  Cinechill_iOS
//

import AuthenticationServices
import Foundation
import Combine
import FirebaseCore
#if canImport(FirebaseAuth)
import FirebaseAuth
#endif
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif
import UIKit

// MARK: - L'erreur, rattachée à un champ

/// Le champ que l'utilisateur doit corriger. `form` désigne les pannes qui ne
/// viennent d'aucune saisie — réseau, quota, compte désactivé : elles se posent
/// au-dessus des actions, pas sous un champ.
enum AuthField: Equatable {
    case name
    case handle
    case email
    case password
    case confirmation
    case form
}

/// Le geste de réparation proposé dans la phrase d'erreur. Une erreur qui dit
/// ce qui ne va pas sans dire quoi faire oblige l'utilisateur à deviner.
enum AuthRepair: Equatable {
    case resetPassword
    case signIn
    case signUp
}

/// Une panne d'authentification, telle que l'écran doit la montrer.
///
/// Firebase renvoie des messages anglais et techniques ; les afficher tels
/// quels, c'est faire lire à l'utilisateur un code d'erreur en prose. On les
/// traduit ici une fois pour toutes, et surtout on les **rattache à un champ** :
/// c'est ce rattachement, pas la formulation, qui rend une erreur réparable.
struct AuthFailure: LocalizedError, Equatable {
    let field: AuthField
    let message: String
    var repair: AuthRepair?

    var errorDescription: String? { message }

    static func form(_ message: String) -> AuthFailure {
        AuthFailure(field: .form, message: message)
    }
}

@MainActor
final class AuthService: ObservableObject {
#if canImport(FirebaseAuth)
    @Published private(set) var firebaseUser: FirebaseAuth.User?
#else
    @Published private(set) var firebaseUser: Any?
#endif
    @Published private(set) var isInitializing = true

    /// Conservé pour les écrans qui affichent encore une panne globale (réglages,
    /// déconnexion). Le parcours d'authentification, lui, lit `AuthFailure`.
    @Published private(set) var errorMessage: String?

#if canImport(FirebaseAuth)
    private var authStateHandle: AuthStateDidChangeListenerHandle?
#endif

    var isAuthenticated: Bool {
#if canImport(FirebaseAuth)
        firebaseUser != nil
#else
        false
#endif
    }

    init() {
#if canImport(FirebaseAuth)
        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self else { return }
            Task { @MainActor in
                self.firebaseUser = user
                self.isInitializing = false
            }
        }
#else
        isInitializing = false
#endif
    }

    deinit {
#if canImport(FirebaseAuth)
        if let authStateHandle {
            Auth.auth().removeStateDidChangeListener(authStateHandle)
        }
#endif
    }

    func clearError() {
        errorMessage = nil
    }

    // MARK: - Connexion et création

    func signIn(email: String, password: String) async throws {
        let address = Self.normalize(email)
        guard Self.isPlausibleEmail(address) else {
            throw fail(AuthFailure(field: .email, message: "Cette adresse n'est pas valide."))
        }
        guard !password.isEmpty else {
            throw fail(AuthFailure(field: .password, message: "Saisissez votre mot de passe."))
        }

#if canImport(FirebaseAuth)
        do {
            _ = try await Auth.auth().signIn(withEmail: address, password: password)
            errorMessage = nil
        } catch {
            throw fail(Self.translate(error, during: .signIn))
        }
#else
        throw fail(Self.sdkMissing)
#endif
    }

    func signUp(email: String, password: String) async throws {
        let address = Self.normalize(email)
        guard Self.isPlausibleEmail(address) else {
            throw fail(AuthFailure(field: .email, message: "Cette adresse n'est pas valide."))
        }
        guard password.count >= 8 else {
            throw fail(AuthFailure(field: .password, message: "8 caractères au minimum."))
        }

#if canImport(FirebaseAuth)
        do {
            _ = try await Auth.auth().createUser(withEmail: address, password: password)
            errorMessage = nil
        } catch {
            throw fail(Self.translate(error, during: .signUp))
        }
#else
        throw fail(Self.sdkMissing)
#endif
    }

    /// Reporte le nom déclaré à l'inscription sur le compte Firebase. Le profil
    /// public, lui, est écrit par `SocialStore` — les deux sont distincts et le
    /// restent.
    func updateDisplayName(_ name: String) async {
#if canImport(FirebaseAuth)
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let user = Auth.auth().currentUser else { return }
        let request = user.createProfileChangeRequest()
        request.displayName = trimmed
        try? await request.commitChanges()
#endif
    }

    // MARK: - Mot de passe oublié

    /// Demande l'envoi du lien de réinitialisation.
    ///
    /// Ne dit jamais si l'adresse existe, et ne le peut pas : avec la protection
    /// contre l'énumération des comptes activée (elle l'est par défaut), Firebase
    /// réussit dans les deux cas. L'écran de confirmation est donc formulé au
    /// conditionnel — ce n'est pas une prudence de rédaction, c'est la vérité de
    /// ce que l'appel garantit.
    func sendPasswordReset(email: String) async throws {
        let address = Self.normalize(email)
        guard Self.isPlausibleEmail(address) else {
            throw fail(AuthFailure(field: .email, message: "Cette adresse n'est pas valide."))
        }

#if canImport(FirebaseAuth)
        do {
            try await Auth.auth().sendPasswordReset(withEmail: address)
            errorMessage = nil
        } catch {
            throw fail(Self.translate(error, during: .reset))
        }
#else
        throw fail(Self.sdkMissing)
#endif
    }

    /// Vérifie le code reçu par email et renvoie l'adresse concernée, qu'on
    /// affiche sur l'écran de saisie : sans elle, on demande un mot de passe
    /// sans dire pour quel compte.
    @discardableResult
    func verifyResetCode(_ code: String) async throws -> String {
#if canImport(FirebaseAuth)
        do {
            let email = try await Auth.auth().verifyPasswordResetCode(code)
            errorMessage = nil
            return email
        } catch {
            throw fail(Self.translate(error, during: .reset))
        }
#else
        throw fail(Self.sdkMissing)
#endif
    }

    /// Applique le nouveau mot de passe.
    ///
    /// Ne connecte pas l'utilisateur — c'est le comportement de Firebase, et
    /// c'est pourquoi l'écran de réussite renvoie vers la connexion plutôt que
    /// vers l'application.
    func confirmPasswordReset(code: String, newPassword: String) async throws {
        guard newPassword.count >= 8 else {
            throw fail(AuthFailure(field: .password, message: "8 caractères au minimum."))
        }
#if canImport(FirebaseAuth)
        do {
            try await Auth.auth().confirmPasswordReset(withCode: code, newPassword: newPassword)
            errorMessage = nil
        } catch {
            throw fail(Self.translate(error, during: .reset))
        }
#else
        throw fail(Self.sdkMissing)
#endif
    }

    /// Extrait le code d'action d'un lien de réinitialisation.
    ///
    /// Ne renvoie un code que si le mode est bien `resetPassword` : le même
    /// paramètre `oobCode` sert aussi à la vérification d'adresse, et confondre
    /// les deux mènerait l'utilisateur sur un écran qui ne peut pas aboutir.
    ///
    /// - Important: pour que ce chemin soit atteint, il faut une URL d'action
    ///   personnalisée dans la console Firebase **et** un lien universel déclaré
    ///   dans les entitlements. Sans cette configuration, Firebase ouvre sa page
    ///   web et le parcours s'arrête à l'écran « lien envoyé ».
    nonisolated static func passwordResetCode(from url: URL) -> String? {
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else {
            return nil
        }
        let value = { (name: String) in items.first { $0.name == name }?.value }
        guard value("mode") == "resetPassword" else { return nil }
        guard let code = value("oobCode"), !code.isEmpty else { return nil }
        return code
    }

    // MARK: - Apple

    /// La règle 4.8 de l'App Store impose une option de connexion respectueuse
    /// de la vie privée dès lors qu'une connexion tierce est proposée — et
    /// Google Sign-In est déjà en place.
    ///
    /// Apple ne transmet le nom qu'à la toute première autorisation : on le
    /// reporte donc immédiatement sur le compte, faute de quoi il est perdu
    /// pour de bon. Le pseudo, lui, reste à choisir dans le profil : aucun
    /// fournisseur tiers n'en fournit.
    func signInWithApple() async throws {
#if canImport(FirebaseAuth)
        do {
            let apple = try await AppleSignInCoordinator().run()
            let credential = OAuthProvider.appleCredential(
                withIDToken: apple.identityToken,
                rawNonce: apple.rawNonce,
                fullName: apple.fullName
            )
            let result = try await Auth.auth().signIn(with: credential)
            errorMessage = nil

            if result.user.displayName?.isEmpty != false, let components = apple.fullName {
                let name = PersonNameComponentsFormatter.localizedString(
                    from: components, style: .default
                )
                await updateDisplayName(name)
            }
        } catch let failure as AuthFailure {
            throw fail(failure)
        } catch {
            // Un refus de la feuille n'est pas une panne : on ne laisse pas un
            // bandeau d'erreur derrière un geste volontaire.
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            throw fail(Self.translate(error, during: .signIn))
        }
#else
        throw fail(Self.sdkMissing)
#endif
    }

    // MARK: - Google

    func signInWithGoogle() async throws {
#if canImport(FirebaseAuth) && canImport(GoogleSignIn)
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            throw fail(.form("Configuration Google Sign-In invalide."))
        }
        guard let rootViewController = Self.rootViewController else {
            throw fail(.form("Impossible d'ouvrir Google Sign-In."))
        }

        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)

        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController)
            guard let idToken = result.user.idToken?.tokenString else {
                throw AuthFailure.form("Google Sign-In incomplet.")
            }
            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: result.user.accessToken.tokenString
            )
            _ = try await Auth.auth().signIn(with: credential)
            errorMessage = nil
        } catch let failure as AuthFailure {
            throw fail(failure)
        } catch {
            // L'annulation de la feuille Google n'est pas une panne : on ne
            // laisse pas un bandeau d'erreur derrière un geste volontaire.
            if (error as NSError).code == GIDSignInError.Code.canceled.rawValue { return }
            throw fail(Self.translate(error, during: .signIn))
        }
#else
        throw fail(Self.sdkMissing)
#endif
    }

    func signOut() throws {
#if canImport(FirebaseAuth)
        do {
            try Auth.auth().signOut()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
#else
        throw Self.sdkMissing
#endif
    }

    // MARK: - Traduction

    private enum Operation { case signIn, signUp, reset }

    private static let sdkMissing = AuthFailure.form("SDK Firebase manquant dans la cible iOS.")

    /// Les seuls codes Firebase qu'on rencontre réellement sur ce parcours.
    ///
    /// Le reste tombe dans un message générique volontairement court : allonger
    /// la liste pour couvrir des cas qui n'arrivent pas revient à maintenir du
    /// texte que personne ne lira jamais.
    private static func translate(_ error: Error, during operation: Operation) -> AuthFailure {
#if canImport(FirebaseAuth)
        let code = (error as NSError).code

        switch code {
        case AuthErrorCode.invalidEmail.rawValue:
            return AuthFailure(field: .email, message: "Cette adresse n'est pas valide.")

        case AuthErrorCode.emailAlreadyInUse.rawValue:
            return AuthFailure(
                field: .email,
                message: "Un compte existe déjà pour cette adresse.",
                repair: .signIn
            )

        case AuthErrorCode.userNotFound.rawValue:
            // À la réinitialisation, ce code ne remonte que si la protection
            // contre l'énumération est désactivée en console — et dans ce cas
            // proposer de créer un compte n'aurait pas de sens : on est venu
            // récupérer le sien.
            return AuthFailure(
                field: .email,
                message: "Aucun compte pour cette adresse.",
                repair: operation == .reset ? nil : .signUp
            )

        case AuthErrorCode.wrongPassword.rawValue,
             AuthErrorCode.invalidCredential.rawValue:
            // Firebase ne distingue plus « mauvais mot de passe » de « compte
            // inconnu » : la phrase ne doit donc pas prétendre le contraire.
            return AuthFailure(
                field: .password,
                message: "Email ou mot de passe incorrect.",
                repair: .resetPassword
            )

        case AuthErrorCode.weakPassword.rawValue:
            return AuthFailure(field: .password, message: "8 caractères au minimum.")

        case AuthErrorCode.expiredActionCode.rawValue,
             AuthErrorCode.invalidActionCode.rawValue:
            return AuthFailure(field: .form, message: "Ce lien a expiré ou a déjà servi.")

        case AuthErrorCode.userDisabled.rawValue:
            return AuthFailure(field: .form, message: "Ce compte a été désactivé.")

        case AuthErrorCode.tooManyRequests.rawValue:
            return AuthFailure(
                field: .form,
                message: "Trop de tentatives. Réessayez dans quelques minutes."
            )

        case AuthErrorCode.networkError.rawValue:
            return AuthFailure(field: .form, message: "Connexion au serveur impossible.")

        default:
            return AuthFailure(field: .form, message: "Connexion au serveur impossible.")
        }
#else
        return sdkMissing
#endif
    }

    /// Une seule porte de sortie pour les erreurs : elle publie le message et
    /// renvoie la panne, si bien qu'aucun appelant ne peut oublier l'un des deux.
    @discardableResult
    private func fail(_ failure: AuthFailure) -> AuthFailure {
        errorMessage = failure.message
        return failure
    }

    // MARK: - Saisie

    static func normalize(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Vérification volontairement grossière : le seul juge de la validité d'une
    /// adresse est le serveur qui lui envoie un message. Refuser ici ne sert qu'à
    /// éviter un aller-retour sur une faute évidente.
    static func isPlausibleEmail(_ address: String) -> Bool {
        guard let at = address.firstIndex(of: "@"), at != address.startIndex else { return false }
        let domain = address[address.index(after: at)...]
        return !domain.isEmpty
            && domain.contains(".")
            && !domain.hasPrefix(".")
            && !domain.hasSuffix(".")
            && !address.contains(" ")
            && address.filter { $0 == "@" }.count == 1
    }

    private static var rootViewController: UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
    }
}
