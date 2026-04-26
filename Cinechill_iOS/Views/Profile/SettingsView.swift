import SwiftUI
import PhotosUI

struct SettingsView: View {
    @EnvironmentObject private var profileStore: UserProfileStore
    @EnvironmentObject private var authService: AuthService
    @Environment(\.dismiss) private var dismiss

    @State private var nameField: String = ""
    @State private var isSavingName = false
    @State private var nameError: String?
    @State private var photoItem: PhotosPickerItem?
    @State private var showRemovePhotoAlert = false

    var body: some View {
        NavigationStack {
            Form {
                photoSection
                profileSection
                accountSection
            }
            .navigationTitle("Réglages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Fermer") { dismiss() }
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

    // MARK: - Photo Section

    private var photoSection: some View {
        Section {
            HStack {
                Spacer()
                currentAvatar
                    .frame(width: 80, height: 80)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Color(.systemGray4), lineWidth: 2))
                Spacer()
            }
            .listRowBackground(Color.clear)
            .padding(.vertical, 8)

            PhotosPicker(selection: $photoItem, matching: .images) {
                Label("Changer la photo", systemImage: "photo")
            }

            if profileStore.customPhotoData != nil {
                Button(role: .destructive) {
                    showRemovePhotoAlert = true
                } label: {
                    Label("Supprimer la photo", systemImage: "trash")
                }
            }
        } header: {
            Text("Photo de profil")
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

    // MARK: - Profile Section

    private var profileSection: some View {
        Section {
            TextField("Nom d'affichage", text: $nameField)
                .autocorrectionDisabled()

            if let nameError {
                Text(nameError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button {
                Task { await saveName() }
            } label: {
                HStack {
                    Text("Enregistrer le nom")
                    Spacer()
                    if isSavingName {
                        ProgressView()
                    }
                }
            }
            .disabled(nameField.trimmingCharacters(in: .whitespaces).isEmpty || isSavingName)
        } header: {
            Text("Profil")
        }
    }

    // MARK: - Account Section

    private var accountSection: some View {
        Section {
            Button(role: .destructive) {
                try? authService.signOut()
                dismiss()
            } label: {
                Label("Déconnexion", systemImage: "rectangle.portrait.and.arrow.right")
            }
        } header: {
            Text("Compte")
        }
    }

    // MARK: - Actions

    private func saveName() async {
        nameError = nil
        isSavingName = true
        defer { isSavingName = false }
        do {
            try await profileStore.updateDisplayName(nameField)
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

private extension UIImage {
    func resized(toMaxDimension max: CGFloat) -> UIImage? {
        let scale = min(max / size.width, max / size.height, 1)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}
