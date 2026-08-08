//
//  AuthComponents.swift
//  Cinechill_iOS
//

import SwiftUI

// MARK: - Encres

/// Les six valeurs de l'authentification — direction « Le Plan ».
///
/// Trois gris, deux états, un fond. En régime courant un écran n'en emploie que
/// quatre : l'accent et l'écart ne servent qu'à dire quelque chose. Toutes sont
/// dérivées de `CinechillPalette`, à plat — aucun dégradé, aucune lueur.
enum AuthInk {
    static let ground = CinechillPalette.night          // #0A0F16
    static let ink = Color(hex: 0xEDF1F5)
    static let ink2 = Color(hex: 0x8D9AA8)              // étain
    static let ink3 = Color(hex: 0x59636E)              // ardoise

    static let rule = Color(hex: 0xC6D3DF).opacity(0.13)
    static let ruleSet = Color(hex: 0xC6D3DF).opacity(0.26)

    /// Le point de lumière de la famille d'icônes. Deux occurrences par écran au
    /// maximum, et jamais autrement que sous la forme d'un carré de 5 pt.
    static let light = CinechillPalette.light           // #7FE3FF
    /// L'écart. Seule teinte chaude de l'application.
    static let warn = Color(hex: 0xE5A276)
}

/// Les mesures de la planche. Elles ne dépendent d'aucun contenu : ce sont les
/// mêmes sur les six écrans du parcours, et c'est cette constance — pas un
/// effet — qui fait qu'on reconnaît l'application d'un écran à l'autre.
enum AuthMetrics {
    static let margin: CGFloat = 24

    /// Hauteur de la bande de signature, mesurée dans la zone sûre. Avec la
    /// barre d'état d'un iPhone récent, le filet tombe à ~96 pt du haut de
    /// l'appareil — le repère du plan.
    static let signatureBand: CGFloat = 52
    /// Vide entre le filet et la première lettre du titre. C'est le plus grand
    /// vide de l'écran, et il est *devant* le contenu, pas derrière.
    static let titleGap: CGFloat = 88
    /// Le même, sur les écrans courts : seul ce repère cède.
    static let titleGapCompact: CGFloat = 48
    /// Vide entre l'accroche et le premier champ.
    static let formGap: CGFloat = 44
    /// Distance du bloc d'actions au bas de la zone sûre.
    static let floor: CGFloat = 32

    static let field: CGFloat = 32
    static let button: CGFloat = 52
    static let buttonSecondary: CGFloat = 48
    static let radius: CGFloat = 3

    /// Une transition de valeur, pas une animation : rien ne se déplace.
    static let shift = Animation.easeOut(duration: 0.18)
    /// Le dépliage de la confirmation — seul mouvement de mise en page du parcours.
    static let unfold = Animation.easeOut(duration: 0.2)
}

// MARK: - Typographie

extension View {
    /// Le niveau de service : libellés et actions secondaires. Interlettré parce
    /// que des capitales serrées ne se lisent pas, gras parce qu'à 10 pt une
    /// graisse fine disparaît.
    func planLabel() -> some View {
        self.font(.system(size: 10, weight: .semibold))
            .tracking(1.8)
            .textCase(.uppercase)
    }
}

// MARK: - Le point

/// Le seul aplat de l'interface. Il ne dit que deux choses : « ce pseudo est
/// libre », « les deux mots de passe correspondent ».
struct PlanLight: View {
    var tint: Color = AuthInk.light

    var body: some View {
        Rectangle()
            .fill(tint)
            .frame(width: 5, height: 5)
            .transition(.opacity)
    }
}

// MARK: - Le champ

/// Ce qui se pose à droite du libellé.
enum PlanAccessory {
    case none
    /// Une action courte — « Oublié ? ».
    case action(String, () -> Void)
    /// Le point de lumière, quand la valeur est vérifiée.
    case light
}

/// Un champ : libellé, valeur, filet, note. Quatre lignes, jamais cinq.
///
/// Le libellé ne flotte pas. Un libellé qui flotte disparaît exactement au
/// moment où l'on remplit le champ — c'est-à-dire au moment où l'on aurait
/// besoin de relire ce qu'on est en train de renseigner.
///
/// L'état ne s'exprime que par la valeur du filet : `rule` au repos, `ruleSet`
/// une fois rempli, l'encre pleine au focus, l'écart en cas d'erreur. Pas de
/// bordure qui apparaît, pas de fond qui s'allume.
struct PlanField<Value: Hashable>: View {
    let label: String
    @Binding var text: String
    let field: Value
    var focus: FocusState<Value?>.Binding

