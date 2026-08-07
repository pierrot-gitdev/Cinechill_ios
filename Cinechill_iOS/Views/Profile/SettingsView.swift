import SwiftUI
import PhotosUI
import FirebaseAuth

/// Les réglages — « Le Profil ».
///
/// L'endroit où l'app apprend de vous directement, au lieu de tout déduire de
/// vos swipes. Trois déclarations alimentent le reste de l'app : les
/// abonnements (accueil, CinéMatch, watchlist, fiche), les genres bannis
/// (filtre dur partout) et la génération (calibre le score « probablement vu »).
struct SettingsView: View {
    @EnvironmentObject private var profileStore: UserProfileStore
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var libraryStore: LibraryStore
    @Environment(MediaCatalog.self) private var catalog
    @Environment(\.dismiss) private var dismiss

    @State private var nameField: String = ""
    @State private var isSavingName = false
    @State private var nameError: String?
    @State private var photoItem: PhotosPickerItem?
    @State private var showRemovePhotoAlert = false
    @State private var showResetSkipsAlert = false
    @State private var showDeleteAccountAlert = false
    @State private var pendingSkips: Int?
    @State private var isWorking = false
    @State private var actionMessage: String?

    private var email: String? { Auth.auth().currentUser?.email }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    profileHeader
                    subscriptionsSection
                    bannedGenresSection
                    generationSection
                    dataSection
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
        .task {
            nameField = profileStore.displayName
            await catalog.loadIfNeeded()
            pendingSkips = await libraryStore.pendingSkipCount()
        }
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
        .alert("Remettre les films en jeu", isPresented: $showResetSkipsAlert) {
            Button("Réinitialiser") { Task { await resetSkips() } }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Les films que vous avez écartés au swipe vous seront à nouveau proposés.")
        }
        .alert("Supprimer votre compte", isPresented: $showDeleteAccountAlert) {
            Button("Supprimer définitivement", role: .destructive) {
                Task { await deleteAccount() }
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Votre galerie, votre watchlist et votre profil seront effacés. Cette action est irréversible.")
        }
    }

    // MARK: - Abonnements

    private var subscriptionsSection: some View {
        SettingsSection(
            title: "MES ABONNEMENTS",
            hint: libraryStore.preferredPlatformIDs.isEmpty
                ? "Déclarez vos abonnements pour que l'app ne vous propose que ce que vous pouvez vraiment regarder."
                : "Utilisés pour l'accueil, CinéMatch, votre watchlist et les fiches films."
        ) {
            if catalog.platforms.isEmpty {
                HStack {
                    CinechillSpinner(size: 18)
                    Text("Chargement des plateformes…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 9), count: 4), spacing: 9) {
                    ForEach(catalog.platforms) { platform in
                        platformCell(platform)
                    }
                }
                .padding(14)
            }
        }
    }

    private func platformCell(_ platform: StreamingPlatform) -> some View {
        let isOn = libraryStore.preferredPlatformIDs.contains(platform.id)
        return Button {
            Haptics.selection()
            var ids = libraryStore.preferredPlatformIDs
            if isOn { ids.remove(platform.id) } else { ids.insert(platform.id) }
            libraryStore.setPreferredPlatforms(ids)
        } label: {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let url = platform.logoURL {
                        PosterImageView(url: url)
                    } else {
                        Text(platform.shortLabel)
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(.tertiarySystemFill))
                    }
                }
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(isOn ? Color.indigo : Color.primary.opacity(0.08), lineWidth: isOn ? 2.5 : 1)
                )
                .opacity(isOn ? 1 : 0.42)
                .saturation(isOn ? 1 : 0.25)

