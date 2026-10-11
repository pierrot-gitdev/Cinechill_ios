//
//  ReportSheet.swift
//  Cinechill_iOS
//

import SwiftUI

// MARK: - Le sujet

/// La personne qu'on signale ou qu'on bloque, telle qu'on l'a sous les yeux.
///
/// Un profil public et une recommandation ne portent pas les mêmes champs ;
/// les deux écrans qui ouvrent ces actions (profil, notifications) passent
/// par ce type commun, pour qu'une seule feuille et une seule alerte servent
/// partout.
struct ReportSubject: Identifiable, Hashable {
    /// L'uid du profil.
    let id: String
    let name: String
    /// Sans `@`, et `nil` quand le profil n'a pas de pseudo : un « @ » seul se
    /// lisait comme une donnée cassée.
    let handle: String?
    let avatarURL: URL?
    let initial: String
    var context: ReportContext?

    var handleDisplay: String? { handle.map { "@\($0)" } }

    init(profile: PublicProfile) {
        id = profile.id
        name = profile.displayName
        handle = profile.handle.isEmpty ? nil : profile.handle
        avatarURL = profile.avatarURL
        initial = profile.initials
        context = nil
    }

    /// Depuis une recommandation : le film voyage avec le signalement, la
    /// personne qui le lira saura quoi ouvrir.
    init(suggestion: Suggestion) {
        id = suggestion.fromUid
        name = suggestion.fromDisplayName
        let raw = suggestion.fromHandle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        handle = raw.isEmpty ? nil : raw
        avatarURL = suggestion.fromAvatarURL
        initial = suggestion.senderInitial
        context = ReportContext(suggestionId: suggestion.id, itemId: suggestion.item.id)
    }
}

// MARK: - Les mots

extension ReportReason {
    /// Calculé à chaque lecture : une chaîne résolue une fois resterait dans
    /// la langue du premier affichage.
    var title: String {
        switch self {
        case .spam: String(localized: "Spam ou publicité", bundle: .app)
        case .offensive: String(localized: "Contenu choquant", bundle: .app)
        case .impersonation: String(localized: "Se fait passer pour quelqu'un", bundle: .app)
        case .other: String(localized: "Autre chose", bundle: .app)
        }
    }
}

/// Les phrases du blocage, dites pareil partout où on bloque.
enum HallBlockCopy {
    /// La conséquence, en une phrase : ce que l'autre perd, et ce qu'on perd
    /// soi-même. Une propriété calculée, jamais `static let` (voir CLAUDE.md).
    static var consequence: String {
        String(localized: "Ce profil ne pourra plus te suivre ni t'envoyer de films, et tu ne le suivras plus.", bundle: .app)
    }

    static func confirmTitle(_ name: String) -> String {
        String(localized: "Bloquer \(name) ?", bundle: .app)
    }
}

// MARK: - La confirmation

extension View {
    /// L'alerte qui précède un blocage. Le blocage défait des abonnements dans
    /// les deux sens et ne se rattrape pas d'un geste : c'est le seul endroit
    /// du Hall qui demande confirmation.
    func blockConfirmation(
        _ subject: Binding<ReportSubject?>,
        onConfirm: @escaping (ReportSubject) -> Void
    ) -> some View {
        modifier(BlockConfirmation(subject: subject, onConfirm: onConfirm))
    }
}

private struct BlockConfirmation: ViewModifier {
    @Binding var subject: ReportSubject?
    let onConfirm: (ReportSubject) -> Void

    func body(content: Content) -> some View {
        content.alert(
            subject.map { HallBlockCopy.confirmTitle($0.name) } ?? "",
            isPresented: Binding(
                get: { subject != nil },
                set: { if !$0 { subject = nil } }
            ),
            presenting: subject
        ) { shown in
            Button(String(localized: "Bloquer", bundle: .app), role: .destructive) {
                onConfirm(shown)
            }
            Button(String(localized: "Annuler", bundle: .app), role: .cancel) {}
        } message: { _ in
            Text(HallBlockCopy.consequence)
        }
    }
}

// MARK: - Le glyphe « plus »

/// Trois points, à la taille de la famille d'icônes. Pas de symbole système :
/// à côté des glyphes tracés de l'app, `ellipsis` se lisait plus gras.
struct HallMoreGlyph: View {
    var dot: CGFloat = 3.5

