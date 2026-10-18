import SwiftUI
import PhotosUI
import FirebaseAuth

/// Les réglages, poussés depuis le profil.
///
/// L'écran empilait onze blocs de même poids, chacun avec son libellé en
/// capitales et son filet : on ne voyait plus où finissait un sujet. Il tient
/// maintenant en quatre groupes, dans l'ordre de ce qu'on vient y faire :
///
/// - **Ce qu'on te propose** : les trois déclarations qui changent vraiment
///   les recommandations, et la remise à zéro des films passés, qui en est une
///   quatrième.
/// - **L'app** : notifications, langue, comptes bloqués.
/// - **Aide** : écrire, relire les conditions.
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
    @State private var showResetSkipsAlert = false
    @State private var showDeleteAccountAlert = false
    @State private var showSignOutAlert = false
    @State private var pendingSkips: Int?
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
    /// toute app où des gens se croisent.
    private static let contactAddress = "pierrerobrt@gmail.com"

    private var email: String? { Auth.auth().currentUser?.email }

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
            nameField = profileStore.displayName
            await notifications.refresh()
            await catalog.loadIfNeeded()
            pendingSkips = await libraryStore.pendingSkipCount()
        }
        .onDisappear { profileStore.refresh() }
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
        .alert(String(localized: "Remettre les films passés", bundle: .app), isPresented: $showResetSkipsAlert) {
            Button(String(localized: "Remettre", bundle: .app)) { Task { await resetSkips() } }
            Button(String(localized: "Annuler", bundle: .app), role: .cancel) {}
        } message: {
            Text("Les films que tu as passés reviendront dans Découvrir.", bundle: .app)
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

    /// Une déclaration : ce qu'on règle, ce que ça change, puis le contrôle.
    private func declaration<Content: View>(
        _ title: String,
        note: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .planFont(15, weight: .medium)
                    .foregroundStyle(Ink.ink)
                Text(note)
                    .planFont(12.5)
                    .foregroundStyle(Ink.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)

            content()
                .padding(.top, 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 18)
        .padding(.bottom, 22)
        .overlay(alignment: .top) { PlanEdge() }
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
            .layoutPriority(1)

            Spacer(minLength: 8)

            if let value {
                Text(value)
                    .planFont(14)
                    .foregroundStyle(Ink.ink2)
                    .lineLimit(1)
            }

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

    private var suggestions: some View {
        group(String(localized: "Ce qu'on te propose", bundle: .app)) {
            declaration(
                String(localized: "Mes plateformes", bundle: .app),
                note: String(localized: "On ne te proposera que des films disponibles sur tes plateformes.", bundle: .app)
            ) {
                platforms
            }

            declaration(
                String(localized: "Mes genres exclus", bundle: .app),
                note: String(localized: "Touche un genre pour qu'on ne te le propose plus.", bundle: .app)
            ) {
                bannedGenres
            }

            declaration(
                String(localized: "Ma génération", bundle: .app),
                note: String(localized: "Les films sortis avant ta naissance te seront moins souvent proposés.", bundle: .app)
            ) {
                generation
            }

            Button { showResetSkipsAlert = true } label: {
                // Le même nom que l'alerte qu'elle ouvre : « écartés » ici,
                // « passés » là, pour une seule et même liste.
                line(
                    String(localized: "Remettre les films passés", bundle: .app),
                    note: skipsSubtitle,
                    trailing: nil
                )
            }
            .buttonStyle(PressableScaleStyle(scale: 0.985))
            .disabled(isWorking || pendingSkips == 0)

            feedback
        }
    }

    @ViewBuilder
    private var platforms: some View {
        if catalog.platforms.isEmpty {
            HStack(spacing: 10) {
                CinechillSpinner(size: 16)
                Text("Chargement des plateformes…", bundle: .app)
                    .planFont(13)
                    .foregroundStyle(Ink.ink2)
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

    @ViewBuilder
    private var bannedGenres: some View {
        if catalog.genreNames.isEmpty {
            Text("Chargement des genres…", bundle: .app)
                .planFont(13)
                .foregroundStyle(Ink.ink2)
        } else {
            FlowLayout(spacing: 7) {
                ForEach(sortedGenres, id: \.id) { genre in
                    let isBanned = libraryStore.bannedGenreIDs.contains(genre.id)
                    PlanChip(title: genre.name, isOn: false, isExcluded: isBanned) {
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

    /// Cinq puces sur une rangée ; aux tailles d'accessibilité, elles passent
    /// à la ligne plutôt que de tronquer « 2000+ ».
    private var generation: some View {
        let wraps = typeSize.isAccessibilitySize
        let layout = wraps ? AnyLayout(FlowLayout(spacing: 7)) : AnyLayout(HStackLayout(spacing: 7))

        return layout {
            ForEach(Generation.allCases) { generation in
                let isOn = libraryStore.birthDecade == generation.decade
                PlanChip(title: generation.label, isOn: isOn, fillsWidth: !wraps) {
                    libraryStore.setBirthDecade(isOn ? nil : generation.decade)
                }
                // « Né dans les années –70 » se lisait tel quel, et accordait
                // au masculin : chaque tranche a sa phrase.
                .accessibilityLabel(generation.accessibilityLabel)
            }
        }
    }

    /// Le compte rendu d'une remise à zéro, sous la ligne qui l'a lancée.
    @ViewBuilder
    private var feedback: some View {
        if isWorking {
            HStack(spacing: 10) {
                CinechillSpinner(size: 16)
                Text("En cours…", bundle: .app)
                    .planFont(13)
                    .foregroundStyle(Ink.ink2)
            }
            .padding(.bottom, 14)
        } else if let actionMessage {
            HStack(alignment: .top, spacing: 11) {
                PlanLight().padding(.top, 6)
                Text(actionMessage)
                    .planFont(13)
                    .foregroundStyle(Ink.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.bottom, 14)
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
                note: String(localized: "Les titres, les résumés et les genres changent aussi.", bundle: .app),
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
            // L'adresse reste écrite en entier : sans app Mail configurée, le
            // tap ne peut rien ouvrir, il la copie alors et le dit.
            Button(action: writeToUs) {
                // La confirmation prend la place de la note et non celle de la
                // valeur : à droite, elle ne tenait pas sur un petit écran.
                line(
                    String(localized: "Nous écrire", bundle: .app),
                    note: addressCopied
                        ? String(localized: "Adresse copiée : \(Self.contactAddress)", bundle: .app)
                        : Self.contactAddress,
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
            if let email {
                line(String(localized: "Email", bundle: .app), note: email, trailing: nil)
                    .accessibilityElement(children: .combine)
            }

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

    private var colophon: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: appVersion)

            // Les conditions de TMDB exigent cette mention, que la traduction
            // anglaise reprend mot pour mot ; JustWatch, qui fournit à TMDB les
            // disponibilités, demande d'être cité. C'est une licence, pas une
            // règle App Store.
            Text("Cinechill utilise l'API TMDB mais n'est ni approuvé ni certifié par TMDB. Disponibilités sur les plateformes : JustWatch.", bundle: .app)
                .fixedSize(horizontal: false, vertical: true)
        }
        .planFont(11.5)
        .foregroundStyle(Ink.ink2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 22)
        .overlay(alignment: .top) { PlanEdge() }
    }

    private var skipsSubtitle: String {
        guard let pendingSkips else { return String(localized: "Ceux que tu as dit ne pas avoir vus", bundle: .app) }
        guard pendingSkips > 0 else { return String(localized: "Aucun film passé", bundle: .app) }
        return String(localized: "\(pendingSkips) films passés", bundle: .app)
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        // La marque s'écrit sans accent, et ne se traduit pas.
        return "Cinechill · " + String(localized: "version \(version) (\(build))", bundle: .app)
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
                ? String(localized: "On pourra te reproposer \(deleted) films.", bundle: .app)
                : String(localized: "Il n'y avait aucun film passé.", bundle: .app)
        } catch {
            actionMessage = String(localized: "La réinitialisation a échoué. Réessaie dans un instant.", bundle: .app)
        }
    }

    private func deleteAccount() async {
        isWorking = true
        actionMessage = nil
        defer { isWorking = false }
        guard await authService.revokeAppleAuthorizationIfNeeded() else { return }
        do {
            try await libraryStore.deleteAccount()
            dismiss()
        } catch {
            actionMessage = String(localized: "La suppression a échoué. Reconnecte-toi puis réessaie.", bundle: .app)
        }
    }

    private func saveNameIfNeeded() async {
        let trimmed = nameField.trimmingCharacters(in: .whitespacesAndNewlines)
        // Un champ vidé n'efface pas le nom : il le retrouve, au lieu de
        // laisser croire qu'un nom vide a été enregistré.
        guard !trimmed.isEmpty else {
            nameField = profileStore.displayName
            return
        }
        guard trimmed != profileStore.displayName else { return }
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

    var accessibilityLabel: String {
        switch self {
        case .before1970: String(localized: "Naissance avant 1970", bundle: .app)
        case .seventies: String(localized: "Naissance dans les années 70", bundle: .app)
        case .eighties: String(localized: "Naissance dans les années 80", bundle: .app)
        case .nineties: String(localized: "Naissance dans les années 90", bundle: .app)
        case .millennium: String(localized: "Naissance en 2000 ou après", bundle: .app)
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

private extension UIImage {
    func resized(toMaxDimension max: CGFloat) -> UIImage? {
        let scale = min(max / size.width, max / size.height, 1)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}
