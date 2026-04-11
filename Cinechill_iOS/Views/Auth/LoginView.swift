import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var authService: AuthService

    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color.black, Color(red: 0.12, green: 0.02, blue: 0.04)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                    .ignoresSafeArea()

                VStack(spacing: 24) {
                    VStack(spacing: 10) {
                        Image(systemName: "popcorn.fill")
                            .font(.system(size: 34))
                            .foregroundStyle(.white)
                        Text("Cinechill")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text("Connectez-vous pour continuer votre séance")
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

                        if let error = authService.errorMessage, !error.isEmpty {
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Button {
                            Task { await submitEmailFlow() }
                        } label: {
                            Text("Se connecter")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(red: 0.78, green: 0.1, blue: 0.14))
                        .disabled(isLoading)

                        Button {
                            Task { await submitGoogleFlow() }
                        } label: {
                            Label("Continuer avec Google", systemImage: "g.circle.fill")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.bordered)
                        .tint(.white)
                        .disabled(isLoading)

                        if isLoading {
                            ProgressView("Chargement…")
                                .tint(.white)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(20)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                    NavigationLink("Créer un compte", destination: SignUpView())
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                }
                .padding()
            }
            .navigationTitle("Connexion")
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
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

