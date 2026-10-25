import SwiftUI
import PhotosUI

/// Les réglages, poussés depuis le profil.
///
/// L'écran empilait onze blocs de même poids, chacun avec son libellé en
/// capitales et son filet : on ne voyait plus où finissait un sujet. Il tient
/// maintenant en quatre groupes, dans l'ordre de ce qu'on vient y faire :
///
/// - **Ce qu'on te propose** : les deux déclarations qui changent vraiment
///   les recommandations, une ligne chacune.
/// - **L'app** : notifications, langue, comptes bloqués.
/// - **Aide** : nous contacter, relire les conditions.
/// - **Ton compte** : tout ce qui touche au compte, ouvert. Le replier cachait
///   « Se déconnecter », qu'on cherche plus souvent qu'on ne le craint ; ce
///   qui est irréversible passe de toute façon par une alerte.
///
/// Deux niveaux de texte seulement : le titre de groupe en capitales, puis des
/// lignes. Chaque déclaration annonce sa conséquence, pas son mécanisme.
struct SettingsView: View {
    @EnvironmentObject private var profileStore: UserProfileStore
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var libraryStore: LibraryStore
    @EnvironmentObject private var socialStore: SocialStore
    @Environment(MediaCatalog.self) private var catalog
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var typeSize

    private enum Field: Hashable { case name }

    @State private var nameField: String = ""
    @State private var nameSaved = false
    @State private var nameError: String?
    @State private var photoItem: PhotosPickerItem?
    @State private var showRemovePhotoAlert = false
    @State private var showDeleteAccountAlert = false
    @State private var showSignOutAlert = false
    @State private var isWorking = false
    @State private var actionMessage: String?
    @State private var addressCopied = false
    /// Le choix de langue vit hors de cet écran : il décide de `Bundle.app`,
    /// que lisent aussi bien les vues que les services.
    @State private var language = LanguageStore.shared
    @State private var notifications = NotificationPermission.shared
    @FocusState private var focus: Field?

    /// Pas une chaîne traduite : une `static let` ne pose ici aucun problème.
    /// La règle 1.2 de l'App Store demande un moyen de joindre l'équipe à
    /// toute app où des gens se croisent. Un moyen, pas une adresse à
    /// l'écran : c'est une adresse personnelle, elle ne s'affiche nulle part.
    private static let contactAddress = "pierrerobrt@gmail.com"

