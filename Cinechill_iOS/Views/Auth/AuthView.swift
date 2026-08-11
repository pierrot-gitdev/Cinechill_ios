//
//  AuthView.swift
//  Cinechill_iOS
//

import SwiftUI

/// L'authentification — direction « Le Plan ».
///
/// Une seule planche pour six étapes. Le logo Cinechill est un plan de salle,
/// pas une illustration : l'écran est donc dessiné comme un relevé. Une grille,
/// deux filets, un tracé, trois valeurs de gris. Rien n'y est posé qui ne serve
/// à lire, à saisir ou à se situer.
///
/// Quatre repères tiennent la composition, identiques d'une étape à l'autre —
/// c'est cette constance, et non un effet, qui fait reconnaître l'application :
/// le plafond, le vide du titre, le premier champ, le plancher des actions. Le
/// bouton principal est ainsi toujours à la même hauteur : **le pouce n'apprend
/// qu'une seule position.**
///
/// Il n'y a pas de sélecteur connexion / inscription. Le titre *est* l'état de
/// l'écran, et une phrase mène à l'autre : un sélecteur à deux positions posé
/// au-dessus d'un formulaire dont la longueur triple était une commodité de
/// maquette, pas une aide.
@MainActor
struct AuthView: View {
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var socialStore: SocialStore

    enum Step: Equatable {
        case signIn
        case signUp
        /// Demander le lien de réinitialisation.
        case resetRequest
        /// Le lien est parti — formulation neutre, voir `sendPasswordReset`.
        case resetSent
        /// Choisir le nouveau mot de passe, une fois revenu par le lien.
        case resetNew
        case resetDone
    }

    private enum FormField: Hashable {
        case firstName, lastName, handle, email, password, confirmation
    }

    /// Le code d'action extrait du lien reçu par email. Fourni par l'app, seule
    /// à voir passer les URL entrantes.
    var resetCode: String? = nil
    var onResetCodeConsumed: () -> Void = {}

    @State private var step: Step = .signIn
    @FocusState private var focus: FormField?

    @State private var email = ""
    @State private var password = ""
    @State private var confirmation = ""
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var handle = ""

    /// Tant que l'utilisateur n'a pas touché le champ, le pseudo suit le nom.
    @State private var handleTouched = false
    @State private var handleAvailability: HandleAvailability = .unknown

    /// Ce que dit le contrôle de disponibilité, à tout instant.
    ///
    /// `.unknown` couvre aussi bien « rien saisi » que « le serveur n'a pas pu
    /// répondre » : dans les deux cas on ne montre rien, plutôt que d'inventer
    /// un état d'erreur pour un contrôle qui n'est qu'indicatif. `claimHandle`,
    /// à la soumission, reste seul à trancher pour de bon — un pseudo dit
    /// libre ici peut être pris entretemps par un autre compte.
    private enum HandleAvailability: Equatable {
        case unknown
        case checking
        case free
        case taken
    }

    @State private var failure: AuthFailure?
    @State private var isWorking = false
    @State private var resendIn = 0

