import SwiftUI
import PhotosUI
import FirebaseAuth

/// Les réglages — « La Régie ».
///
/// L'endroit où l'app apprend de vous directement, au lieu de tout déduire de
/// vos swipes.
///
/// L'écran reposait sur six cartes à rayon 20, des carrés d'icônes orange et
/// rouges et un fond groupé : c'était l'app Réglages d'iOS, pas Cinéchill.
/// Trois décisions le remettent d'aplomb :
///
/// - **Deux zones, séparées par le seul écart franc de l'écran.** En haut, les
///   trois déclarations qui pilotent réellement les recommandations. En bas,
///   replié, l'administration du compte. La proportion à l'écran dit enfin la
///   proportion d'usage : personne n'ouvre les réglages pour supprimer son
///   compte.
/// - **Zéro carte.** Chaque bloc reprend l'anatomie de `PlanField` — libellé
///   gravé, note en ardoise, contrôle, filet de clôture.
/// - **Chaque déclaration annonce sa conséquence, pas son mécanisme.** « Ce qui
///   n'est pas chez vous ne vous sera pas proposé » plutôt que la liste des
///   écrans qui consomment le réglage.
struct SettingsView: View {
    @EnvironmentObject private var profileStore: UserProfileStore
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var libraryStore: LibraryStore
    @EnvironmentObject private var socialStore: SocialStore
    @Environment(MediaCatalog.self) private var catalog
    @Environment(\.dismiss) private var dismiss

    private enum Field: Hashable { case name }

    @State private var nameField: String = ""
    @State private var isSavingName = false
    @State private var nameSaved = false
    @State private var nameError: String?
    @State private var photoItem: PhotosPickerItem?
    @State private var showRemovePhotoAlert = false
    @State private var showResetSkipsAlert = false
    @State private var showDeleteAccountAlert = false
    @State private var showSignOutAlert = false
    @State private var pendingSkips: Int?
    @State private var isWorking = false
    @State private var actionMessage: String?
    /// Le compte reste replié : rien d'irréversible n'est à un tap de distance
    /// dans le flux de lecture.
    @State private var isAccountOpen = false
    @State private var introReplayArmed = false
    /// Le choix de langue vit hors de cet écran : il décide de `Bundle.app`,
    /// que lisent aussi bien les vues que les services.
    @State private var language = LanguageStore.shared
    /// Le même drapeau que celui du deck : le remettre à zéro suffit à réarmer la
    /// démonstration des gestes (voir `SwipeIntroSequence`).
    @AppStorage("swipe.introPlayed") private var swipeIntroPlayed = false
    @FocusState private var focus: Field?

    private var email: String? { Auth.auth().currentUser?.email }

    var body: some View {
        ZStack {
            Ink.ground.ignoresSafeArea()

            VStack(spacing: 0) {
                PlanHeader(String(localized: "Réglages", bundle: .app), leading: .close)

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        identity

                        declaration(
                            String(localized: "Langue", bundle: .app),
                            note: String(localized: "Elle vaut pour l'application comme pour les films : titres, résumés et genres suivent.", bundle: .app)
                        ) {
                            languagePicker
                        }

                        declaration(
                            String(localized: "Mes abonnements", bundle: .app),
                            note: String(localized: "Ce qui n'est pas chez vous ne vous sera pas proposé.", bundle: .app)
                        ) {
                            platforms
                        }

                        declaration(
                            String(localized: "Jamais de…", bundle: .app),
                            note: String(localized: "Exclus partout, sans exception.", bundle: .app)
                        ) {
                            bannedGenres
                        }

                        declaration(
                            String(localized: "Ma génération", bundle: .app),
                            note: String(localized: "À 25 et à 55 ans, on n'a pas vu les mêmes classiques.", bundle: .app)
                        ) {
                            generation
                        }

                        declaration(
                            String(localized: "Les gestes de Découvrir", bundle: .app),
                            note: String(localized: "Les trois directions remontrées en quelques secondes, sur votre prochaine carte.", bundle: .app),
                            isLast: true
                        ) {
                            gestureDemo
                        }

                        account
                    }
                    .padding(.horizontal, Metrics.margin)
                    .padding(.bottom, 32)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
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
        .alert(String(localized: "Supprimer la photo", bundle: .app), isPresented: $showRemovePhotoAlert) {
            Button(String(localized: "Supprimer", bundle: .app), role: .destructive) { profileStore.removeCustomPhoto() }
            Button(String(localized: "Annuler", bundle: .app), role: .cancel) {}
        } message: {
            Text("La photo de profil sera supprimée.", bundle: .app)
        }
        .alert(String(localized: "Remettre les films en jeu", bundle: .app), isPresented: $showResetSkipsAlert) {
            Button(String(localized: "Réinitialiser", bundle: .app)) { Task { await resetSkips() } }
            Button(String(localized: "Annuler", bundle: .app), role: .cancel) {}
        } message: {
            Text("Les films que vous avez écartés au swipe vous seront à nouveau proposés.", bundle: .app)
        }
        .alert(String(localized: "Supprimer votre compte", bundle: .app), isPresented: $showDeleteAccountAlert) {
            Button(String(localized: "Supprimer définitivement", bundle: .app), role: .destructive) {
                Task { await deleteAccount() }
            }
            Button(String(localized: "Annuler", bundle: .app), role: .cancel) {}
        } message: {
            Text("Votre galerie, votre watchlist et votre profil seront effacés. Cette action est irréversible.", bundle: .app)
        }
        // La déconnexion ne détruit rien, mais elle renvoie à l'écran de
        // connexion : le message rassure sur ce point plutôt que d'alarmer.
        .alert(String(localized: "Se déconnecter", bundle: .app), isPresented: $showSignOutAlert) {
            Button(String(localized: "Se déconnecter", bundle: .app), role: .destructive) {
                try? authService.signOut()
                dismiss()
            }
            Button(String(localized: "Annuler", bundle: .app), role: .cancel) {}
        } message: {
            Text("Vous retrouverez votre galerie et votre watchlist à la prochaine connexion.", bundle: .app)
        }
    }

    // MARK: - Le gabarit d'une déclaration

    /// Libellé gravé, note en ardoise, contrôle, filet. C'est `PlanField`
    /// appliqué à un réglage : le composant existait, il n'y avait aucune raison
    /// d'en dessiner un second.
    @ViewBuilder
    private func declaration<Content: View>(
        _ title: String,
        note: String,
        isLast: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            PlanSectionLabel(title: title, note: note)
                .padding(.bottom, 16)

            content()

            if !isLast {
                PlanEdge().padding(.top, 22)
            }
        }
        .padding(.top, 26)
    }