    var placeholder: String = ""
    var isSecure: Bool = false
    /// Le « @ » du pseudo. Ne paraît qu'une fois le champ engagé, pour ne pas
    /// meubler une ligne vide.
    var prefix: String?
    var keyboard: UIKeyboardType = .default
    var contentType: UITextContentType?
    var submitLabel: SubmitLabel = .next
    var accessory: PlanAccessory = .none
    /// Le message d'écart. Remplace la note quand il est présent.
    var error: String?
    /// La note de service — critères, règle du pseudo. Toujours du texte.
    var note: String?
    var isDisabled: Bool = false
    var onSubmit: () -> Void = {}

    private var isActive: Bool { focus.wrappedValue == field }
    private var isSet: Bool { !text.isEmpty }
    private var hasError: Bool { error?.isEmpty == false }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            row
            Rectangle()
                .fill(ruleTint)
                .frame(height: 1)
            footer
        }
        .animation(AuthMetrics.shift, value: isActive)
        .animation(AuthMetrics.shift, value: hasError)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
        .accessibilityValue(error ?? text)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .planLabel()
                .foregroundStyle(labelTint)

            Spacer(minLength: 8)

            switch accessory {
            case .none:
                EmptyView()
            case .action(let title, let perform):
                Button(title, action: perform)
                    .buttonStyle(.plain)
                    .planLabel()
                    .foregroundStyle(AuthInk.ink3)
                    // La cible déborde le texte : 10 pt de haut ne se touchent
                    // pas. Le débord reste modeste — au-delà, il mordrait sur
                    // la fin du champ, juste en dessous.
                    .contentShape(Rectangle().inset(by: -8))
            case .light:
                PlanLight()
            }
        }
        .frame(height: 16)
    }

    private var row: some View {
        HStack(spacing: 10) {
            if let prefix, isActive || isSet {
                Text(prefix)
                    .font(.system(size: 17))
                    .foregroundStyle(AuthInk.ink3)
                    .transition(.opacity)
            }

            Group {
                if isSecure {
                    SecureField("", text: $text, prompt: prompt)
                } else {
                    TextField("", text: $text, prompt: prompt)
                }
            }
            .font(.system(size: 17))
            .kerning(-0.17)
            .foregroundStyle(AuthInk.ink)
            .tint(AuthInk.ink)
            .textInputAutocapitalization(capitalization)
            .autocorrectionDisabled()
            .keyboardType(keyboard)
            .textContentType(contentType)
            .submitLabel(submitLabel)
            .focused(focus, equals: field)
            .disabled(isDisabled)
            .onSubmit(onSubmit)
        }
        .frame(height: AuthMetrics.field)
    }

    @ViewBuilder
    private var footer: some View {
        if let message = error, !message.isEmpty {
            noteText(message, tint: AuthInk.warn)
        } else if let note, !note.isEmpty {
            noteText(note, tint: AuthInk.ink3)
        }
    }

    private func noteText(_ value: String, tint: Color) -> some View {
        Text(.init(value))              // le gras du repli est écrit en Markdown
            .font(.system(size: 12))
            .foregroundStyle(tint)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 9)
            .transition(.opacity)
    }

    private var prompt: Text {
        Text(placeholder).foregroundColor(AuthInk.ink3)
    }

    private var capitalization: TextInputAutocapitalization {
        contentType == .givenName || contentType == .familyName ? .words : .never
    }

    private var ruleTint: Color {
        if hasError { return AuthInk.warn }
        if isActive { return AuthInk.ink }
        return isSet ? AuthInk.ruleSet : AuthInk.rule
    }

    private var labelTint: Color {
        if hasError { return AuthInk.warn }
        return isActive ? AuthInk.ink : AuthInk.ink2
    }
}

// MARK: - Les actions

/// L'action principale : le seul aplat clair de l'écran, et donc le seul objet
/// sur lequel l'œil n'hésite pas.
///
/// Le chargement se joue dans le bouton — un filet de 2 pt parcourt son bord
/// bas. Pas de voile, pas de roue posée ailleurs, et le libellé dit ce qui se
/// passe plutôt que de disparaître.
struct PlanButton: View {
    let title: String
    var loadingTitle: String?
    var isLoading: Bool = false
    var isEnabled: Bool = true
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var travel: CGFloat = -1

