import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var authService: AuthService

    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false

    @FocusState private var focusedField: Field?
    private enum Field: Hashable { case email, password }

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundLayer

                ScrollView {
                    VStack(spacing: 30) {
                        header
                        form
                        signUpLink
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 48)
                    .padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationBarHidden(true)
        }
    }

    private var backgroundLayer: some View {
        ZStack {
            Color(red: 0.05, green: 0.05, blue: 0.09)
            RadialGradient(
                colors: [.indigo.opacity(0.28), .clear],
                center: UnitPoint(x: 0.15, y: 0.05), startRadius: 10, endRadius: 420
            )
            RadialGradient(
                colors: [.pink.opacity(0.18), .clear],
                center: UnitPoint(x: 0.9, y: 0.42), startRadius: 10, endRadius: 380
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
                Image(systemName: "popcorn.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(.white)
            }
            VStack(spacing: 6) {
                Text("Cinechill")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Connectez-vous pour continuer votre séance")
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
                textContentType: .password,
                submitLabel: .go,
                onSubmit: { Task { await submitEmailFlow() } }
            )
            .focused($focusedField, equals: .password)

            if let error = authService.errorMessage, !error.isEmpty {
                AuthErrorBanner(message: error)
            }

            AuthPrimaryButton(title: "Se connecter", isLoading: isLoading) {
                Task { await submitEmailFlow() }
            }

            dividerRow

            googleButton
        }
        .padding(22)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.1), lineWidth: 1)
        )
    }

    private var dividerRow: some View {
        HStack(spacing: 10) {
            Rectangle().fill(.white.opacity(0.15)).frame(height: 1)
            Text("ou")
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.4))
            Rectangle().fill(.white.opacity(0.15)).frame(height: 1)
        }
        .padding(.vertical, 2)
    }

    private var googleButton: some View {
        Button {
            Task { await submitGoogleFlow() }
        } label: {
            Label("Continuer avec Google", systemImage: "g.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(.white.opacity(0.08), in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.15), lineWidth: 1))
        }
        .buttonStyle(PressableScaleStyle(scale: 0.97))
        .disabled(isLoading)
    }

    private var signUpLink: some View {
        HStack(spacing: 4) {
            Text("Pas encore de compte ?")
                .foregroundStyle(.white.opacity(0.6))
            NavigationLink("Créer un compte", destination: SignUpView())
                .foregroundStyle(.white)
                .fontWeight(.semibold)
        }
        .font(.subheadline)
    }

    private func submitEmailFlow() async {
        isLoading = true
        authService.clearError()
        defer { isLoading = false }

        do {
            try await authService.signIn(email: email, password: password)
        } catch {
            // Error already surfaced by service.
        }
    }

    private func submitGoogleFlow() async {
        isLoading = true
        authService.clearError()
        defer { isLoading = false }
        do {
            try await authService.signInWithGoogle()
        } catch {
            // Error already surfaced by service.
        }
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthService())
}