    private var fullName: String {
        [firstName, lastName]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    // MARK: - Corps

    var body: some View {
        ZStack {
            AuthInk.ground.ignoresSafeArea()
            planche
                // Le tracé est un **fond**, jamais un frère : voir `plan`.
                .background { plan }
        }
        .onAppear(perform: adoptResetCode)
        .onChange(of: resetCode) { _, _ in adoptResetCode() }
    }

    /// Le tracé : le contour du logo, agrandi et sorti du cadre par le haut et
    /// la droite. Ce n'est pas un décor — c'est la même forme que la signature,
    /// à une autre échelle et à un autre poids.
    ///
    /// **Il doit rester posé en `background` de la planche.** Frère dans le
    /// `ZStack`, il pesait sur la mise en page : ses 552 pt de large sont une
    /// taille idéale, et il suffisait que la pile reçoive une proposition
    /// indéterminée — ce qui arrive quand `AuthView` remplace `MainTabView` à la
    /// déconnexion, là où un lancement à froid propose d'emblée la taille de
    /// l'écran — pour que le `ZStack` adopte 552. Le `GeometryReader` de la
    /// planche lisait alors 552, tout le contenu se centrait sur cette largeur,
    /// et l'écran partait 79 pt à gauche, marges comprises. Un fond, lui, reçoit
    /// la taille de ce qu'il habille et ne peut jamais la changer.
    private var plan: some View {
        CinechillPlanOutline()
            .foregroundStyle(Color(hex: 0xC6D3DF).opacity(0.11))
            .frame(width: 552, height: 552)
            .offset(x: 224, y: -186)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .clipped()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var planche: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    signature
                    PlanEdge()

                    VStack(alignment: .leading, spacing: 0) {
                        content(compact: geo.size.height < 640)
                    }
                    .padding(.horizontal, AuthMetrics.margin)
                }
                .frame(minHeight: geo.size.height, alignment: .top)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    /// La bande haute ne porte que la signature. Le mot « Cinechill » y figure
    /// parce qu'on arrive parfois par un lien d'email, sans être passé par le
    /// splash — c'est le seul écran où le nom doit encore être écrit.
    private var signature: some View {
        HStack(spacing: 9) {
            CinechillMarkOutline()
                .foregroundStyle(AuthInk.ink)
                .frame(width: 20, height: 20)
            Text(verbatim: "Cinechill")
                .planLabel()
                .foregroundStyle(AuthInk.ink)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, AuthMetrics.margin)
        .frame(height: AuthMetrics.signatureBand)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: "Cinechill"))
    }

    // MARK: - Les six étapes

    @ViewBuilder
    private func content(compact: Bool) -> some View {
        let gap = compact ? AuthMetrics.titleGapCompact : AuthMetrics.titleGap

        switch step {
        case .signIn:       signIn(gap: gap, compact: compact)
        case .signUp:       signUp(gap: gap, compact: compact)
        case .resetRequest: resetRequest(gap: gap, compact: compact)
        case .resetSent:    resetSent(gap: gap)
        case .resetNew:     resetNew(gap: gap, compact: compact)
        case .resetDone:    resetDone(gap: gap)
        }
    }

    // MARK: Connexion

    @ViewBuilder
    private func signIn(gap: CGFloat, compact: Bool) -> some View {
        title(String(localized: "Connexion", bundle: .app), gap: gap, compact: compact)

        crossLink(
            question: String(localized: "Pas encore de compte ?", bundle: .app),
            action: String(localized: "Créer un compte", bundle: .app)
        ) {
            go(.signUp)
        }

        VStack(alignment: .leading, spacing: 32) {
            emailField(contentType: .username, submitLabel: .next) { focus = .password }

            PlanField(
                label: String(localized: "Mot de passe", bundle: .app), text: $password, field: .password, focus: $focus,
                placeholder: "••••••••",
                isSecure: true,
                contentType: .password,
                submitLabel: .go,
                accessory: .action(String(localized: "Oublié ?", bundle: .app)) { go(.resetRequest) },
                error: message(for: .password),
                isDisabled: isWorking,
                onSubmit: submit
            )
        }
        .padding(.top, AuthMetrics.formGap)

        Spacer(minLength: 32)

        actions {
            PlanButton(
                title: String(localized: "Entrer", bundle: .app), loadingTitle: String(localized: "Connexion…", bundle: .app),
                isLoading: isWorking, action: submit
            )
            doors
        }
    }

    // MARK: Inscription

    @ViewBuilder
    private func signUp(gap: CGFloat, compact: Bool) -> some View {
        title(String(localized: "Inscription", bundle: .app), gap: gap, compact: compact)

        crossLink(
            question: String(localized: "Déjà un compte ?", bundle: .app),
            action: String(localized: "Se connecter", bundle: .app)
        ) {
            go(.signIn)
        }

        VStack(alignment: .leading, spacing: 26) {
            // Prénom et nom partagent une ligne : deux filets côte à côte se
            // lisent comme une seule règle interrompue, et la paire se voit
            // sans qu'aucun encadré ne la dessine. Une rangée entière gagnée,
            // sur le seul écran où chaque rangée coûte cher.
            HStack(alignment: .top, spacing: 16) {
                PlanField(
                    label: String(localized: "Prénom", bundle: .app), text: $firstName, field: .firstName, focus: $focus,
                    placeholder: String(localized: "Pierre", bundle: .app),
                    contentType: .givenName,
                    error: message(for: .name),
                    isDisabled: isWorking,
                    onSubmit: { focus = .lastName }
                )
                PlanField(
                    label: String(localized: "Nom", bundle: .app), text: $lastName, field: .lastName, focus: $focus,
                    placeholder: String(localized: "Robert", bundle: .app),
                    contentType: .familyName,
                    isDisabled: isWorking,
                    onSubmit: { focus = .handle }
                )
            }
            .onChange(of: firstName) { _, _ in proposeHandle() }
            .onChange(of: lastName) { _, _ in proposeHandle() }

            handleField

            emailField(contentType: .username, submitLabel: .next) { focus = .password }

            passwordField()

            if PlanCriteria.isAcceptable(password) {
                confirmationField
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.top, AuthMetrics.formGap)
        .animation(AuthMetrics.unfold, value: PlanCriteria.isAcceptable(password))

        Spacer(minLength: 32)

        actions {
            PlanButton(
                title: String(localized: "Créer mon compte", bundle: .app), loadingTitle: String(localized: "Création…", bundle: .app),
                isLoading: isWorking, action: submit
            )
            doors
            Text("En créant un compte, tu acceptes les conditions et la politique de confidentialité.", bundle: .app)
                .font(.system(size: 11))
                .foregroundStyle(AuthInk.ink3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
        }
    }

    // MARK: Réinitialisation — demande

    @ViewBuilder
    private func resetRequest(gap: CGFloat, compact: Bool) -> some View {
        title(String(localized: "Mot de passe\noublié", bundle: .app), gap: gap, compact: compact)

        say(String(localized: "Indique l'adresse de ton compte. Nous envoyons un lien pour en choisir un nouveau.", bundle: .app))

        VStack(alignment: .leading, spacing: 32) {
            emailField(contentType: .username, submitLabel: .go, onSubmit: submit)
        }
        .padding(.top, AuthMetrics.formGap)

        Spacer(minLength: 32)

        actions {
            PlanButton(
                title: String(localized: "Envoyer le lien", bundle: .app), loadingTitle: String(localized: "Envoi…", bundle: .app),
                isLoading: isWorking, action: submit
            )
            PlanSecondaryButton(title: String(localized: "Revenir à la connexion", bundle: .app)) { go(.signIn) }
        }
    }

    // MARK: Réinitialisation — envoyé

    @ViewBuilder
    private func resetSent(gap: CGFloat) -> some View {
        // Formulation au conditionnel : avec la protection contre l'énumération
        // des comptes, Firebase réussit que l'adresse existe ou non. Affirmer
        // l'envoi serait faux une fois sur deux ; dire qu'aucun compte n'existe
        // serait une fuite d'information.
        outcome(
            gap: gap,
            headline: String(localized: "Le lien est parti.", bundle: .app),
            detail: String(localized: "Si un compte existe pour \(AuthService.normalize(email)), tu recevras un message d'ici une minute. Pense aux indésirables.", bundle: .app)
        )

        Spacer(minLength: 32)

        actions {
            PlanButton(title: String(localized: "Revenir à la connexion", bundle: .app)) { go(.signIn) }
            // Le bouton reste lisible et annonce son délai. Un bouton grisé sans
            // explication est la première cause de tapotement répété — donc de
            // limitation côté serveur.
            PlanSecondaryButton(
                title: resendIn > 0
                    ? String(localized: "Renvoyer dans \(resendIn) s", bundle: .app)
                    : String(localized: "Renvoyer le lien", bundle: .app),
                isEnabled: resendIn == 0 && !isWorking
            ) {
                Task { await resend() }
            }
        }
        .task(id: resendIn) {
            guard resendIn > 0 else { return }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if resendIn > 0 { resendIn -= 1 }
        }
    }

    // MARK: Réinitialisation — nouveau mot de passe

    @ViewBuilder
    private func resetNew(gap: CGFloat, compact: Bool) -> some View {
        title(String(localized: "Nouveau\nmot de passe", bundle: .app), gap: gap, compact: compact)

        if !email.isEmpty {
            say(String(localized: "Pour \(email).", bundle: .app))
        }

        VStack(alignment: .leading, spacing: 26) {
            passwordField(label: String(localized: "Nouveau mot de passe", bundle: .app))

            if PlanCriteria.isAcceptable(password) {
                confirmationField
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.top, AuthMetrics.formGap)
        .animation(AuthMetrics.unfold, value: PlanCriteria.isAcceptable(password))

        Spacer(minLength: 32)

        actions {
            PlanButton(
                title: String(localized: "Enregistrer", bundle: .app), loadingTitle: String(localized: "Enregistrement…", bundle: .app),
                isLoading: isWorking, action: submit
            )
        }
    }

    // MARK: Réinitialisation — fait

    @ViewBuilder
    private func resetDone(gap: CGFloat) -> some View {
        outcome(
            gap: gap,
            headline: String(localized: "Mot de passe modifié.", bundle: .app),
            detail: String(localized: "Tu peux te connecter avec le nouveau. Ton adresse est déjà reportée sur l'écran suivant.", bundle: .app)
        )

        Spacer(minLength: 32)

        actions {
            PlanButton(title: String(localized: "Se connecter", bundle: .app)) { go(.signIn) }
        }
    }

    // MARK: - Pièces communes

    private func title(_ value: String, gap: CGFloat, compact: Bool) -> some View {
        Text(value)
            .font(.system(size: compact ? 28 : 34, weight: .light))
            .kerning(compact ? -0.78 : -0.95)     // −0,028 em
            .foregroundStyle(AuthInk.ink)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, gap)
            .accessibilityAddTraits(.isHeader)
    }

    private func say(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 14.5))
            .foregroundStyle(AuthInk.ink2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 300, alignment: .leading)
            .padding(.top, 12)
    }

    /// Le passage d'une entrée à l'autre : une phrase, pas un onglet.
    private func crossLink(
        question: String, action: String, perform: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 5) {
            Text(question).foregroundStyle(AuthInk.ink2)
            Button(action: perform) {
                Text(action)
                    .foregroundStyle(AuthInk.ink)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(AuthInk.ruleSet)
                            .frame(height: 1)
                            .offset(y: 2)
                    }
            }
            .buttonStyle(.plain)
        }
        .font(.system(size: 14.5))
        .padding(.top, 12)
    }

    /// Une réussite : une ligne et un point. Pas d'écran de félicitations, pas
    /// de plein écran — la réussite, c'est de pouvoir continuer.
    private func outcome(gap: CGFloat, headline: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            PlanLight()
                .padding(.top, 9)
            VStack(alignment: .leading, spacing: 12) {
                Text(headline)
                    .font(.system(size: 22, weight: .light))
                    .kerning(-0.48)
                    .foregroundStyle(AuthInk.ink)
                Text(detail)
                    .font(.system(size: 14))
                    .foregroundStyle(AuthInk.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 290, alignment: .leading)
            }
        }
        .padding(.top, gap)
        .accessibilityElement(children: .combine)
    }

    /// Le bloc d'actions, construit depuis le bas de la zone sûre. La panne
    /// technique s'y installe au-dessus : elle ne vient d'aucun champ, elle ne
    /// se pose donc sur aucun.
    private func actions<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 8) {
            if let failure, failure.field == .form {
                PlanAlert(message: failure.message, retry: submit)
                    .padding(.bottom, 16)
                    .transition(.opacity)
            }
            content()
        }
        .padding(.bottom, AuthMetrics.floor)
        .animation(AuthMetrics.shift, value: failure)
    }

    /// Les portes tierces. Apple passe devant Google : c'est la position
    /// attendue en revue App Store, et la plus rapide sur iOS.
    private var doors: some View {
        Group {
            PlanSecondaryButton(
                title: String(localized: "Continuer avec Apple", bundle: .app),
                icon: Image(systemName: "apple.logo"),
                isEnabled: !isWorking
            ) {
                Task { await run { try await authService.signInWithApple() } }
            }
            PlanSecondaryButton(title: String(localized: "Continuer avec Google", bundle: .app), isEnabled: !isWorking) {
                Task { await run { try await authService.signInWithGoogle() } }
            }
        }
    }

    // MARK: - Champs

    private func emailField(
        contentType: UITextContentType,
        submitLabel: SubmitLabel,
        onSubmit: @escaping () -> Void = {}
    ) -> some View {
        PlanField(
            label: String(localized: "Email", bundle: .app), text: $email, field: .email, focus: $focus,
            placeholder: String(localized: "toi@exemple.com", bundle: .app),
            keyboard: .emailAddress,
            contentType: contentType,
            submitLabel: submitLabel,
            error: message(for: .email),
            isDisabled: isWorking,
            onSubmit: onSubmit
        )
    }

    private func passwordField(label: String = String(localized: "Mot de passe", bundle: .app)) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            PlanField(
                label: label, text: $password, field: .password, focus: $focus,
                placeholder: "••••••••",
                isSecure: true,
                contentType: .newPassword,
                error: message(for: .password),
                isDisabled: isWorking,
                onSubmit: { focus = .confirmation }
            )
            if message(for: .password) == nil {
                PlanCriteria(password: password)
            }
        }
    }

    private var confirmationField: some View {
        PlanField(
            label: String(localized: "Confirmer", bundle: .app), text: $confirmation, field: .confirmation, focus: $focus,
            placeholder: "••••••••",
            isSecure: true,
            contentType: .newPassword,
            submitLabel: .go,
            // Le point paraît dès que les deux valeurs correspondent, sans
            // attendre la validation. Tant qu'elles diffèrent, rien ne
            // s'affiche : on ne reproche pas une saisie inachevée.
            accessory: !confirmation.isEmpty && confirmation == password ? .light : .none,
            error: message(for: .confirmation),
            isDisabled: isWorking,
            onSubmit: submit
        )
        .animation(AuthMetrics.shift, value: confirmation == password)
    }

    /// La saisie passe par une liaison intermédiaire plutôt que par `onChange` :
    /// c'est le seul moyen de distinguer une frappe d'une écriture programmée.
    /// `proposeHandle` écrit directement dans l'état et ne marque donc jamais le
    /// champ comme touché — sans quoi la proposition se désarmerait elle-même.
    private var handleEntry: Binding<String> {
        Binding(
            get: { handle },
            set: { typed in
                handleTouched = true
                // Réinitialisé tout de suite, pour que le point de lumière
                // s'éteigne à la première frappe plutôt que d'attendre la fin
                // du débounce : rien ne s'affiche tant que rien n'est vérifié.
                handleAvailability = .unknown
                // La normalisation se fait sous les doigts, jamais en reproche :
                // une majuscule ou un accent est une faute de conception si on
                // la signale, pas une faute de l'utilisateur.
                handle = PlanHandle.normalize(typed)
            }
        )
    }

    private var handleField: some View {
        VStack(alignment: .leading, spacing: 0) {
            PlanField(
                label: String(localized: "Pseudo", bundle: .app), text: handleEntry, field: .handle, focus: $focus,
                placeholder: String(localized: "pierre.robert", bundle: .app),
                prefix: "@",
                contentType: .username,
                accessory: handleAvailability == .free ? .light : .none,
                error: handleAvailability == .taken
                    ? String(localized: "Ce pseudo est déjà pris.", bundle: .app) : message(for: .handle),
                note: handleAvailability == .taken ? nil : PlanHandle.rule,
                isDisabled: isWorking,
                onSubmit: { focus = .email }
            )

            if handleAvailability == .taken {
                alternatives
            }
        }
        .animation(AuthMetrics.shift, value: handleAvailability)
        // Vérifie 450 ms après la dernière frappe. `.task(id:)` annule
        // d'elle-même la précédente dès que `handle` change : pas de
        // minuterie à gérer à la main.
        .task(id: handle) {
            guard PlanHandle.isValid(handle) else { return }
            handleAvailability = .checking
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            do {
                let free = try await socialStore.handleAvailability(handle)
                guard !Task.isCancelled else { return }
                handleAvailability = free ? .free : .taken
            } catch {
                // Panne réseau sur un contrôle indicatif : on se tait plutôt
                // que d'inventer un état d'erreur. `claimHandle` tranchera à
                // la soumission, avec ou sans ce contrôle.
                guard !Task.isCancelled else { return }
                handleAvailability = .unknown
            }
        }
    }

    /// Trois replis, touchables. On ne met jamais quelqu'un devant un mur sans
    /// lui tendre une porte — d'autant que c'est ici, sur le dernier champ
    /// inventé du formulaire, qu'on abandonne.
    private var alternatives: some View {
        HStack(spacing: 7) {
            ForEach(PlanHandle.alternatives(for: handle), id: \.self) { candidate in
                Button {
                    handle = candidate
                    handleAvailability = .unknown
                    Haptics.selection()
                } label: {
                    Text(verbatim: "@\(candidate)")
                        .font(.system(size: 11.5))
                        .foregroundStyle(AuthInk.ink)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .overlay(
                            RoundedRectangle(cornerRadius: AuthMetrics.radius, style: .continuous)
                                .stroke(AuthInk.ruleSet, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 10)
    }

    // MARK: - Erreurs

    /// Une erreur ne s'affiche que sous le champ qu'elle concerne. Celles qui ne
    /// viennent d'aucune saisie portent `.form` et vivent au-dessus des actions.
    private func message(for field: AuthField) -> String? {
        guard let failure, failure.field == field else { return nil }
        return failure.message + repair(failure.repair)
    }

    private func repair(_ repair: AuthRepair?) -> String {
        switch repair {
        case .resetPassword: return String(localized: " Tu peux le **réinitialiser**.", bundle: .app)
        case .signIn:        return String(localized: " **Se connecter** ?", bundle: .app)
        case .signUp:        return String(localized: " **Créer un compte** ?", bundle: .app)
        case nil:            return ""
        }
    }

    // MARK: - Navigation

    private func go(_ next: Step) {
        guard step != next else { return }
        Haptics.selection()
        focus = nil
        failure = nil
        handleAvailability = .unknown

        // Le mot de passe ne survit jamais à un changement d'étape : le garder
        // d'un écran à l'autre n'apporte rien et le laisse traîner en mémoire.
        password = ""
        confirmation = ""

        withAnimation(.easeInOut(duration: 0.22)) { step = next }
    }

    /// Reprend le pseudo depuis le nom tant que le champ n'a pas été touché.
    /// Dans le cas courant, l'utilisateur ne remplit jamais ce champ lui-même.
    private func proposeHandle() {
        guard !handleTouched else { return }
        let proposed = PlanHandle.normalize(fullName)
        guard proposed != handle else { return }
        handle = proposed
        handleAvailability = .unknown
    }

    private func adoptResetCode() {
        guard let code = resetCode, !code.isEmpty, step != .resetNew else { return }
        Task {
            isWorking = true
            defer { isWorking = false }
            do {
                email = try await authService.verifyResetCode(code)
                password = ""
                confirmation = ""
                failure = nil
                withAnimation(.easeInOut(duration: 0.22)) { step = .resetNew }
            } catch {
                // Lien expiré ou déjà servi : on le dit, et on propose d'en
                // redemander un. Jamais de cul-de-sac.
                failure = (error as? AuthFailure)
                    ?? .form(String(localized: "Ce lien a expiré ou a déjà servi.", bundle: .app))
                withAnimation(.easeInOut(duration: 0.22)) { step = .resetRequest }
            }
            onResetCodeConsumed()
        }
    }

    // MARK: - Soumission

    private func submit() {
        guard !isWorking else { return }
        // `Task` détachée du cycle de vie de la vue : à l'inscription, l'état
        // d'authentification bascule dès la création du compte et cette vue
        // disparaît. Le travail qui suit — pseudo, nom d'affichage — doit
        // survivre à sa disparition, sinon il est annulé au pire moment.
        Task { await run(perform) }
    }

    /// Une seule enveloppe pour tout ce qui appelle le réseau : elle tient
    /// l'indicateur d'attente et le rapport d'erreur, si bien qu'aucun appelant
    /// ne peut oublier l'un des deux.
    private func run(_ work: @escaping () async throws -> Void) async {
        guard !isWorking else { return }
        isWorking = true
        failure = nil
        defer { isWorking = false }

        do {
            try await work()
        } catch let error as AuthFailure {
            report(error)
        } catch {
            report(.form(error.localizedDescription))
        }
    }

    private func perform() async throws {
        switch step {
        case .signIn:
            focus = nil
            try await authService.signIn(email: email, password: password)

        case .signUp:
            try await runSignUp()

        case .resetRequest:
            focus = nil
            try await authService.sendPasswordReset(email: email)
            resendIn = 45
            withAnimation(.easeInOut(duration: 0.22)) { step = .resetSent }

        case .resetNew:
            try await runResetNew()

        case .resetSent, .resetDone:
            break
        }
    }

    private func runSignUp() async throws {
        // L'ordre de validation suit l'ordre de lecture : sinon le focus saute
        // par-dessus un champ fautif et l'utilisateur corrige à l'aveugle.
        guard !firstName.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw AuthFailure(field: .name, message: String(localized: "Indique ton prénom.", bundle: .app))
        }
        guard PlanHandle.isValid(handle) else {
            throw AuthFailure(field: .handle, message: PlanHandle.rule)
        }
        // Le contrôle en direct dit déjà « pris » : pas besoin d'aller créer le
        // compte pour l'apprendre une seconde fois. S'il est resté `.unknown`
        // (aucune vérification, ou panne réseau), `claimHandle` tranchera après
        // la création — c'est toujours lui qui a le dernier mot. Le champ
        // affiche déjà « Ce pseudo est déjà pris. » depuis `handleAvailability` ;
        // cette panne ne sert qu'à ramener le focus dessus.
        guard handleAvailability != .taken else {
            throw AuthFailure(field: .handle, message: String(localized: "Ce pseudo est déjà pris.", bundle: .app))
        }
        guard confirmation == password else {
            // Le seul geste utile : vider la confirmation et y revenir. On
            // ignore laquelle des deux saisies est la bonne.
            confirmation = ""
            throw AuthFailure(
                field: .confirmation,
                message: String(localized: "Les deux mots de passe ne correspondent pas.", bundle: .app)
            )
        }

        focus = nil
        try await authService.signUp(email: email, password: password)

        // Le compte existe : à partir d'ici plus rien ne doit interrompre le
        // parcours. Le nom d'affichage et le pseudo se réparent dans le profil,
        // le compte non.
        await authService.updateDisplayName(fullName)
        do {
            try await socialStore.claimHandle(handle, displayName: fullName)
        } catch {
            // Pseudo pris entre le contrôle en direct et la création — la
            // fenêtre est étroite mais réelle. `ProfileView` propose déjà
            // `ClaimHandleSheet` quand aucun profil public n'existe : c'est le
            // même rattrapage que pour une connexion Google, qui ne fournit
            // pas de pseudo non plus.
            handleAvailability = .taken
        }
        Haptics.success()
    }

    private func runResetNew() async throws {
        guard let code = resetCode, !code.isEmpty else {
            throw AuthFailure(field: .form, message: String(localized: "Ce lien a expiré ou a déjà servi.", bundle: .app))
        }
        guard confirmation == password else {
            confirmation = ""
            throw AuthFailure(
                field: .confirmation,
                message: String(localized: "Les deux mots de passe ne correspondent pas.", bundle: .app)
            )
        }

        focus = nil
        try await authService.confirmPasswordReset(code: code, newPassword: password)
        password = ""
        confirmation = ""
        Haptics.success()
        withAnimation(.easeInOut(duration: 0.22)) { step = .resetDone }
    }

    private func resend() async {
        guard resendIn == 0 else { return }
        await run {
            try await authService.sendPasswordReset(email: email)
            resendIn = 45
            Haptics.selection()
        }
    }

    /// Une seule vibration par soumission ratée, jamais une par champ : trois
    /// d'affilée se lisent comme une panne de l'appareil.
    private func report(_ error: AuthFailure) {
        Haptics.warning()
        withAnimation(AuthMetrics.shift) { failure = error }

        switch error.field {
        case .name:         focus = .firstName
        case .handle:       focus = .handle
        case .email:        focus = .email
        case .password:     focus = .password
        case .confirmation: focus = .confirmation
        case .form:         break
        }
    }
}

#Preview("Authentification") {
    AuthView()
        .environmentObject(AuthService())
        .environmentObject(SocialStore())
}