    var body: some View {
        Button(action: action) {
            Text(isLoading ? (loadingTitle ?? title) : title)
                .font(.system(size: 15.5, weight: .semibold))
                .kerning(-0.08)
                .foregroundStyle(AuthInk.ground)
                .frame(maxWidth: .infinity)
                .frame(height: AuthMetrics.button)
                .background(AuthInk.ink)
                .overlay(alignment: .bottomLeading) { progress }
                .clipShape(RoundedRectangle(cornerRadius: AuthMetrics.radius, style: .continuous))
                .opacity(isEnabled && !isLoading ? 1 : 0.6)
        }
        .buttonStyle(PressableScaleStyle(scale: 0.985))
        .disabled(isLoading || !isEnabled)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isLoading ? [.updatesFrequently] : [])
    }

    @ViewBuilder
    private var progress: some View {
        if isLoading && !reduceMotion {
            GeometryReader { geo in
                Rectangle()
                    .fill(AuthInk.ground.opacity(0.4))
                    .frame(width: geo.size.width * 0.45, height: 2)
                    .offset(x: travel * geo.size.width)
                    .onAppear {
                        travel = -0.45
                        withAnimation(.easeInOut(duration: 1.05).repeatForever(autoreverses: false)) {
                            travel = 1
                        }
                    }
            }
            .frame(height: 2)
        }
    }
}

/// Une porte tierce, ou un retour. Contour, jamais rempli : ce sont des
/// alternatives, pas des concurrentes de l'action principale.
struct PlanSecondaryButton: View {
    let title: String
    var icon: Image?
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                if let icon {
                    icon.font(.system(size: 15, weight: .medium))
                }
                Text(title)
                    .font(.system(size: 14.5, weight: .medium))
            }
            .foregroundStyle(AuthInk.ink)
            .frame(maxWidth: .infinity)
            .frame(height: AuthMetrics.buttonSecondary)
            .overlay(
                RoundedRectangle(cornerRadius: AuthMetrics.radius, style: .continuous)
                    .stroke(AuthInk.ruleSet, lineWidth: 1)
            )
            .opacity(isEnabled ? 1 : 0.5)
        }
        .buttonStyle(PressableScaleStyle(scale: 0.985))
        .disabled(!isEnabled)
    }
}

// MARK: - La panne technique

/// Une erreur qui ne vient d'aucun champ ne se pose sur aucun : elle s'installe
/// au-dessus des actions, entre deux filets. Aucun fond, aucune carte — le
/// dispositif est le même que le plafond et le plancher, à une couleur près.
struct PlanAlert: View {
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(AuthInk.warn)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let retry {
                Button("Réessayer", action: retry)
                    .buttonStyle(.plain)
                    .planLabel()
                    .foregroundStyle(AuthInk.ink)
                    .contentShape(Rectangle().inset(by: -12))
            }
        }
        .padding(.vertical, 12)
        .overlay(alignment: .top) { Rectangle().fill(AuthInk.warn).frame(height: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(AuthInk.rule).frame(height: 1) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
    }
}

// MARK: - Les critères

/// Les exigences du mot de passe, écrites plutôt que jaugées.
///
/// Chaque critère atteint passe de l'ardoise à l'étain. Une jauge à segments
/// colorés dirait la même chose en inventant un composant et deux couleurs, et
/// surtout elle ne dirait pas *ce qui manque* — un utilisateur devant deux
/// barres oranges ne sait pas quoi taper de plus.
struct PlanCriteria: View {
    let password: String

    static func isLongEnough(_ value: String) -> Bool { value.count >= 8 }
    static func hasVariety(_ value: String) -> Bool {
        value.contains { $0.isUppercase || $0.isNumber }
    }
    static func isAcceptable(_ value: String) -> Bool {
        isLongEnough(value) && hasVariety(value)
    }

