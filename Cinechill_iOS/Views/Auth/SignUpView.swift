import SwiftUI

struct SignUpView: View {
    @EnvironmentObject private var authService: AuthService
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var localErrorMessage: String?
    @State private var isLoading = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color(red: 0.12, green: 0.02, blue: 0.04)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                VStack(spacing: 10) {
                    Image(systemName: "ticket.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(.white)
                    Text("Créer votre compte")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Rejoignez Cinechill et sauvegardez vos préférences")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 14) {
                    TextField("Email", text: $email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .padding(12)
                        .foregroundStyle(.white)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))

                    SecureField("Mot de passe", text: $password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(12)
                        .foregroundStyle(.white)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))

                    SecureField("Confirmer le mot de passe", text: $confirmPassword)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(12)
                        .foregroundStyle(.white)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))

                    if let localErrorMessage, !localErrorMessage.isEmpty {
                        Text(localErrorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else if let authError = authService.errorMessage, !authError.isEmpty {
                        Text(authError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button {
                        Task { await submitSignUp() }
                    } label: {
                        Text("Créer mon compte")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.78, green: 0.1, blue: 0.14))
                    .disabled(isLoading)

                    if isLoading {
                        ProgressView("Création…")
                            .tint(.white)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(20)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .padding()
        }
        .navigationTitle("Inscription")
        .toolbarColorScheme(.dark, for: .navigationBar)
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

