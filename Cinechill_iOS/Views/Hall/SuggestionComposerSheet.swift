//
//  SuggestionComposerSheet.swift
//  Cinechill_iOS
//

import SwiftUI

/// Le choix du destinataire, une fois le film choisi.
///
/// La décision de conception qui structure cet écran : **l'action impossible
/// n'est jamais offerte**. Chaque ligne arrive du serveur avec son état pour
/// ce film — « a déjà vu », « déjà recommandé le 2 août » — la case est
/// désactivée et le compteur du bouton ne la compte pas. L'utilisateur ne se
/// heurte à rien parce qu'il n'y a rien à heurter ; il ne reste d'erreur que
/// pour la course réelle (le destinataire marque le film vu entre l'affichage
/// et l'envoi), traitée par l'appelant.
///
/// Feuille ancrée en bas : la liste et le bouton tombent tous deux sous le
/// pouce, contrairement à une modale plein écran.
struct SuggestionComposerSheet: View {
    let item: MediaItem
    /// Rapporte ce qui s'est réellement passé, pour le bandeau de l'appelant.
    let onSent: (SuggestionOutcome) -> Void

    @EnvironmentObject private var socialStore: SocialStore
    @Environment(\.dismiss) private var dismiss

    @State private var targets: [SuggestionTarget] = []
    @State private var selected: Set<String> = []
    @State private var filter = ""
    @State private var isLoading = true
    @State private var isSending = false
    @State private var loadError: String?

    private var filtered: [SuggestionTarget] {
        let needle = SocialStore.normalize(filter)
        guard !needle.isEmpty else { return targets }
        return targets.filter {
            SocialStore.normalize($0.displayName).contains(needle)
                || SocialStore.normalize($0.handle ?? "").contains(needle)
        }
    }