    var body: some View {
        HStack(spacing: 6) {
            item("8 caractères", met: Self.isLongEnough(password))
            Text("·").foregroundStyle(AuthInk.ink3)
            item("une majuscule ou un chiffre", met: Self.hasVariety(password))
        }
        .font(.system(size: 12))
        .padding(.top, 9)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            Self.isAcceptable(password)
                ? "Mot de passe conforme"
                : "Il faut 8 caractères et une majuscule ou un chiffre"
        )
    }

    private func item(_ title: String, met: Bool) -> some View {
        Text(title)
            .foregroundStyle(met ? AuthInk.ink2 : AuthInk.ink3)
            .animation(AuthMetrics.shift, value: met)
    }
}

// MARK: - Le pseudo

/// Les bornes du pseudo, alignées sur `ClaimHandleSheet` et sur `isValidHandle`
/// côté serveur : 3 à 20 caractères, minuscules, chiffres, point et tiret bas.
///
/// La normalisation se fait sous les doigts plutôt qu'en reproche : une
/// majuscule ou un accent est une faute de conception si on la signale, pas une
/// faute de l'utilisateur.
enum PlanHandle {
    static let rule = "3 à 20 caractères, minuscules, chiffres, point et tiret bas."

    static func normalize(_ raw: String) -> String {
        let folded = raw.folding(
            options: [.diacriticInsensitive],
            locale: Locale(identifier: "fr_FR")
        ).lowercased()

        // Tout ce qui n'est pas admis devient un point : « Robert-Émile » se
        // lit « robert.emile », et non « robertemile ».
        var out = ""
        var lastWasSeparator = true          // évite un séparateur en tête
        for character in folded {
            let admitted = character.isNumber
                || character == "_"
                || character == "."
                || (character.isLetter && character.isASCII)
            if admitted && character != "." && character != "_" {
                out.append(character)
                lastWasSeparator = false
            } else if !lastWasSeparator {
                out.append(character == "_" ? "_" : ".")
                lastWasSeparator = true
            }
        }
        while let last = out.last, last == "." || last == "_" { out.removeLast() }
        return String(out.prefix(20))
    }

    static func isValid(_ handle: String) -> Bool {
        (3...20).contains(handle.count) && handle == normalize(handle)
    }

    /// Trois replis, quand le pseudo demandé est pris. On ne met jamais
    /// quelqu'un devant un mur sans lui tendre une porte — d'autant que c'est
    /// ici, sur le dernier champ inventé du formulaire, qu'on abandonne.
    static func alternatives(for handle: String) -> [String] {
        guard !handle.isEmpty else { return [] }
        let parts = handle.split(separator: ".")
        var out: [String] = []

        out.append(normalize(handle + "2"))
        out.append(normalize(handle.replacingOccurrences(of: ".", with: "_")))
        if let first = parts.first?.first, let last = parts.last, parts.count > 1 {
            out.append(normalize("\(first).\(last)"))
        }

        var seen = Set([handle])
        return out.filter { candidate in
            guard isValid(candidate), !seen.contains(candidate) else { return false }
            seen.insert(candidate)
            return true
        }
    }
}

// MARK: - Le filet

/// Le plafond et le plancher : exactement le filet de `AppHeaderView` et de
/// `AppTabBar`, aux mêmes valeurs. C'est lui qui fait lire l'écran comme un
/// volume, et il n'a pas été inventé ici.
struct PlanEdge: View {
    var body: some View {
        Rectangle()
            .fill(AuthInk.rule)
            .frame(height: 1)
    }
}

private struct PlanComponentsPreview: View {
    @FocusState private var focus: String?
    @State private var email = "pierre@footbar.com"
    @State private var pseudo = ""

    var body: some View {
        ZStack {
            AuthInk.ground.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 32) {
                PlanField(
                    label: "Email", text: $email, field: "email", focus: $focus,
                    placeholder: "vous@exemple.com", keyboard: .emailAddress
                )
                PlanField(
                    label: "Pseudo", text: $pseudo, field: "pseudo", focus: $focus,
                    placeholder: "pierre.robert", prefix: "@",
                    accessory: .light,
                    note: "3 à 20 caractères, minuscules, chiffres, point et tiret bas."
                )
                PlanAlert(message: "Connexion au serveur impossible.", retry: {})
                PlanButton(title: "Entrer", loadingTitle: "Connexion…", isLoading: true) {}
                PlanSecondaryButton(title: "Continuer avec Google") {}
            }
            .padding(24)
        }
    }
}

#Preview("Composants") {
    PlanComponentsPreview()
}