    var body: some View {
        ZStack {
            Ink.ground.ignoresSafeArea()

            VStack(spacing: 0) {
                PlanHeader(String(localized: "Réglages", bundle: .app))

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        identity
                        suggestions
                        app
                        help
                        account
                        colophon
                    }
                    .padding(.horizontal, Metrics.margin)
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            nameField = profileStore.chosenName ?? ""
            await notifications.refresh()
            await catalog.loadIfNeeded()
        }
        // Un nom tapé puis un retour arrière, sans valider : le focus ne
        // change pas avant la disparition, et le nom se perdait.
        .onDisappear {
            Task {
                await saveNameIfNeeded()
                profileStore.refresh()
            }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await loadPhoto(from: item) }
        }
        .onChange(of: focus) { _, now in
            guard now != .name else { return }
            Task { await saveNameIfNeeded() }
        }
        .alert(String(localized: "Supprimer la photo", bundle: .app), isPresented: $showRemovePhotoAlert) {
            Button(String(localized: "Supprimer", bundle: .app), role: .destructive) { profileStore.removeCustomPhoto() }
            Button(String(localized: "Annuler", bundle: .app), role: .cancel) {}
        } message: {
            Text("On supprimera ta photo de profil.", bundle: .app)
        }
        .alert(String(localized: "Supprimer ton compte", bundle: .app), isPresented: $showDeleteAccountAlert) {
            Button(String(localized: "Supprimer définitivement", bundle: .app), role: .destructive) {
                Task { await deleteAccount() }
            }
            Button(String(localized: "Annuler", bundle: .app), role: .cancel) {}
        } message: {
            Text("On effacera ta galerie, ta watchlist et ton profil. Tu ne pourras pas les récupérer.", bundle: .app)
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
            Text("Tu retrouveras ta galerie et ta watchlist à la prochaine connexion.", bundle: .app)
        }
    }

    // MARK: - Les gabarits

    /// Un groupe : son titre en capitales, puis ses lignes, chacune posée sous
    /// un filet. C'est le seul écart franc de l'écran ; entre deux lignes d'un
    /// même groupe, il n'y a qu'un filet.
    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .planLabel()
                .foregroundStyle(Ink.ink2)
                .padding(.bottom, 10)
                .accessibilityAddTraits(.isHeader)

            content()
        }
        .padding(.top, 40)
    }

    /// Une ligne : un titre, sa note éventuelle, une valeur à droite et le
    /// signe de ce qui se passe au tap. La même anatomie pour un écran qui
    /// s'ouvre, une page web, un menu ou une action.
    private func line(
        _ title: String,
        note: String? = nil,
        value: String? = nil,
        trailing: LineGlyph.Kind? = .chevron,
        tint: Color = Ink.ink
    ) -> some View {
        line(title, note: note, trailing: trailing, tint: tint) {
            if let value {
                Text(value)
                    .planFont(14)
                    .foregroundStyle(Ink.ink2)
                    .lineLimit(1)
            }
        }
    }

    /// La même ligne, avec à droite autre chose qu'un texte : les logos des
    /// plateformes retenues.
    private func line<Accessory: View>(
        _ title: String,
        note: String? = nil,
        trailing: LineGlyph.Kind? = .chevron,
        tint: Color = Ink.ink,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .planFont(15)
                    .foregroundStyle(tint)
                    .fixedSize(horizontal: false, vertical: true)
                if let note {
                    Text(note)
                        .planFont(12.5)
                        .foregroundStyle(Ink.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            // Posée dans le libellé d'un `Menu`, une ligne hérite d'un
            // alignement centré : la seconde ligne d'une note partait au
            // milieu. Toujours à gauche, quel que soit le conteneur.
            .multilineTextAlignment(.leading)
            .layoutPriority(1)

            Spacer(minLength: 8)

            accessory()

            if let trailing {
                LineGlyph(kind: trailing)
                    .stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(Ink.ink3)
                    .frame(width: 14, height: 14)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .contentShape(Rectangle())
        .overlay(alignment: .top) { PlanEdge() }
    }

    // MARK: - Identité

    /// L'avatar et le nom, sans rien d'autre : la distinction et les badges
    /// ont leur place sur le profil, juste derrière.
    private var identity: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 18))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 18))

        return layout {
            PhotosPicker(selection: $photoItem, matching: .images) {
                avatar
            }
            .buttonStyle(PressableScaleStyle(scale: 0.94))
            .accessibilityLabel(String(localized: "Changer la photo de profil", bundle: .app))

            VStack(alignment: .leading, spacing: 8) {
                // Le champ de l'authentification, et non un titre éditable :
                // un nom posé en gros sans filet ne se lisait pas comme une
                // valeur qu'on peut changer.
                PlanField(
                    label: String(localized: "Nom d'affichage", bundle: .app),
                    text: $nameField,
                    field: Field.name,
                    focus: $focus,
                    contentType: .name,
                    submitLabel: .done,
                    accessory: nameSaved ? .light : .none,
                    error: nameError,
                    onSubmit: { focus = nil }
                )

                if let handle = socialStore.myProfile?.handleDisplay {
                    Text(verbatim: handle)
                        .planFont(13)
                        .foregroundStyle(Ink.ink2)
                        .lineLimit(1)
                }
            }
        }
        .padding(.top, 24)
    }

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
                    .frame(width: 26, height: 26)
                    .foregroundStyle(Ink.ink3)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Ink.ground3)
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Ink.ruleSet, lineWidth: 1))
    }

    // MARK: - Ce qu'on te propose

    /// Deux lignes, chacune avec ce qui est retenu à droite. Les plateformes
    /// et les genres ouvrent leur propre écran : leurs grilles prenaient la
    /// moitié des réglages pour un choix qu'on fait une fois.
    ///
    /// Plus de décennie de naissance : elle ne servait qu'à Découvrir, qui
    /// apprend seul des réponses si l'on connaît les vieux films.
    ///
    /// Plus de « Remettre les films passés » : un film passé dans Découvrir
    /// revient de lui-même au bout de 90 jours, il n'y a rien à rattraper.
    private var suggestions: some View {
        group(String(localized: "Ce qu'on te propose", bundle: .app)) {
            NavigationLink {
                PlatformSettingsView()
            } label: {
                line(String(localized: "Mes plateformes", bundle: .app)) {
                    platformsSummary
                }
            }
            .buttonStyle(PressableScaleStyle(scale: 0.985))

            NavigationLink {
                BannedGenresSettingsView()
            } label: {
                line(String(localized: "Genres exclus", bundle: .app), value: bannedGenresSummary)
            }
            .buttonStyle(PressableScaleStyle(scale: 0.985))
        }
    }

    /// Les plateformes retenues, par leur logo : quatre noms ne tenaient pas
    /// sur la ligne, quatre logos de 22 pt si. Au-delà, le compte du reste.
    @ViewBuilder
    private var platformsSummary: some View {
        let chosen = catalog.platforms.filter { libraryStore.preferredPlatformIDs.contains($0.id) }
        if libraryStore.preferredPlatformIDs.isEmpty {
            Text("Aucune", bundle: .app)
                .planFont(14)
                .foregroundStyle(Ink.ink2)
        } else if chosen.isEmpty {
            // Le catalogue n'est pas encore là : le nombre, en attendant.
            Text(String(localized: "\(libraryStore.preferredPlatformIDs.count) plateformes", bundle: .app))
                .planFont(14)
                .foregroundStyle(Ink.ink2)
        } else {
            HStack(spacing: 5) {
                ForEach(chosen.prefix(4)) { platform in
                    platformLogo(platform)
                }
                if chosen.count > 4 {
                    Text(verbatim: "+\(chosen.count - 4)")
                        .planFont(12)
                        .monospacedDigit()
                        .foregroundStyle(Ink.ink2)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(chosen.map(\.name).joined(separator: ", "))
        }
    }

    private func platformLogo(_ platform: StreamingPlatform) -> some View {
        Group {
            if let logoURL = platform.logoURL {
                PosterImageView(url: logoURL)
            } else {
                Text(platform.shortLabel.prefix(2))
                    .planFont(8, weight: .semibold)
                    .foregroundStyle(Ink.ink2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Ink.ground3)
            }
        }
        .frame(width: 22, height: 22)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                .strokeBorder(Ink.rule, lineWidth: 1)
        )
    }

    private var bannedGenresSummary: String {
        let names = libraryStore.bannedGenreIDs
            .compactMap { catalog.genreNames[$0] }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return names.isEmpty ? String(localized: "Aucun", bundle: .app) : names.joined(separator: ", ")
    }

    /// Le compte rendu d'une action du compte qui a échoué, sous ses lignes.
    @ViewBuilder
    private var feedback: some View {
        if isWorking {
            HStack(spacing: 10) {
                CinechillSpinner(size: 16)
                Text("En cours…", bundle: .app)
                    .planFont(13)
                    .foregroundStyle(Ink.ink2)
            }
            .padding(.vertical, 14)
        } else if let actionMessage {
            HStack(alignment: .top, spacing: 11) {
                PlanLight(tint: Ink.warn).padding(.top, 6)
                Text(actionMessage)
                    .planFont(13)
                    .foregroundStyle(Ink.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 14)
        }
    }

    // MARK: - L'app

    private var app: some View {
        group(String(localized: "L'app", bundle: .app)) {
            // Notifications et comptes bloqués ont leur écran : chacun porte
            // ses propres états (l'autorisation d'iOS, une liste à charger).
            NavigationLink {
                NotificationSettingsView()
            } label: {
                line(
                    String(localized: "Notifications", bundle: .app),
                    // Seul l'état qui empêche quelque chose se dit ici.
                    value: notifications.status == .denied
                        ? String(localized: "Coupées", bundle: .app)
                        : nil
                )
            }
            .buttonStyle(PressableScaleStyle(scale: 0.985))

            languageMenu

            NavigationLink {
                BlockedAccountsView()
            } label: {
                line(String(localized: "Comptes bloqués", bundle: .app))
            }
            .buttonStyle(PressableScaleStyle(scale: 0.985))
        }
    }

    /// Un menu et non des puces : deux langues ne méritent pas une rangée
    /// entière. Le changement se voit tout de suite, l'application entière
    /// est redemandée à la racine (voir `Cinechill_iOSApp`) et revient à
    /// l'accueil, comme iOS le fait quand on change la langue d'une app.
    private var languageMenu: some View {
        Menu {
            Picker(
                selection: Binding(
                    get: { language.selection },
                    set: { language.select($0) }
                )
            ) {
                ForEach(AppLanguage.allCases) { candidate in
                    Text(verbatim: candidate.label).tag(candidate)
                }
            } label: {
                Text("Langue", bundle: .app)
            }
            .pickerStyle(.inline)
        } label: {
            line(
                String(localized: "Langue", bundle: .app),
                value: language.selection.label,
                trailing: .menu
            )
        }
        .accessibilityLabel(String(localized: "Langue", bundle: .app))
        .accessibilityValue(language.selection.label)
    }

    // MARK: - Aide

    private var help: some View {
        group(String(localized: "Aide", bundle: .app)) {
            // Sans app Mail configurée, le tap ne peut rien ouvrir : il copie
            // alors l'adresse, sans l'afficher, et le dit.
            Button(action: writeToUs) {
                line(
                    String(localized: "Contacter Cinechill", bundle: .app),
                    note: addressCopied ? String(localized: "Adresse copiée", bundle: .app) : nil,
                    trailing: .external
                )
            }
            .buttonStyle(PressableScaleStyle(scale: 0.985))

            // Les pages légales s'ouvrent dans Safari : elles vivent sur le
            // web, et on les relit sans quitter son compte.
            legalLink(String(localized: "Conditions d'utilisation", bundle: .app), page: .terms)
            legalLink(String(localized: "Politique de confidentialité", bundle: .app), page: .privacy)
        }
    }

    private func legalLink(_ title: String, page: LegalPage) -> some View {
        Link(destination: page.url) {
            line(title, trailing: .external)
        }
        .buttonStyle(PressableScaleStyle(scale: 0.985))
        .accessibilityAddTraits(.isLink)
    }

    private func writeToUs() {
        guard let url = URL(string: "mailto:\(Self.contactAddress)") else { return }
        openURL(url) { accepted in
            guard !accepted else { return }
            UIPasteboard.general.string = Self.contactAddress
            withAnimation(Metrics.shift) { addressCopied = true }
        }
    }

    // MARK: - Ton compte

    private var account: some View {
        group(String(localized: "Ton compte", bundle: .app)) {
            if profileStore.customPhotoData != nil {
                accountAction(String(localized: "Supprimer la photo de profil", bundle: .app)) {
                    showRemovePhotoAlert = true
                }
            }

            accountAction(String(localized: "Se déconnecter", bundle: .app)) {
                showSignOutAlert = true
            }

            accountAction(
                String(localized: "Supprimer mon compte", bundle: .app),
                note: String(localized: "Tu perdras ta galerie, ta watchlist et ton profil.", bundle: .app),
                isDestructive: true
            ) {
                showDeleteAccountAlert = true
            }

            feedback
        }
    }

    private func accountAction(
        _ title: String,
        note: String? = nil,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            line(title, note: note, trailing: nil, tint: isDestructive ? Ink.warn : Ink.ink)
        }
        // Le retour à l'appui des autres lignes de l'app : sans lui, rien ne
        // disait que « Se déconnecter » avait pris le tap avant l'alerte.
        .buttonStyle(PressableScaleStyle(scale: 0.985))
        .disabled(isWorking)
    }

    // MARK: - Pied de page

    /// La version seule, utile quand on nous écrit. La mention de TMDB que
    /// demandent ses conditions vit dans les Conditions d'utilisation, liées
    /// juste au-dessus.
    /// La version, et la source des données. Les conditions de TMDB demandent
    /// son nom et son logo dans l'app elle-même, pas seulement dans les
    /// conditions en ligne. Au pied, à la taille de la version : c'est un
    /// crédit, pas une fonction.
    private var colophon: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image("TMDBLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 10)
                    // Le texte à côté nomme TMDB : VoiceOver ne le lirait pas deux fois.
                    .accessibilityHidden(true)
                Text("Données de films fournies par TMDB", bundle: .app)
                    .planFont(11.5)
                    .foregroundStyle(Ink.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(verbatim: appVersion)
                .planFont(11.5)
                .foregroundStyle(Ink.ink2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 22)
        .overlay(alignment: .top) { PlanEdge() }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        // La marque s'écrit sans accent, et ne se traduit pas.
        return "Cinechill · " + String(localized: "version \(version) (\(build))", bundle: .app)
    }

    // MARK: - Actions

    private func deleteAccount() async {
        isWorking = true
        actionMessage = nil
        defer { isWorking = false }
        guard await authService.revokeAppleAuthorizationIfNeeded() else { return }
        do {
            try await libraryStore.deleteAccount()
            dismiss()
        } catch {
            actionMessage = String(localized: "On n'a pas pu supprimer ton compte. Vérifie ta connexion et réessaie.", bundle: .app)
        }
    }

    private func saveNameIfNeeded() async {
        let trimmed = nameField.trimmingCharacters(in: .whitespacesAndNewlines)
        // Un champ vidé n'efface pas le nom : il le retrouve, au lieu de
        // laisser croire qu'un nom vide a été enregistré.
        guard !trimmed.isEmpty else {
            nameField = profileStore.chosenName ?? ""
            return
        }
        guard trimmed != profileStore.chosenName else { return }
        nameError = nil
        nameSaved = false
        do {
            try await profileStore.updateDisplayName(trimmed)
            // Le profil public a sa propre copie du nom, pour que la recherche
            // par prénom/nom fonctionne sans lire le compte Firebase de chacun.
            // Sans ce second appel, elle resterait figée sur le nom du jour où
            // le pseudo a été choisi.
            await socialStore.syncDisplayName(trimmed)
            // La confirmation est le point de lumière, comme partout :
            // *c'est enregistré*.
            withAnimation(Metrics.shift) { nameSaved = true }
            try? await Task.sleep(for: .seconds(2))
            withAnimation(Metrics.shift) { nameSaved = false }
        } catch {
            // Le message de Firebase est technique, et souvent en anglais.
            nameError = String(localized: "On n'a pas pu enregistrer ton nom. Réessaie.", bundle: .app)
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

/// Ce que dit le bout d'une ligne, dans l'écriture des icônes de l'app :
/// grille de 24, trait de 1,5, extrémités rondes.
private struct LineGlyph: Shape {
    enum Kind {
        /// Un écran qui s'ouvre à droite.
        case chevron
        /// Une page qui s'ouvre hors de l'app.
        case external
        /// Un menu qui se déplie sur place.
        case menu
    }

    let kind: Kind

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * scale, y: rect.minY + y * scale)
        }

        var path = Path()
        switch kind {
        case .chevron:
            path.move(to: p(9, 4.8))
            path.addLine(to: p(16, 12))
            path.addLine(to: p(9, 19.2))
        case .external:
            path.move(to: p(6, 18))
            path.addLine(to: p(18, 6))
            path.move(to: p(9, 6))
            path.addLine(to: p(18, 6))
            path.addLine(to: p(18, 15))
        case .menu:
            path.move(to: p(7, 9.5))
            path.addLine(to: p(12, 4.5))
            path.addLine(to: p(17, 9.5))
            path.move(to: p(7, 14.5))
            path.addLine(to: p(12, 19.5))
            path.addLine(to: p(17, 14.5))
        }
        return path
    }
}

extension UIImage {
    func resized(toMaxDimension max: CGFloat) -> UIImage? {
        let scale = min(max / size.width, max / size.height, 1)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}
