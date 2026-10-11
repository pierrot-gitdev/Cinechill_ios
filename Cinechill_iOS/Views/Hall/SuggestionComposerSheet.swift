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
                        title: String(localized: "Liste indisponible", bundle: .app),
                        message: loadError,
                        actionTitle: String(localized: "Réessayer", bundle: .app),
                        action: { Task { await load() } }
                    )
                } else if targets.isEmpty {
                    HallEmptyState(
                        icon: .hall,
                        title: String(localized: "Tu ne suis personne", bundle: .app),
                        message: String(localized: "Suis quelqu'un pour pouvoir lui recommander un film.", bundle: .app)
                    )
                } else {
                    content
                }
            }
            .background(Ink.ground)
            .safeAreaInset(edge: .top) {
                PlanHeader(String(localized: "Recommander", bundle: .app), leading: .close)
            }
            .toolbar(.hidden, for: .navigationBar)
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
                    HallSearchField(placeholder: String(localized: "Filtrer mes abonnements", bundle: .app), text: $filter)
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
        HStack(spacing: 12) {
            PosterTile(posterPath: item.posterPath, title: item.title, width: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .planTitle(17)
                    .foregroundStyle(Ink.ink)
                    .lineLimit(2)
                Text("À qui l'envoyer ?", bundle: .app)
                    .planFont(12)
                    .foregroundStyle(Ink.ink2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Metrics.margin)
        .padding(.top, 16)
        .padding(.bottom, 18)
    }

    private func row(_ target: SuggestionTarget) -> some View {
        Button {
            guard target.canReceive else { return }
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

                VStack(alignment: .leading, spacing: 2) {
                    Text(target.displayName)
                        .planFont(14, weight: .medium)
                        .foregroundStyle(Ink.ink)
                        .lineLimit(1)

                    Text(target.blockedReason ?? handleText(target))
                        .planFont(11.5)
                        .foregroundStyle(target.alreadySeen ? Ink.warn : Ink.ink2)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                checkbox(target)
            }
            .padding(.horizontal, Metrics.margin)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .opacity(target.canReceive ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .disabled(!target.canReceive)
        .accessibilityLabel(target.displayName)
        .accessibilityAddTraits(selected.contains(target.id) ? .isSelected : [])
        .accessibilityHint(target.blockedReason ?? String(localized: "Sélectionner", bundle: .app))
    }

    private func handleText(_ target: SuggestionTarget) -> String {
        guard let handle = target.handle else { return "" }
        return "@\(handle)"
    }

    /// La case retenue est un aplat de lumière, pas une coche. C'est le même
    /// signe que partout ailleurs — plateforme retenue, film déjà vu, pseudo
    /// libre : *ce qui est acquis s'allume*.
    @ViewBuilder
    private func checkbox(_ target: SuggestionTarget) -> some View {
        let isOn = selected.contains(target.id)
        RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
            .strokeBorder(
                isOn ? Color.clear : Ink.ruleSet.opacity(target.canReceive ? 1 : 0.5),
                lineWidth: 1
            )
            .background(
                RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                    .fill(isOn ? Ink.light : Color.clear)
            )
            .frame(width: 20, height: 20)
            .animation(Metrics.shift, value: isOn)
    }

    // MARK: - Envoi

    /// Le libellé dit exactement ce qui va se passer, jamais « OK ».
    private var sendBar: some View {
        VStack(spacing: 0) {
            PlanEdge()

            PlanButton(
                title: sendTitle,
                loadingTitle: String(localized: "Envoi…", bundle: .app),
                isLoading: isSending,
                isEnabled: !selected.isEmpty,
                height: Metrics.control
            ) {
                Haptics.impact(.medium)
                Task { await send() }
            }
            .padding(.horizontal, Metrics.margin)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
        .background(Ink.ground)
    }

    private var sendTitle: String {
        switch selected.count {
        case 0 where selectableCount == 0: String(localized: "Personne ne peut le recevoir", bundle: .app)
        case 0: String(localized: "Choisis au moins une personne", bundle: .app)
        default: String(localized: "Recommander à \(selected.count) personnes", bundle: .app)
        }
    }

    private func load() async {
        isLoading = true
        loadError = nil
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
        var hitDailyLimit = false

        for target in chosen {
            do {
                try await socialStore.sendSuggestion(to: target.id, item: item)
                sent.append(target)
            } catch SocialError.targetAlreadySeen {
                alreadySeen.append(target)
            } catch SocialError.dailyLimit {
                // La limite vaut pour tous les destinataires suivants : inutile
                // d'insister, et le bandeau doit le dire au lieu d'un échec vague.
                hitDailyLimit = true
                break
            } catch {
                failed = true
            }
        }

        if !sent.isEmpty {
            Haptics.success()
            // Premier envoi : le bon moment pour proposer les notifications,
            // une fois cette feuille refermée.
            NotificationPermission.shared.offer(.firstSuggestion)
        }
        onSent(SuggestionOutcome(
            film: item.title,
            sent: sent.map(\.displayName),
            alreadySeen: alreadySeen.map(\.displayName),
            hadFailure: failed,
            hitDailyLimit: hitDailyLimit
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
    /// Le serveur a refusé un envoi pour la limite du jour. Sans ce cas, le
    /// bandeau disait « Rien n'a pu être envoyé » sans dire pourquoi.
    var hitDailyLimit: Bool = false

    var isSilent: Bool {
        sent.isEmpty && alreadySeen.isEmpty && !hadFailure && !hitDailyLimit
    }

    var title: String {
        if hitDailyLimit, sent.isEmpty {
            return String(localized: "Rien n'a pu être envoyé.", bundle: .app)
        }
        if !alreadySeen.isEmpty, sent.isEmpty {
            // L'accord suit le nombre : « Léa et Sofiane ont déjà vu… ».
            return alreadySeen.count == 1
                ? String(localized: "\(list(alreadySeen)) a déjà vu \(film).", bundle: .app)
                : String(localized: "\(list(alreadySeen)) ont déjà vu \(film).", bundle: .app)
        }
        if hadFailure, sent.isEmpty {
            return String(localized: "Rien n'a pu être envoyé.", bundle: .app)
        }
        return String(localized: "Recommandé à \(list(sent)).", bundle: .app)
    }

    var message: String? {
        if hitDailyLimit {
            return sent.isEmpty
                ? String(localized: "Tu as envoyé beaucoup de recommandations aujourd'hui. Réessaie demain.", bundle: .app)
                : String(localized: "Tu as atteint la limite du jour. Réessaie demain pour les autres.", bundle: .app)
        }
        if !alreadySeen.isEmpty, sent.isEmpty {
            return alreadySeen.count == 1
                ? String(localized: "Rien ne lui a été envoyé.", bundle: .app)
                : String(localized: "On ne leur a rien envoyé.", bundle: .app)
        }
        if !alreadySeen.isEmpty {
            return alreadySeen.count == 1
                ? String(localized: "\(list(alreadySeen)) l'avait déjà vu. Rien ne lui a été envoyé.", bundle: .app)
                : String(localized: "\(list(alreadySeen)) l'avaient déjà vu. On ne leur a rien envoyé.", bundle: .app)
        }
        if hadFailure {
            return String(localized: "Une partie des envois a échoué. Réessaie.", bundle: .app)
        }
        return sent.count == 1
            ? String(localized: "Cette personne le verra dans ses notifications.", bundle: .app)
            : String(localized: "Ils le verront dans leurs notifications.", bundle: .app)
    }

    private func list(_ names: [String]) -> String {
        switch names.count {
        case 0: return String(localized: "Personne", bundle: .app)
        case 1: return names[0]
        case 2: return String(localized: "\(names[0]) et \(names[1])", bundle: .app)
        default:
            let others = names.count - 1
            return others == 1
                ? String(localized: "\(names[0]) et \(others) autre", bundle: .app)
                : String(localized: "\(names[0]) et \(others) autres", bundle: .app)
        }
    }
}
