//
//  AuthComponents.swift
//  Cinechill_iOS
//

import SwiftUI

/// Champ de saisie stylé pour les écrans d'authentification : icône, fond verre dépoli,
/// bordure qui passe en dégradé au focus. Partagé entre login et inscription pour que les
/// deux écrans restent visuellement identiques sans dupliquer le style.
struct AuthTextField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType?
    var submitLabel: SubmitLabel = .next
    var onSubmit: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.white.opacity(0.55))
                .frame(width: 20)
            TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(.white.opacity(0.4)))
                .foregroundStyle(.white)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(keyboardType)
                .textContentType(textContentType)
                .submitLabel(submitLabel)
                .onSubmit { onSubmit?() }
        }
        .padding(14)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        )
    }
}

/// Variante mot de passe avec bouton "afficher / masquer" — ergonomie attendue sur un champ
/// de mot de passe, absente du champ `SecureField` d'origine.
struct AuthSecureField: View {
    let placeholder: String
    @Binding var text: String
    var textContentType: UITextContentType?
    var submitLabel: SubmitLabel = .done
    var onSubmit: (() -> Void)?

    @State private var isRevealed = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.fill")
                .foregroundStyle(.white.opacity(0.55))
                .frame(width: 20)
            Group {
                if isRevealed {
                    TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(.white.opacity(0.4)))
                } else {
                    SecureField("", text: $text, prompt: Text(placeholder).foregroundStyle(.white.opacity(0.4)))
                }
            }
            .foregroundStyle(.white)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .textContentType(textContentType)
            .submitLabel(submitLabel)
            .onSubmit { onSubmit?() }

            Button {
                isRevealed.toggle()
            } label: {
                Image(systemName: isRevealed ? "eye.slash.fill" : "eye.fill")
                    .foregroundStyle(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        )
    }
}

/// CTA principal en pilule dégradée — même langage visuel que les boutons CinéMatch, pour que
/// l'app se sente cohérente dès le premier écran.
struct AuthPrimaryButton: View {
    let title: String
    var isLoading: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if isLoading {
                    CinechillSpinner(size: 22, tint: .onAccent)
                } else {
                    Text(title).font(.headline)
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                Capsule().fill(LinearGradient(colors: [.indigo, .pink], startPoint: .leading, endPoint: .trailing))
            )
            .shadow(color: .indigo.opacity(0.35), radius: 16, y: 8)
        }
        .buttonStyle(PressableScaleStyle(scale: 0.97))
        .disabled(isLoading)
    }
}

/// Bannière d'erreur — plus visible et plus lisible qu'un simple texte rouge sur fond sombre.
struct AuthErrorBanner: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote.weight(.medium))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.red.opacity(0.22), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.red.opacity(0.4), lineWidth: 1)
            )
    }
}