    var body: some View {
        HStack(spacing: dot) {
            ForEach(0..<3, id: \.self) { _ in
                Circle().frame(width: dot, height: dot)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - La feuille

/// Signaler un profil : une raison, un détail si on veut, et c'est parti.
///
/// Quatre raisons et pas davantage : au-delà, on hésite entre deux cases qui
/// disent presque la même chose, et la note libre couvre le reste. Après
/// l'envoi, la feuille ne se ferme pas d'elle-même : elle confirme, puis
/// propose de bloquer, parce qu'un profil qu'on signale est rarement un
/// profil qu'on veut continuer à croiser.
struct ReportSheet: View {
    let subject: ReportSubject

    @EnvironmentObject private var socialStore: SocialStore
    @Environment(\.dismiss) private var dismiss

    @State private var reason: ReportReason?
    @State private var note = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var isSent = false
    @State private var blockError: String?
    @FocusState private var noteFocused: Bool

    /// La limite du serveur, comptée comme lui : en unités UTF-16, celles de
    /// `String.length` en JavaScript. Un emoji en vaut deux.
    private static let noteLimit = 500

    private var isBlocked: Bool { socialStore.isBlocked(subject.id) }
    private var isBlocking: Bool { socialStore.blocksInFlight.contains(subject.id) }

    var body: some View {
        ZStack {
            Ink.ground.ignoresSafeArea()

            if isSent {
                sentState
                    .transition(.opacity)
            } else {
                form
                    .transition(.opacity)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            PlanHeader(String(localized: "Signaler", bundle: .app), leading: .close)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        // Une feuille tirée vers le bas pendant l'envoi laissait croire que
        // rien n'était parti.
        .interactiveDismissDisabled(isSending || isBlocking)
    }

    // MARK: - Le formulaire

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                subjectRow
                    .padding(.top, 18)
                    .padding(.bottom, 26)

                PlanSectionLabel(title: String(localized: "Ce qui ne va pas", bundle: .app))
                    .padding(.bottom, 8)

                VStack(spacing: 0) {
                    ForEach(ReportReason.allCases) { option in
                        reasonRow(option)
                        PlanEdge()
                    }
                }

                PlanSectionLabel(
                    title: String(localized: "Précisions", bundle: .app),
                    note: String(localized: "Facultatif : ce qui s'est passé, en quelques mots.", bundle: .app)
                )
                .padding(.top, 30)
                .padding(.bottom, 14)

                noteField
            }
            .padding(.horizontal, Metrics.margin)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) { sendBar }
    }

    private var subjectRow: some View {
        HStack(alignment: .top, spacing: 12) {
            HallAvatar(
                seed: subject.id,
                initial: subject.initial,
                url: subject.avatarURL,
                size: 38
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(subject.name)
                    .planFont(14.5, weight: .medium)
                    .foregroundStyle(Ink.ink)
                    .lineLimit(2)
                if let handle = subject.handleDisplay {
                    Text(verbatim: handle)
                        .planFont(11.5)
                        .foregroundStyle(Ink.ink2)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    /// Une case par raison, choix unique. La case retenue s'allume, comme
    /// dans le choix des destinataires d'une recommandation : ce qui est
    /// acquis prend la lumière.
    private func reasonRow(_ option: ReportReason) -> some View {
        let isOn = reason == option
        return Button {
            withAnimation(Metrics.shift) { reason = option }
        } label: {
            HStack(spacing: 12) {
                Text(option.title)
                    .planFont(14.5, weight: isOn ? .medium : .regular)
                    .foregroundStyle(Ink.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                    .strokeBorder(isOn ? Color.clear : Ink.ruleSet, lineWidth: 1)
                    .background(
                        RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                            .fill(isOn ? Ink.light : Color.clear)
                    )
                    .frame(width: 20, height: 20)
            }
            .frame(minHeight: Metrics.button)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isSending)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }

    /// Le champ de `PlanField` : un filet qui prend l'encre au focus, pas de
    /// boîte. Le compteur ne sert qu'à la fin ; il reste discret avant.
    private var noteField: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(
                "",
                text: $note,
                prompt: Text("Écris ici", bundle: .app).foregroundColor(Ink.ink3),
                axis: .vertical
            )
            .planFont(14.5)
            .foregroundStyle(Ink.ink)
            .tint(Ink.ink)
            .lineLimit(3...8)
            .focused($noteFocused)
            .disabled(isSending)
            .onChange(of: note) { _, value in
                if value.utf16.count > Self.noteLimit { note = Self.clamp(value) }
            }

            Rectangle()
                .fill(noteFocused ? Ink.ink : (note.isEmpty ? Ink.rule : Ink.ruleSet))
                .frame(height: 1)
                .animation(Metrics.shift, value: noteFocused)

            HStack {
                Spacer()
                Text(verbatim: "\(note.utf16.count) / \(Self.noteLimit)")
                    .planFont(11)
                    .monospacedDigit()
                    .foregroundStyle(note.utf16.count >= Self.noteLimit ? Ink.warn : Ink.ink2)
                    .accessibilityLabel(
                        String(localized: "\(note.utf16.count) sur \(Self.noteLimit) caractères", bundle: .app)
                    )
            }
        }
    }

    /// Le libellé dit ce qui manque tant qu'on ne peut pas envoyer.
    private var sendBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            PlanEdge()

            if let errorMessage {
                Text(errorMessage)
                    .planFont(12.5)
                    .foregroundStyle(Ink.warn)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Metrics.margin)
                    .padding(.top, 12)
                    .transition(.opacity)
            }

            PlanButton(
                title: reason == nil
                    ? String(localized: "Choisis une raison", bundle: .app)
                    : String(localized: "Envoyer", bundle: .app),
                loadingTitle: String(localized: "Envoi…", bundle: .app),
                isLoading: isSending,
                isEnabled: reason != nil,
                height: Metrics.control
            ) {
                Task { await send() }
            }
            .padding(.horizontal, Metrics.margin)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
        .background(Ink.ground)
    }

    // MARK: - La confirmation

    private var sentState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    PlanLight()
                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 4 }
                    Text("Signalement envoyé", bundle: .app)
                        .planTitle(22)
                        .foregroundStyle(Ink.ink)
                }
                .padding(.top, 28)

                Text("On lit chaque signalement. Ce profil ne saura pas que c'est toi.", bundle: .app)
                    .planFont(13.5)
                    .foregroundStyle(Ink.ink2)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)

                PlanEdge().padding(.top, 28)

                blockOffer
                    .padding(.top, 22)
            }
            .padding(.horizontal, Metrics.margin)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                PlanEdge()
                PlanButton(title: String(localized: "Fermer", bundle: .app), height: Metrics.control) {
                    dismiss()
                }
                .padding(.horizontal, Metrics.margin)
                .padding(.top, 12)
                .padding(.bottom, 8)
            }
            .background(Ink.ground)
        }
    }

    /// Bloquer après avoir signalé. La conséquence est écrite juste au-dessus
    /// du bouton : c'est elle qui tient lieu de confirmation ici, on vient de
    /// dire pourquoi ce profil pose problème.
    @ViewBuilder
    private var blockOffer: some View {
        if isBlocked {
            HStack(alignment: .firstTextBaseline, spacing: 11) {
                PlanLight()
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 3 }
                Text("Profil bloqué", bundle: .app)
                    .planFont(14.5, weight: .medium)
                    .foregroundStyle(Ink.ink)
            }
            .transition(.opacity)
        } else {
            VStack(alignment: .leading, spacing: 14) {
                PlanSectionLabel(
                    title: String(localized: "Bloquer aussi", bundle: .app),
                    note: HallBlockCopy.consequence
                )

                PlanSecondaryButton(
                    title: isBlocking
                        ? String(localized: "Blocage…", bundle: .app)
                        : String(localized: "Bloquer ce profil", bundle: .app),
                    isEnabled: !isBlocking,
                    height: Metrics.control
                ) {
                    Task { await block() }
                }

                if let blockError {
                    Text(blockError)
                        .planFont(12.5)
                        .foregroundStyle(Ink.warn)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .transition(.opacity)
        }
    }

    // MARK: - Actions

    private func send() async {
        guard let reason, !isSending else { return }
        noteFocused = false
        isSending = true
        defer { isSending = false }
        withAnimation(Metrics.shift) { errorMessage = nil }

        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await socialStore.report(
                uid: subject.id,
                reason: reason,
                note: trimmed.isEmpty ? nil : trimmed,
                context: subject.context
            )
        } catch is CancellationError {
            return
        } catch {
            Haptics.warning()
            withAnimation(Metrics.shift) { errorMessage = Self.message(for: error) }
            return
        }

        Haptics.success()
        withAnimation(Metrics.unfold) { isSent = true }
        AccessibilityNotification.Announcement(
            String(localized: "Signalement envoyé", bundle: .app)
        ).post()
    }

    private func block() async {
        blockError = nil
        do {
            try await socialStore.block(uid: subject.id)
        } catch is CancellationError {
            return
        } catch {
            Haptics.warning()
            withAnimation(Metrics.shift) { blockError = Self.message(for: error) }
        }
    }

    private static func message(for error: any Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    /// Coupe entre deux caractères affichés, jamais au milieu d'un emoji.
    private static func clamp(_ value: String) -> String {
        var kept = ""
        var units = 0
        for character in value {
            units += character.utf16.count
            guard units <= noteLimit else { break }
            kept.append(character)
        }
        return kept
    }
}