    private var selectableCount: Int {
        targets.filter(\.canReceive).count
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    loading
                } else if let loadError {
                    HallEmptyState(
                        icon: .hall,
                        title: "Liste indisponible",
                        message: loadError
                    )
                } else if targets.isEmpty {
                    HallEmptyState(
                        icon: .hall,
                        title: "Vous ne suivez personne",
                        message: "Suivez quelqu'un pour pouvoir lui recommander un film."
                    )
                } else {
                    content
                }
            }
            .background(Color(.systemBackground))
            .navigationTitle("Recommander")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !isLoading && !targets.isEmpty { sendBar }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task { await load() }
    }

    // MARK: - Contenu

    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                header

                if targets.count > 8 {
                    HallSearchField(placeholder: "Filtrer mes abonnements", text: $filter)
                        .padding(.horizontal, 18)
                        .padding(.bottom, 10)
                }

                ForEach(filtered) { target in
                    row(target)
                    Divider().padding(.leading, 64)
                }
            }
            .padding(.bottom, 12)
        }
    }

    private var header: some View {
        HStack(spacing: 11) {
            PosterTile(
                posterPath: item.posterPath,
                title: item.title,
                width: 44,
                cornerRadius: 6
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .lineLimit(2)
                Text("À qui l'envoyer ?")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.top, 6)
        .padding(.bottom, 14)
    }

    private func row(_ target: SuggestionTarget) -> some View {
        Button {
            guard target.canReceive else { return }
            Haptics.selection()
            if selected.contains(target.id) {
                selected.remove(target.id)
            } else {
                selected.insert(target.id)
            }
        } label: {
            HStack(spacing: 10) {
                HallAvatar(
                    seed: target.id,
                    initial: target.initial,
                    url: target.avatarURL,
                    size: 38
                )

                VStack(alignment: .leading, spacing: 1) {
                    Text(target.displayName)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(target.blockedReason ?? handleText(target))
                        .font(.system(size: 11.5))
                        .foregroundStyle(
                            target.alreadySeen ? Color.orange : Color.secondary
                        )
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                checkbox(target)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .opacity(target.canReceive ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .disabled(!target.canReceive)
        .accessibilityLabel(target.displayName)
        .accessibilityHint(target.blockedReason ?? "Sélectionner")
    }

    private func handleText(_ target: SuggestionTarget) -> String {
        guard let handle = target.handle else { return "" }
        return "@\(handle)"
    }

    @ViewBuilder
    private func checkbox(_ target: SuggestionTarget) -> some View {
        let isOn = selected.contains(target.id)
        ZStack {
            Circle()
                .strokeBorder(
                    isOn ? Color.clear : Color.secondary.opacity(target.canReceive ? 0.4 : 0.2),
                    lineWidth: 1.5
                )
                .background(
                    Circle().fill(isOn ? CinechillPalette.light : .clear)
                )
            if isOn {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(Color(hex: 0x04121A))
            }
        }
        .frame(width: 22, height: 22)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isOn)
    }

    // MARK: - Envoi

    /// Le libellé dit exactement ce qui va se passer, jamais « OK ».
    private var sendBar: some View {
        VStack(spacing: 0) {
            Divider()
            Button {
                Haptics.impact(.medium)
                Task { await send() }
            } label: {
                Group {
                    if isSending {
                        CinechillSpinner(size: 18, tint: .onAccent)
                    } else {
                        Text(sendTitle)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(
                    selected.isEmpty ? Color.secondary.opacity(0.28) : Color.indigo,
                    in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                )
            }
            .buttonStyle(PressableScaleStyle(scale: 0.98))
            .disabled(selected.isEmpty || isSending)
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .padding(.bottom, 6)
        }
        .background(.ultraThinMaterial)
    }

    private var sendTitle: String {
        switch selected.count {
        case 0 where selectableCount == 0: "Personne ne peut le recevoir"
        case 0: "Choisissez au moins une personne"
        case 1: "Recommander à 1 personne"
        default: "Recommander à \(selected.count) personnes"
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            targets = try await socialStore.suggestionTargets(itemId: item.id)
        } catch is CancellationError {
            return
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    /// Les envois partent en parallèle mais leurs échecs sont collectés un par
    /// un : si l'un des destinataires a vu le film entretemps, les autres
    /// doivent quand même recevoir la recommandation, et le bandeau doit
    /// pouvoir le dire précisément.
    private func send() async {
        guard !isSending else { return }
        isSending = true
        defer { isSending = false }

        let chosen = targets.filter { selected.contains($0.id) }
        var sent: [SuggestionTarget] = []
        var alreadySeen: [SuggestionTarget] = []
        var failed = false

        for target in chosen {
            do {
                try await socialStore.sendSuggestion(to: target.id, item: item)
                sent.append(target)
            } catch SocialError.targetAlreadySeen {
                alreadySeen.append(target)
            } catch {
                failed = true
            }
        }

        if !sent.isEmpty { Haptics.success() }
        onSent(SuggestionOutcome(
            film: item.title,
            sent: sent.map(\.displayName),
            alreadySeen: alreadySeen.map(\.displayName),
            hadFailure: failed
        ))
        dismiss()
    }

    private var loading: some View {
        VStack {
            Spacer()
            CinechillSpinner(size: 28)
            Spacer()
        }
    }
}

/// Ce qu'il s'est réellement passé à l'envoi, pour que le bandeau nomme les
/// personnes et le film plutôt que d'annoncer un succès générique.
struct SuggestionOutcome: Equatable {
    let film: String
    let sent: [String]
    let alreadySeen: [String]
    let hadFailure: Bool

    var isSilent: Bool {
        sent.isEmpty && alreadySeen.isEmpty && !hadFailure
    }

    var title: String {
        if !alreadySeen.isEmpty, sent.isEmpty {
            return "\(list(alreadySeen)) a déjà vu \(film)."
        }
        if hadFailure, sent.isEmpty {
            return "Rien n'a pu être envoyé."
        }
        return "Recommandé à \(list(sent))."
    }

    var message: String? {
        if !alreadySeen.isEmpty, sent.isEmpty {
            return "Rien ne lui a été envoyé."
        }
        if !alreadySeen.isEmpty {
            return "\(list(alreadySeen)) l'avait déjà vu — rien ne lui a été envoyé."
        }
        if hadFailure {
            return "Une partie des envois a échoué. Réessayez."
        }
        return sent.count == 1
            ? "Cette personne le verra dans ses notifications."
            : "Ils le verront dans leurs notifications."
    }

    private func list(_ names: [String]) -> String {
        switch names.count {
        case 0: return "Personne"
        case 1: return names[0]
        case 2: return "\(names[0]) et \(names[1])"
        default: return "\(names[0]) et \(names.count - 1) autres"
        }
    }
}