                if isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: 16, height: 16)
                        .background(Color.indigo, in: Circle())
                        .overlay(Circle().strokeBorder(Color(.secondarySystemGroupedBackground), lineWidth: 2))
                        .offset(x: 5, y: -5)
                }
            }
        }
        .buttonStyle(PressableScaleStyle(scale: 0.92))
        .accessibilityLabel(platform.name)
        .accessibilityValue(isOn ? "Abonné" : "Pas abonné")
    }

    // MARK: - Genres bannis

    private var bannedGenresSection: some View {
        SettingsSection(
            title: "JAMAIS DE…",
            hint: "Ces genres ne vous seront plus jamais proposés, nulle part."
        ) {
            if catalog.genreNames.isEmpty {
                Text("Chargement des genres…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            } else {
                FlowLayout(spacing: 7) {
                    ForEach(sortedGenres, id: \.id) { genre in
                        genreChip(id: genre.id, name: genre.name)
                    }
                }
                .padding(14)
            }
        }
    }

    private var sortedGenres: [(id: Int, name: String)] {
        catalog.genreNames
            .map { (id: $0.key, name: $0.value) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func genreChip(id: Int, name: String) -> some View {
        let isBanned = libraryStore.bannedGenreIDs.contains(id)
        return Button {
            Haptics.selection()
            var ids = libraryStore.bannedGenreIDs
            if isBanned { ids.remove(id) } else { ids.insert(id) }
            libraryStore.setBannedGenres(ids)
        } label: {
            HStack(spacing: 5) {
                Text(name)
                if isBanned {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .heavy))
                }
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(isBanned ? Color.red : Color.secondary)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(
                isBanned ? Color.red.opacity(0.13) : Color(.tertiarySystemFill),
                in: Capsule()
            )
        }
        .buttonStyle(PressableScaleStyle(scale: 0.93))
        .accessibilityValue(isBanned ? "Exclu" : "Autorisé")
    }

    // MARK: - Génération

    private var generationSection: some View {
        SettingsSection(
            title: "MA GÉNÉRATION",
            hint: "Affine les films qu'on vous propose au swipe. À 25 ans et à 55 ans, on n'a pas vu les mêmes classiques."
        ) {
            HStack(spacing: 6) {
                ForEach(Generation.allCases) { generation in
                    let isOn = libraryStore.birthDecade == generation.decade
                    Button {
                        Haptics.selection()
                        libraryStore.setBirthDecade(isOn ? nil : generation.decade)
                    } label: {
                        Text(generation.label)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(isOn ? .white : .secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(
                                isOn ? AnyShapeStyle(Color.indigo) : AnyShapeStyle(Color(.tertiarySystemFill)),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                            )
                    }
                    .buttonStyle(PressableScaleStyle(scale: 0.94))
                    .accessibilityLabel("Né dans les années \(generation.label)")
                    .accessibilityAddTraits(isOn ? [.isSelected] : [])
                }
            }
            .padding(14)
        }
    }

    // MARK: - Données

    private var dataSection: some View {
        SettingsSection(title: "MES DONNÉES", hint: nil) {
            VStack(spacing: 0) {
                SettingsRow(
                    icon: "arrow.counterclockwise",
                    color: .orange,
                    title: "Réinitialiser les films écartés",
                    subtitle: skipsSubtitle
                ) {
                    showResetSkipsAlert = true
                }

                Divider().padding(.leading, 60)

                SettingsRow(
                    icon: "trash.fill",
                    color: .red,
                    title: "Supprimer mon compte",
                    subtitle: "Galerie, watchlist et profil",
                    role: .destructive
                ) {
                    showDeleteAccountAlert = true
                }
            }
            .overlay(alignment: .center) {
                if isWorking {
                    Color(.secondarySystemGroupedBackground).opacity(0.85)
                    CinechillSpinner(size: 24)
                }
            }

            if let actionMessage {
                Text(actionMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
        }
    }

    private var skipsSubtitle: String {
        guard let pendingSkips else { return "Ceux que vous avez dit ne pas avoir vus" }
        guard pendingSkips > 0 else { return "Aucun film en attente" }
        return "\(pendingSkips) film\(pendingSkips > 1 ? "s" : "") en attente de réapparition"
    }

    // MARK: - Profil

    /// La même carte que l'écran profil, en mode éditable : l'avatar ouvre le
    /// sélecteur de photo, le nom devient un champ. Le nom s'enregistre en
    /// quittant le champ, sans bouton dédié.
    private var profileHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProfileSignatureCard(
                isEditable: true,
                nameField: $nameField,
                photoItem: $photoItem,
                onNameFocusChange: { isFocused in
                    if !isFocused { Task { await saveNameIfNeeded() } }
                }
            )

            HStack(spacing: 10) {
                if let email {
                    Text(email)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if isSavingName {
                    CinechillSpinner(size: 16)
                }

                if profileStore.customPhotoData != nil {
                    Button("Supprimer la photo") { showRemovePhotoAlert = true }
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 6)

            if let nameError {
                Text(nameError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 6)
            }
        }
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

    private func resetSkips() async {
        isWorking = true
        actionMessage = nil
        defer { isWorking = false }
        do {
            let deleted = try await libraryStore.resetSwipeSkips()
            pendingSkips = 0
            actionMessage = deleted > 0
                ? "\(deleted) film\(deleted > 1 ? "s" : "") remis en jeu."
                : "Aucun film n'était en attente."
        } catch {
            actionMessage = "La réinitialisation a échoué. Réessayez dans un instant."
        }
    }

    private func deleteAccount() async {
        isWorking = true
        actionMessage = nil
        defer { isWorking = false }
        do {
            try await libraryStore.deleteAccount()
            dismiss()
        } catch {
            actionMessage = "La suppression a échoué. Reconnectez-vous puis réessayez."
        }
    }

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

/// Les tranches proposées pour la génération. Volontairement grossières : on
/// cherche un ordre de grandeur pour pondérer les décennies, pas un âge exact.
private enum Generation: String, CaseIterable, Identifiable {
    case before1970
    case seventies
    case eighties
    case nineties
    case millennium

    var id: String { rawValue }

    var decade: Int {
        switch self {
        case .before1970: 1960
        case .seventies: 1970
        case .eighties: 1980
        case .nineties: 1990
        case .millennium: 2000
        }
    }

    var label: String {
        switch self {
        case .before1970: "–70"
        case .seventies: "70"
        case .eighties: "80"
        case .nineties: "90"
        case .millennium: "2000+"
        }
    }
}

// MARK: - Reusable card components

/// Section titrée avec sa carte — le titre et l'explication vivent à
/// l'extérieur de la carte, pour que celle-ci reste dense.
private struct SettingsSection<Content: View>: View {
    let title: String
    let hint: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .kerning(0.8)
                    .foregroundStyle(.secondary)

                if let hint {
                    Text(hint)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 4)

            VStack(spacing: 0) { content }
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }
}

/// Ligne d'action avec badge d'icône colorée — cible tactile généreuse (~56pt) pour rester
/// ergonomique malgré le style plus dense d'une carte personnalisée.
private struct SettingsRow: View {
    let icon: String
    let color: Color
    let title: String
    var subtitle: String?
    var role: ButtonRole?
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: 14) {
                SettingsIconBadge(systemName: icon, color: color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(role == .destructive ? Color.red : Color.primary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
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
