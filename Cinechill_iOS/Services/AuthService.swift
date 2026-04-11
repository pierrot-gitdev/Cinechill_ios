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

enum AuthServiceError: LocalizedError {
    case sdkMissing
    case invalidEmail
    case emptyPassword
    case missingGoogleClientID
    case missingRootViewController
    case missingGoogleIDToken

    var errorDescription: String? {
        switch self {
        case .sdkMissing:
            return "SDK FirebaseAuth/GoogleSignIn manquant dans la cible iOS."
        case .invalidEmail:
            return "Veuillez saisir un email valide."
        case .emptyPassword:
            return "Veuillez saisir un mot de passe."
        case .missingGoogleClientID:
            return "Configuration Google Sign-In invalide (client ID manquant)."
        case .missingRootViewController:
            return "Impossible d’ouvrir Google Sign-In (root view introuvable)."
        case .missingGoogleIDToken:
            return "Google Sign-In incomplet (ID token manquant)."
        }
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

    func signIn(email: String, password: String) async throws {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalizedEmail.contains("@"), normalizedEmail.contains(".") else {
            throw setAndReturn(AuthServiceError.invalidEmail)
        }
        guard !password.isEmpty else {
            throw setAndReturn(AuthServiceError.emptyPassword)
        }

#if canImport(FirebaseAuth)
        do {
            _ = try await Auth.auth().signIn(withEmail: normalizedEmail, password: password)
            errorMessage = nil
        } catch {
            throw setAndReturn(error)
        }
#else
        throw setAndReturn(AuthServiceError.sdkMissing)
#endif
    }

    func signUp(email: String, password: String) async throws {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalizedEmail.contains("@"), normalizedEmail.contains(".") else {
            throw setAndReturn(AuthServiceError.invalidEmail)
        }
        guard !password.isEmpty else {
            throw setAndReturn(AuthServiceError.emptyPassword)
        }

#if canImport(FirebaseAuth)
        do {
            _ = try await Auth.auth().createUser(withEmail: normalizedEmail, password: password)
            errorMessage = nil
        } catch {
            throw setAndReturn(error)
        }
#else
        throw setAndReturn(AuthServiceError.sdkMissing)
#endif
    }

    func signInWithGoogle() async throws {
#if canImport(FirebaseAuth) && canImport(GoogleSignIn)
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            throw setAndReturn(AuthServiceError.missingGoogleClientID)
        }
        guard let rootViewController = Self.rootViewController else {
            throw setAndReturn(AuthServiceError.missingRootViewController)
        }

        let configuration = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = configuration

        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController)
            guard let idToken = result.user.idToken?.tokenString else {
                throw AuthServiceError.missingGoogleIDToken
            }
            let accessToken = result.user.accessToken.tokenString
            let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: accessToken)
            _ = try await Auth.auth().signIn(with: credential)
            errorMessage = nil
        } catch {
            throw setAndReturn(error)
        }
#else
        throw setAndReturn(AuthServiceError.sdkMissing)
#endif
    }

    func signOut() throws {
#if canImport(FirebaseAuth)
        do {
            try Auth.auth().signOut()
            errorMessage = nil
        } catch {
            throw setAndReturn(error)
        }
#else
        throw setAndReturn(AuthServiceError.sdkMissing)
#endif
    }

    @discardableResult
    private func setAndReturn(_ error: Error) -> Error {
        errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        return error
    }

    private static var rootViewController: UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
    }
}