    // MARK: - Identité

    /// La carte de signature perd son cadre : l'identité tient en un avatar, un
    /// nom, et la jauge de palier réduite à un filet. Le badge et le palier ont
    /// leur écran ; ici on ne fait que se reconnaître.
    private var identity: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    avatar
                }
                .buttonStyle(PressableScaleStyle(scale: 0.94))
                .accessibilityLabel(String(localized: "Changer la photo de profil", bundle: .app))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        TextField(
                            "",
                            text: $nameField,
                            prompt: Text("Nom d'affichage", bundle: .app).foregroundColor(Ink.ink3)
                        )
                        .planTitle(20)
                        .foregroundStyle(Ink.ink)
                        .tint(Ink.ink)
                        .focused($focus, equals: .name)
                        .submitLabel(.done)
                        .onSubmit { Task { await saveNameIfNeeded() } }

                        if isSavingName {
                            CinechillSpinner(size: 14)
                        } else if nameSaved {
                            // La confirmation est le point de lumière, comme
                            // partout : *c'est enregistré*.
                            PlanLight()
                        }
                    }

                    if let handle = socialStore.myProfile?.handleDisplay {
                        Text(handle)
                            .font(.system(size: 12))
                            .foregroundStyle(Ink.ink2)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.top, 22)

            if let nameError {
                Text(nameError)
                    .font(.system(size: 12))
                    .foregroundStyle(Ink.warn)
                    .padding(.top, 10)
            }

            HStack(spacing: 10) {
                Text(String(localized: "Palier \(tier.label.lowercased()) · \(libraryStore.galleryItems.count) films", bundle: .app))
                    .planLabel()
                    .foregroundStyle(Ink.ink3)
                    .fixedSize()

                PlanProgressRule(fraction: tier.progress(count: libraryStore.galleryItems.count))
            }
            .padding(.top, 18)

            PlanEdge().padding(.top, 20)
        }
        .onChange(of: focus) { _, now in
            guard now != .name else { return }
            Task { await saveNameIfNeeded() }
        }
    }

    private var tier: CinephileTier { .tier(for: libraryStore.galleryItems.count) }

    @ViewBuilder
    private var avatar: some View {
        Group {
            if let data = profileStore.avatarData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage).resizable().scaledToFill()
            } else if let url = profileStore.avatarURL {
                PosterImageView(url: url)
            } else {
                // Ni silhouette générique ni pastille d'appareil photo : l'anneau
                // du logo, ouvert, qui est déjà l'icône « un profil » du Hall.
                CinechillHallIconView(.salle)
                    .frame(width: 24, height: 24)
                    .foregroundStyle(Ink.ink3)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(hex: 0x151B23))
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Ink.ruleSet, lineWidth: 1))
    }

    // MARK: - Langue

    /// Trois puces, comme partout ailleurs dans cet écran. « Système » d'abord :
    /// c'est l'état par défaut, et le seul qui se contente de ne rien imposer.
    ///
    /// Le changement se voit tout de suite — l'application entière est
    /// redemandée à la racine (voir `Cinechill_iOSApp`), ce qui ramène à
    /// l'accueil. C'est le comportement d'iOS lui-même quand on change la
    /// langue d'une app depuis ses réglages, et ça évite un écran à moitié
    /// traduit le temps d'un retour en arrière.
    private var languagePicker: some View {
        HStack(spacing: 7) {
            ForEach(AppLanguage.allCases) { candidate in
                PlanChip(
                    title: candidate.label,
                    isOn: language.selection == candidate,
                    fillsWidth: true
                ) {
                    Haptics.selection()
                    language.select(candidate)
                }
            }
        }
    }

    // MARK: - Abonnements

    @ViewBuilder
    private var platforms: some View {
        if catalog.platforms.isEmpty {
            HStack(spacing: 10) {
                CinechillSpinner(size: 16)
                Text("Chargement des plateformes…", bundle: .app)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Ink.ink3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            PlatformGrid(
                platforms: catalog.platforms,
                selection: Binding(
                    get: { libraryStore.preferredPlatformIDs },
                    set: { libraryStore.setPreferredPlatforms($0) }
                )
            )
        }
    }

    // MARK: - Genres bannis

    @ViewBuilder
    private var bannedGenres: some View {
        if catalog.genreNames.isEmpty {
            Text("Chargement des genres…", bundle: .app)
                .font(.system(size: 12.5))
                .foregroundStyle(Ink.ink3)
        } else {
            FlowLayout(spacing: 7) {
                ForEach(sortedGenres, id: \.id) { genre in
                    let isBanned = libraryStore.bannedGenreIDs.contains(genre.id)
                    PlanChip(title: genre.name, isOn: false, isExcluded: isBanned) {
                        Haptics.selection()
                        var ids = libraryStore.bannedGenreIDs
                        if isBanned { ids.remove(genre.id) } else { ids.insert(genre.id) }
                        libraryStore.setBannedGenres(ids)
                    }
                    .accessibilityValue(isBanned ? String(localized: "Exclu", bundle: .app) : String(localized: "Autorisé", bundle: .app))
                }
            }
        }
    }

    private var sortedGenres: [(id: Int, name: String)] {
        catalog.genreNames
            .map { (id: $0.key, name: $0.value) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Génération

    private var generation: some View {
        HStack(spacing: 7) {
            ForEach(Generation.allCases) { generation in
                let isOn = libraryStore.birthDecade == generation.decade
                PlanChip(title: generation.label, isOn: isOn, fillsWidth: true) {
                    Haptics.selection()
                    libraryStore.setBirthDecade(isOn ? nil : generation.decade)
                }
                .accessibilityLabel(String(localized: "Né dans les années \(generation.label)", bundle: .app))
            }
        }
    }

    // MARK: - La démonstration des gestes

    /// La seule porte de sortie d'une démonstration qui ne se joue qu'une fois.
    ///
    /// Elle n'ouvre pas un écran : elle réarme le drapeau, et la séquence se
    /// rejoue là où elle a un sens — sur le deck, à la prochaine entrée dans
    /// l'onglet. Le libellé passe donc à l'acquittement plutôt que de renvoyer
    /// vers un ailleurs.
    @ViewBuilder
    private var gestureDemo: some View {
        if introReplayArmed {
            HStack(alignment: .top, spacing: 11) {
                PlanLight().padding(.top, 5)
                Text("La démonstration se rejouera à votre prochain passage sur Découvrir.", bundle: .app)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Ink.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(minHeight: Metrics.control)
            .transition(.opacity)
        } else {
            PlanSecondaryButton(title: String(localized: "Revoir la démonstration", bundle: .app), height: Metrics.control) {
                Haptics.selection()
                swipeIntroPlayed = false
                withAnimation(Metrics.shift) { introReplayArmed = true }
            }
        }
    }

    // MARK: - Le compte

    /// Replié par défaut, et séparé du reste par le seul écart franc de l'écran.
    /// Tout ce qui est irréversible vit ici, et nulle part ailleurs.
    private var account: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(Ink.ruleSet)
                .frame(height: 1)
                .padding(.top, 44)

            Button {
                Haptics.selection()
                withAnimation(Metrics.unfold) { isAccountOpen.toggle() }
            } label: {
                HStack {
                    Text("Le compte", bundle: .app)
                        .planLabel()
                        .foregroundStyle(Ink.ink2)
                    Spacer()
                    DisclosureGlyph(isOpen: isAccountOpen)
                        .stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                        .foregroundStyle(Ink.ink3)
                        .frame(width: 14, height: 14)
                }
                .frame(height: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Le compte", bundle: .app))
            .accessibilityValue(isAccountOpen ? String(localized: "Déplié", bundle: .app) : String(localized: "Replié", bundle: .app))

            if isAccountOpen {
                accountBody
                    .transition(.opacity)
            }

            PlanEdge()

            Text(appVersion)
                .font(.system(size: 11))
                .foregroundStyle(Ink.ink3)
                .padding(.top, 16)
        }
    }

    private var accountBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let email {
                accountLine(label: String(localized: "Adresse", bundle: .app), value: email)
            }

            accountAction(
                String(localized: "Réinitialiser les films écartés", bundle: .app),
                note: skipsSubtitle
            ) {
                showResetSkipsAlert = true
            }

            if profileStore.customPhotoData != nil {
                accountAction(String(localized: "Supprimer la photo de profil", bundle: .app), note: nil) {
                    showRemovePhotoAlert = true
                }
            }

            accountAction(String(localized: "Se déconnecter", bundle: .app), note: nil) {
                showSignOutAlert = true
            }

            accountAction(
                String(localized: "Supprimer mon compte", bundle: .app),
                note: String(localized: "Galerie, watchlist et profil. Irréversible.", bundle: .app),
                isDestructive: true
            ) {
                showDeleteAccountAlert = true
            }

            if let actionMessage {
                HStack(alignment: .top, spacing: 11) {
                    PlanLight().padding(.top, 6)
                    Text(actionMessage)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Ink.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 14)
            }

            if isWorking {
                HStack(spacing: 10) {
                    CinechillSpinner(size: 16)
                    Text("En cours…", bundle: .app)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Ink.ink3)
                }
                .padding(.bottom, 14)
            }
        }
        .padding(.bottom, 8)
    }

    private func accountLine(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .planLabel()
                .foregroundStyle(Ink.ink3)
            Text(value)
                .font(.system(size: 14))
                .foregroundStyle(Ink.ink2)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 14)
        .overlay(alignment: .top) { PlanEdge() }
    }

    private func accountAction(
        _ title: String,
        note: String?,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14))
                    .foregroundStyle(isDestructive ? Ink.warn : Ink.ink)
                if let note {
                    Text(note)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Ink.ink3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isWorking)
        .overlay(alignment: .top) { PlanEdge() }
    }

    private var skipsSubtitle: String {
        guard let pendingSkips else { return String(localized: "Ceux que vous avez dit ne pas avoir vus", bundle: .app) }
        guard pendingSkips > 0 else { return String(localized: "Aucun film en attente", bundle: .app) }
        return String(localized: "\(pendingSkips) films en attente de réapparition", bundle: .app)
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return String(localized: "Cinéchill · version \(version) (\(build))", bundle: .app)
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
                ? String(localized: "\(deleted) films remis en jeu.", bundle: .app)
                : String(localized: "Aucun film n'était en attente.", bundle: .app)
        } catch {
            actionMessage = String(localized: "La réinitialisation a échoué. Réessayez dans un instant.", bundle: .app)
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
            actionMessage = String(localized: "La suppression a échoué. Reconnectez-vous puis réessayez.", bundle: .app)
        }
    }

    private func saveNameIfNeeded() async {
        let trimmed = nameField.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != profileStore.displayName else { return }
        nameError = nil
        nameSaved = false
        isSavingName = true
        defer { isSavingName = false }
        do {
            try await profileStore.updateDisplayName(trimmed)
            // Le profil public a sa propre copie du nom, pour que la recherche
            // par prénom/nom fonctionne sans lire le compte Firebase de chacun.
            // Sans ce second appel, elle resterait figée sur le nom du jour où
            // le pseudo a été choisi.
            await socialStore.syncDisplayName(trimmed)
            withAnimation(Metrics.shift) { nameSaved = true }
            try? await Task.sleep(for: .seconds(2))
            withAnimation(Metrics.shift) { nameSaved = false }
        } catch {
            nameError = error.localizedDescription
        }
    }

    private func loadPhoto(from item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        // Redimensionné pour garder le stockage `UserDefaults` raisonnable (~200 Ko).
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

/// Le chevron de dépliage, dans l'écriture de la famille.
private struct DisclosureGlyph: Shape {
    let isOpen: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let midX = rect.midX
        if isOpen {
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY * 0.68))
            path.addLine(to: CGPoint(x: midX, y: rect.maxY * 0.32))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY * 0.68))
        } else {
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY * 0.32))
            path.addLine(to: CGPoint(x: midX, y: rect.maxY * 0.68))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY * 0.32))
        }
        return path
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
