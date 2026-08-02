import SwiftUI

struct SignUpView: View {
    @EnvironmentObject private var authService: AuthService
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var localErrorMessage: String?
    @State private var isLoading = false

    @FocusState private var focusedField: Field?
    private enum Field: Hashable { case email, password, confirm }

    var body: some View {
        ZStack {
            backgroundLayer

            ScrollView {
                VStack(spacing: 30) {
                    header
                    form
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var backgroundLayer: some View {
        ZStack {
            Color(red: 0.05, green: 0.05, blue: 0.09)
            RadialGradient(
                colors: [.pink.opacity(0.22), .clear],
                center: UnitPoint(x: 0.85, y: 0.05), startRadius: 10, endRadius: 420
            )
            RadialGradient(
                colors: [.indigo.opacity(0.22), .clear],
                center: UnitPoint(x: 0.1, y: 0.4), startRadius: 10, endRadius: 380
            )
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(LinearGradient(colors: [.indigo, .pink], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 76, height: 76)
                    .shadow(color: .indigo.opacity(0.4), radius: 20, y: 10)
                Image(systemName: "ticket.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
            }
            VStack(spacing: 6) {
                Text("Créer votre compte")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Rejoignez Cinechill et sauvegardez vos préférences")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var form: some View {
        VStack(spacing: 14) {
            AuthTextField(
                icon: "envelope.fill",
                placeholder: "Email",
                text: $email,
                keyboardType: .emailAddress,
                textContentType: .username,
                submitLabel: .next,
                onSubmit: { focusedField = .password }
            )
            .focused($focusedField, equals: .email)

            AuthSecureField(
                placeholder: "Mot de passe",
                text: $password,
                textContentType: .newPassword,
                submitLabel: .next,
                onSubmit: { focusedField = .confirm }
            )
            .focused($focusedField, equals: .password)

            AuthSecureField(
                placeholder: "Confirmer le mot de passe",
                text: $confirmPassword,
                textContentType: .newPassword,
                submitLabel: .go,
                onSubmit: { Task { await submitSignUp() } }
            )
            .focused($focusedField, equals: .confirm)

            if let localErrorMessage, !localErrorMessage.isEmpty {
                AuthErrorBanner(message: localErrorMessage)
            } else if let authError = authService.errorMessage, !authError.isEmpty {
                AuthErrorBanner(message: authError)
            }

            AuthPrimaryButton(title: "Créer mon compte", isLoading: isLoading) {
                Task { await submitSignUp() }
            }
        }
        .padding(22)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.1), lineWidth: 1)
        )
    }

    private func submitSignUp() async {
        localErrorMessage = nil
        authService.clearError()

        guard password == confirmPassword else {
            localErrorMessage = "Les mots de passe ne correspondent pas."
            return
        }

        isLoading = true
        defer { isLoading = false }
        do {
            try await authService.signUp(email: email, password: password)
            dismiss()
        } catch {
            // Error already surfaced by service.
        }
    }
}

#Preview {
    NavigationStack {
        SignUpView()
            .environmentObject(AuthService())
    }
}
