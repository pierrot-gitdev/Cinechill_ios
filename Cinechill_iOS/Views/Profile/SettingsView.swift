import SwiftUI
import PhotosUI
import FirebaseAuth

struct SettingsView: View {
    @EnvironmentObject private var profileStore: UserProfileStore
    @EnvironmentObject private var authService: AuthService
    @Environment(\.dismiss) private var dismiss

    @State private var nameField: String = ""
    @State private var isSavingName = false
    @State private var nameError: String?
    @State private var photoItem: PhotosPickerItem?
    @State private var showRemovePhotoAlert = false
    @FocusState private var nameFieldFocused: Bool

    private var email: String? { Auth.auth().currentUser?.email }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    heroCard

                    if profileStore.customPhotoData != nil {
                        SettingsCard {
                            SettingsRow(icon: "trash.fill", color: .red, title: "Supprimer la photo", role: .destructive) {
                                showRemovePhotoAlert = true
                            }
                        }
                    }

                    signOutButton

                    Text(appVersion)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Réglages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .padding(7)
                            .background(Color(.tertiarySystemFill), in: Circle())
                    }
                }
            }
        }
        .onAppear { nameField = profileStore.displayName }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await loadPhoto(from: item) }
        }
        .alert("Supprimer la photo", isPresented: $showRemovePhotoAlert) {
            Button("Supprimer", role: .destructive) { profileStore.removeCustomPhoto() }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("La photo de profil sera supprimée.")
        }
    }

    // MARK: - Hero Card

    /// Avatar + nom en carte dégradée, moment d'ouverture de l'écran — le nom s'enregistre
    /// automatiquement en quittant le champ, sans bouton dédié.
    private var heroCard: some View {
        VStack(spacing: 16) {
            PhotosPicker(selection: $photoItem, matching: .images) {
                ZStack(alignment: .bottomTrailing) {
                    currentAvatar
                        .frame(width: 100, height: 100)
                        .clipShape(Circle())
                        .overlay(
                            Circle().strokeBorder(
                                LinearGradient(colors: [.indigo, .pink], startPoint: .topLeading, endPoint: .bottomTrailing),
                                lineWidth: 3
                            )
                        )
                        .shadow(color: .indigo.opacity(0.25), radius: 18, y: 10)

                    Image(systemName: "camera.fill")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(
                            Circle().fill(
                                LinearGradient(colors: [.indigo, .pink], startPoint: .top, endPoint: .bottom)
                            )
                        )
                        .overlay(Circle().strokeBorder(Color(.secondarySystemGroupedBackground), lineWidth: 3))
                }
            }
            .buttonStyle(PressableScaleStyle(scale: 0.95))

            VStack(spacing: 6) {
                TextField("Nom d'affichage", text: $nameField)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .autocorrectionDisabled()
                    .focused($nameFieldFocused)
                    .submitLabel(.done)
                    .onSubmit { Task { await saveNameIfNeeded() } }

                if let email {
                    Text(email)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if isSavingName {
                GradientSpinner(size: 16, lineWidth: 2, colors: [.indigo, .pink.opacity(0.1)])
            } else if let nameError {
                Text(nameError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 20)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.indigo.opacity(0.10), .pink.opacity(0.06)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 20, y: 10)
        .onChange(of: nameFieldFocused) { wasFocused, isFocused in
            if wasFocused, !isFocused { Task { await saveNameIfNeeded() } }
        }
    }

    @ViewBuilder
    private var currentAvatar: some View {
        if let data = profileStore.avatarData, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage).resizable().scaledToFill()
        } else if let url = profileStore.avatarURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFill()
                default: placeholderAvatar
                }
            }
        } else {
            placeholderAvatar
        }
    }

    private var placeholderAvatar: some View {
        Image(systemName: "person.circle.fill")
            .resizable()
            .foregroundStyle(Color(.systemGray3))
    }

    // MARK: - Sign Out

    private var signOutButton: some View {
        Button(role: .destructive) {
            try? authService.signOut()
            dismiss()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.body.weight(.semibold))
                Text("Déconnexion")
                    .font(.headline)
            }
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.red.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(PressableScaleStyle(scale: 0.97))
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "Cinechill · version \(version) (\(build))"
    }

    // MARK: - Actions

    private func saveNameIfNeeded() async {
        let trimmed = nameField.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != profileStore.displayName else { return }
        nameError = nil
        isSavingName = true
        defer { isSavingName = false }
        do {
            try await profileStore.updateDisplayName(trimmed)
        } catch {
            nameError = error.localizedDescription
        }
    }

    private func loadPhoto(from item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        // Resize to keep UserDefaults storage reasonable (~200KB)
        if let uiImage = UIImage(data: data),
           let resized = uiImage.resized(toMaxDimension: 400),
           let jpeg = resized.jpegData(compressionQuality: 0.7) {
            profileStore.setCustomPhoto(jpeg)
        } else {
            profileStore.setCustomPhoto(data)
        }
    }
}

// MARK: - Reusable card components

/// Carte arrondie regroupant une ou plusieurs `SettingsRow` — remplace les sections `Form`
/// par un conteneur au style plus affirmé, cohérent avec le reste de l'app.
private struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            )
    }
}

/// Ligne d'action avec badge d'icône colorée — cible tactile généreuse (~56pt) pour rester
/// ergonomique malgré le style plus dense d'une carte personnalisée.
private struct SettingsRow: View {
    let icon: String
    let color: Color
    let title: String
    var role: ButtonRole?
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: 14) {
                SettingsIconBadge(systemName: icon, color: color)
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(role == .destructive ? Color.red : Color.primary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableScaleStyle(scale: 0.98))
    }
}

/// Icône colorée en carré arrondi, façon lignes de l'app Réglages iOS.
private struct SettingsIconBadge: View {
    let systemName: String
    let color: Color

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(color, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private extension UIImage {
    func resized(toMaxDimension max: CGFloat) -> UIImage? {
        let scale = min(max / size.width, max / size.height, 1)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}
