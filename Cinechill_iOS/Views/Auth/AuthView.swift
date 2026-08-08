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
    /// Renseigné par le serveur au moment de la revendication : faute d'endpoint
    /// de disponibilité, c'est le seul instant où l'on sait.
    @State private var handleTaken = false

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
            plan
            planche
        }
        .onAppear(perform: adoptResetCode)
        .onChange(of: resetCode) { _, _ in adoptResetCode() }
    }

    /// Le tracé : le contour du logo, agrandi et sorti du cadre par le haut et
    /// la droite. Ce n'est pas un décor — c'est la même forme que la signature,
    /// à une autre échelle et à un autre poids.
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
            Text("Cinechill")
                .planLabel()
                .foregroundStyle(AuthInk.ink)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, AuthMetrics.margin)
        .frame(height: AuthMetrics.signatureBand)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Cinechill")
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
        title("Connexion", gap: gap, compact: compact)

        crossLink(question: "Pas encore de compte ?", action: "Créer un compte") {
            go(.signUp)
        }

        VStack(alignment: .leading, spacing: 32) {
            emailField(contentType: .username, submitLabel: .next) { focus = .password }

            PlanField(
                label: "Mot de passe", text: $password, field: .password, focus: $focus,
                placeholder: "••••••••",
                isSecure: true,
                contentType: .password,
                submitLabel: .go,
                accessory: .action("Oublié ?") { go(.resetRequest) },
                error: message(for: .password),
                isDisabled: isWorking,
                onSubmit: submit
            )
        }
        .padding(.top, AuthMetrics.formGap)

        Spacer(minLength: 32)

        actions {
            PlanButton(
                title: "Entrer", loadingTitle: "Connexion…",
                isLoading: isWorking, action: submit
            )
            doors
        }
    }

    // MARK: Inscription

    @ViewBuilder
    private func signUp(gap: CGFloat, compact: Bool) -> some View {
        title("Inscription", gap: gap, compact: compact)

        crossLink(question: "Déjà un compte ?", action: "Se connecter") {
            go(.signIn)
        }

        VStack(alignment: .leading, spacing: 26) {
            // Prénom et nom partagent une ligne : deux filets côte à côte se
            // lisent comme une seule règle interrompue, et la paire se voit
            // sans qu'aucun encadré ne la dessine. Une rangée entière gagnée,
            // sur le seul écran où chaque rangée coûte cher.
            HStack(alignment: .top, spacing: 16) {
                PlanField(
                    label: "Prénom", text: $firstName, field: .firstName, focus: $focus,
                    placeholder: "Pierre",
                    contentType: .givenName,
                    error: message(for: .name),
                    isDisabled: isWorking,
                    onSubmit: { focus = .lastName }
                )
                PlanField(
                    label: "Nom", text: $lastName, field: .lastName, focus: $focus,
                    placeholder: "Robert",
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
                title: "Créer mon compte", loadingTitle: "Création…",
                isLoading: isWorking, action: submit
            )
            doors
            Text("En créant un compte, vous acceptez les conditions et la politique de confidentialité.")
                .font(.system(size: 11))
                .foregroundStyle(AuthInk.ink3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
        }
    }

    // MARK: Réinitialisation — demande

    @ViewBuilder
    private func resetRequest(gap: CGFloat, compact: Bool) -> some View {
        title("Mot de passe\noublié", gap: gap, compact: compact)

        say("Indiquez l'adresse de votre compte. Nous envoyons un lien pour en choisir un nouveau.")

        VStack(alignment: .leading, spacing: 32) {
            emailField(contentType: .username, submitLabel: .go, onSubmit: submit)
        }
        .padding(.top, AuthMetrics.formGap)

        Spacer(minLength: 32)

        actions {
            PlanButton(
                title: "Envoyer le lien", loadingTitle: "Envoi…",
                isLoading: isWorking, action: submit
            )
            PlanSecondaryButton(title: "Revenir à la connexion") { go(.signIn) }
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
            headline: "Le lien est parti.",
            detail: "Si un compte existe pour \(AuthService.normalize(email)), "
                + "vous recevrez un message d'ici une minute. Pensez aux indésirables."
        )

        Spacer(minLength: 32)

        actions {
            PlanButton(title: "Revenir à la connexion") { go(.signIn) }
            // Le bouton reste lisible et annonce son délai. Un bouton grisé sans
            // explication est la première cause de tapotement répété — donc de
            // limitation côté serveur.
            PlanSecondaryButton(
                title: resendIn > 0 ? "Renvoyer dans \(resendIn) s" : "Renvoyer le lien",
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
        title("Nouveau\nmot de passe", gap: gap, compact: compact)

        if !email.isEmpty {
            say("Pour \(email).")
        }

        VStack(alignment: .leading, spacing: 26) {
            passwordField(label: "Nouveau mot de passe")

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
                title: "Enregistrer", loadingTitle: "Enregistrement…",
                isLoading: isWorking, action: submit
            )
        }
    }

    // MARK: Réinitialisation — fait

    @ViewBuilder
    private func resetDone(gap: CGFloat) -> some View {
        outcome(
            gap: gap,
            headline: "Mot de passe modifié.",
            detail: "Vous pouvez vous connecter avec le nouveau. "
                + "Votre adresse est déjà reportée sur l'écran suivant."
        )

        Spacer(minLength: 32)

        actions {
            PlanButton(title: "Se connecter") { go(.signIn) }
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
                title: "Continuer avec Apple",
                icon: Image(systemName: "apple.logo"),
                isEnabled: !isWorking
            ) {
                Task { await run { try await authService.signInWithApple() } }
            }
            PlanSecondaryButton(title: "Continuer avec Google", isEnabled: !isWorking) {
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
            label: "Email", text: $email, field: .email, focus: $focus,
            placeholder: "vous@exemple.com",
            keyboard: .emailAddress,
            contentType: contentType,
            submitLabel: submitLabel,
            error: message(for: .email),
            isDisabled: isWorking,
            onSubmit: onSubmit
        )
    }

    private func passwordField(label: String = "Mot de passe") -> some View {
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
            label: "Confirmer", text: $confirmation, field: .confirmation, focus: $focus,
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
                handleTaken = false
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
                label: "Pseudo", text: handleEntry, field: .handle, focus: $focus,
                placeholder: "pierre.robert",
                prefix: "@",
                contentType: .username,
                accessory: PlanHandle.isValid(handle) && !handleTaken ? .light : .none,
                error: handleTaken ? "Ce pseudo est déjà pris." : message(for: .handle),
                note: handleTaken ? nil : PlanHandle.rule,
                isDisabled: isWorking,
                onSubmit: { focus = .email }
            )

            if handleTaken {
                alternatives
            }
        }
        .animation(AuthMetrics.shift, value: handleTaken)
    }

    /// Trois replis, touchables. On ne met jamais quelqu'un devant un mur sans
    /// lui tendre une porte — d'autant que c'est ici, sur le dernier champ
    /// inventé du formulaire, qu'on abandonne.
    private var alternatives: some View {
        HStack(spacing: 7) {
            ForEach(PlanHandle.alternatives(for: handle), id: \.self) { candidate in
                Button {
                    handle = candidate
                    handleTaken = false
                    Haptics.selection()
                } label: {
                    Text("@\(candidate)")
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
        case .resetPassword: return " Vous pouvez le **réinitialiser**."
        case .signIn:        return " **Se connecter** ?"
        case .signUp:        return " **Créer un compte** ?"
        case nil:            return ""
        }
    }

    // MARK: - Navigation

    private func go(_ next: Step) {
        guard step != next else { return }
        Haptics.selection()
        focus = nil
        failure = nil
        handleTaken = false

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
        handleTaken = false
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
                failure = (error as? AuthFailure) ?? .form("Ce lien a expiré ou a déjà servi.")
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
            throw AuthFailure(field: .name, message: "Indiquez votre prénom.")
        }
        guard PlanHandle.isValid(handle) else {
            throw AuthFailure(field: .handle, message: PlanHandle.rule)
        }
        guard confirmation == password else {
            // Le seul geste utile : vider la confirmation et y revenir. On
            // ignore laquelle des deux saisies est la bonne.
            confirmation = ""
            throw AuthFailure(
                field: .confirmation,
                message: "Les deux mots de passe ne correspondent pas."
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
            // Pseudo pris entre la saisie et la création. `ProfileView` propose
            // déjà `ClaimHandleSheet` quand aucun profil public n'existe : c'est
            // le même rattrapage que pour une connexion Google, qui ne fournit
            // pas de pseudo non plus.
            handleTaken = true
        }
        Haptics.success()
    }

    private func runResetNew() async throws {
        guard let code = resetCode, !code.isEmpty else {
            throw AuthFailure(field: .form, message: "Ce lien a expiré ou a déjà servi.")
        }
        guard confirmation == password else {
            confirmation = ""
            throw AuthFailure(
                field: .confirmation,
                message: "Les deux mots de passe ne correspondent pas."
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
