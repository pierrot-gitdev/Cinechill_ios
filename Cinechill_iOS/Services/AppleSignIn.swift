//
//  AppleSignIn.swift
//  Cinechill_iOS
//

import AuthenticationServices
import CryptoKit
import Foundation
import UIKit

/// « Sign in with Apple », réduit à un `await`.
///
/// `ASAuthorizationController` ne connaît que les délégués : il faut donc un
/// objet Objective-C vivant le temps de la demande. Ce coordinateur se retient
/// lui-même jusqu'à la réponse, ce qui évite à l'appelant de le stocker quelque
/// part — un `Task` qui attend n'a aucune raison de garder un délégué en vie.
///
/// - Important: exige la capacité **Sign In with Apple** sur la cible dans
///   Xcode, et le fournisseur Apple activé dans la console Firebase. Sans elles
///   la feuille ne s'ouvre pas, et l'erreur remontée le dit.
@MainActor
final class AppleSignInCoordinator: NSObject {
    /// Le nonce brut, à transmettre tel quel à Firebase : c'est lui qui prouve
    /// que le jeton reçu répond bien à *cette* demande.
    private var rawNonce = ""
    private var proceed: CheckedContinuation<(token: String, nonce: String, fullName: PersonNameComponents?), Error>?
    private var retained: AppleSignInCoordinator?

    struct Result {
        let identityToken: String
        let rawNonce: String
        /// Apple ne renvoie le nom qu'à la **toute première** autorisation. Le
        /// perdre ici, c'est le perdre définitivement.
        let fullName: PersonNameComponents?
    }

    func run() async throws -> Result {
        let nonce = Self.makeNonce()
        rawNonce = nonce

        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self

        retained = self
        defer { retained = nil }

        let payload = try await withCheckedThrowingContinuation { continuation in
            proceed = continuation
            controller.performRequests()
        }
        return Result(
            identityToken: payload.token,
            rawNonce: payload.nonce,
            fullName: payload.fullName
        )
    }

    // MARK: Nonce

    private static func makeNonce(length: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        guard status == errSecSuccess else {
            // Sur un appareil incapable de produire de l'aléa, mieux vaut une
            // valeur exploitable qu'un crash au milieu d'une connexion.
            return UUID().uuidString + UUID().uuidString
        }
        let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(bytes.map { alphabet[Int($0) % alphabet.count] })
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

extension AppleSignInCoordinator: ASAuthorizationControllerDelegate {
    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        Task { @MainActor in
            guard
                let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let data = credential.identityToken,
                let token = String(data: data, encoding: .utf8)
            else {
                finish(.failure(AuthFailure.form(String(localized: "Connexion Apple incomplète.", bundle: .app))))
                return
            }
            finish(.success((token, rawNonce, credential.fullName)))
        }
    }

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        Task { @MainActor in
            finish(.failure(error))
        }
    }

    private func finish(
        _ result: Swift.Result<(token: String, nonce: String, fullName: PersonNameComponents?), Error>
    ) {
        guard let proceed else { return }
        self.proceed = nil
        proceed.resume(with: result)
    }
}

extension AppleSignInCoordinator: ASAuthorizationControllerPresentationContextProviding {
    nonisolated func presentationAnchor(
        for controller: ASAuthorizationController
    ) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first { $0.isKeyWindow } ?? ASPresentationAnchor()
        }
    }
}
