//
//  NotificationsPanel.swift
//  Cinechill_iOS
//

import SwiftUI

/// Le contenu du centre de notifications.
///
/// Le panneau existait déjà dans `AppHeaderView`, avec son état vide écrit en
/// dur : c'était le seul écran de l'app dessiné pour un contenu qui n'existait
/// pas encore. On ne crée donc rien ici — on le remplit.
///
/// Deux types de ligne, un seul gabarit : une recommandation et un nouvel
/// abonné ont la même hauteur et la même grille, seules les actions changent.
/// C'est ce qui permettra d'en ajouter d'autres sans redessiner le panneau.
struct NotificationsPanel: View {
    let onClose: () -> Void
    /// Remonte le film accepté, pour que l'appelant puisse confirmer.
    let onAccepted: (String) -> Void

    @EnvironmentObject private var socialStore: SocialStore

    /// Les lignes qui viennent d'être tranchées restent visibles un instant,
    /// le temps de confirmer sur place. Une ligne qui s'évapore sous le doigt
    /// ne laisse aucun moyen de vérifier ce qu'on a fait.
    @State private var settled: [String: Settled] = [:]
    /// La recommandation tranchée, gardée à sa place le temps de la
    /// confirmation : le magasin la retire tout de suite, et la confirmation
    /// tombait sinon après toutes les autres, hors de la zone visible.
    @State private var held: [String: Suggestion] = [:]
    @State private var busy: Set<String> = []

    private enum Settled: Equatable {
        case added(String)
        case alreadySeen(String)
    }

    private var displayedSuggestions: [Suggestion] {
        let live = socialStore.suggestions
        let kept = held.values.filter { h in !live.contains { $0.id == h.id } }
        return (live + kept).sorted { ($0.createdAt, $0.id) > ($1.createdAt, $1.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if socialStore.suggestions.isEmpty
                && socialStore.recentFollowers.isEmpty
                && settled.isEmpty {
                emptyState
            } else {
                rows
            }
        }
        .padding(13)
        .frame(width: 320)
        .background(
            Ink.ground,
            in: RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                .strokeBorder(Ink.ruleSet, lineWidth: 1)
        )
        // Modal pour VoiceOver, et fermé par le geste d'échappement.
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { onClose() }
    }

    private var header: some View {
        HStack {
            Text("Notifications", bundle: .app)
                .planTitle(17)
                .foregroundStyle(Ink.ink)
            Spacer()
            Button(action: onClose) {
                NotificationsCloseGlyph()
                    .stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .foregroundStyle(Ink.ink3)
                    .frame(width: 12, height: 12)
                    .contentShape(Rectangle().inset(by: -10))
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle().inset(by: -16))
            .accessibilityLabel(String(localized: "Fermer", bundle: .app))
        }
    }

    private var emptyState: some View {
        VStack(spacing: 11) {
            CinechillHallIconView(.salle)
                .frame(width: 30, height: 30)
                .foregroundStyle(Ink.ink3)

            Text("Aucune notification", bundle: .app)
                .planFont(13.5)
                .foregroundStyle(Ink.ink2)
            Text("Les films qu'on te recommande arriveront ici.", bundle: .app)
                .planFont(11.5)
                .foregroundStyle(Ink.ink2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }

    private var rows: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(displayedSuggestions) { suggestion in
                    if let state = settled[suggestion.id] {
                        settledRow(state)
                    } else {
                        suggestionRow(suggestion)
                    }
                    Divider()
                }
                ForEach(socialStore.recentFollowers) { follower in
                    followerRow(follower)
                    Divider()
                }
            }
        }
        .frame(maxHeight: 340)
    }

    // MARK: - Recommandation

    /// Les deux actions occupent leur propre ligne, en pleine largeur.
    ///
    /// Coincées dans la colonne de texte — entre l'avatar et l'affiche — elles
    /// se partageaient la place résiduelle, et « Refuser » disparaissait dès
    /// qu'un titre de film était long ou que le corps de texte grossissait.
    /// Ici leur largeur ne dépend plus de rien, et les cibles passent de ~70
    /// à ~140 points.
    private func suggestionRow(_ suggestion: Suggestion) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 9) {
                HallAvatar(
                    seed: suggestion.fromUid,
                    initial: suggestion.senderInitial,
                    url: suggestion.fromAvatarURL,
                    size: 30
                )

                VStack(alignment: .leading, spacing: 3) {
                    (
                        Text(suggestion.fromDisplayName)
                            .fontWeight(.semibold)
                        + Text(" te recommande", bundle: .app)
                    )
                    .planFont(13)
                    .lineLimit(2)

                    Text(verbatim: "\(suggestion.item.title) · \(suggestion.item.displayYear)")
                        .planFont(11.5)
                        .foregroundStyle(Ink.ink2)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                PosterTile(
                    posterPath: suggestion.item.posterPath,
                    title: suggestion.item.title,
                    width: 30,
                    cornerRadius: Metrics.radius
                )
            }

            HStack(spacing: 8) {
                actionButton(String(localized: "Accepter", bundle: .app), isProminent: true, fullWidth: true) {
                    Task { await respond(suggestion, accept: true) }
                }
                actionButton(String(localized: "Refuser", bundle: .app), isProminent: false, fullWidth: true) {
                    Task { await respond(suggestion, accept: false) }
                }
            }
            .opacity(busy.contains(suggestion.id) ? 0.4 : 1)
            .disabled(busy.contains(suggestion.id))
        }
        .padding(.vertical, 10)
    }

    /// La confirmation sur place, avant effacement — l'action reste
    /// vérifiable une seconde et demie.
    private func settledRow(_ state: Settled) -> some View {
        let title: String
        let isAdded: Bool
        switch state {
        case .added(let value): title = value; isAdded = true
        case .alreadySeen(let value): title = value; isAdded = false
        }
        return HStack(spacing: 9) {
            Group {
                if isAdded { PlanLight() } else { PlanLightOutline(tint: Ink.ink3) }
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                // L'en-tête dit ce qui s'est vraiment passé : « Ajouté » sur un
                // film déjà vu affirmait le contraire de la ligne d'en dessous.
                Group {
                    if isAdded {
                        Text("Ajouté à ta watchlist", bundle: .app)
                    } else {
                        Text("Tu l'avais déjà vu", bundle: .app)
                    }
                }
                .planFont(13, weight: .medium)
                .foregroundStyle(isAdded ? Ink.light : Ink.ink2)
                Text(title)
                    .planFont(11.5)
                    .foregroundStyle(Ink.ink2)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .transition(.opacity)
    }

    // MARK: - Nouvel abonné

    private func followerRow(_ profile: PublicProfile) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 9) {
                HallAvatar(
                    seed: profile.id,
                    initial: profile.initials,
                    url: profile.avatarURL,
                    size: 30
                )

                (
                    Text(profile.displayName)
                        .fontWeight(.semibold)
                    + Text(" te suit", bundle: .app)
                )
                .planFont(13)
                .lineLimit(2)

                Spacer(minLength: 0)
            }

            // Même gabarit que la recommandation : l'action prend sa propre
            // ligne, sa largeur ne dépend donc pas de celle du nom.
            if !socialStore.isFollowing(profile.id) {
                actionButton(String(localized: "Suivre en retour", bundle: .app), isProminent: false, fullWidth: true) {
                    Haptics.impact(.light)
                    Task { await followBack(profile) }
                }
                // L'attente se voit : le suivi n'est plus optimiste.
                .opacity(busy.contains(profile.id) ? 0.5 : 1)
                .disabled(busy.contains(profile.id))
            }
        }
        .padding(.vertical, 10)
    }

    private func actionButton(
        _ title: String,
        isProminent: Bool,
        fullWidth: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .planFont(12.5, weight: isProminent ? .semibold : .regular)
                // Le libellé ne se replie jamais : mieux vaut le réduire un
                // peu que le voir passer sur deux lignes ou se faire couper.
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .foregroundStyle(isProminent ? Ink.ground : Ink.ink2)
                .frame(maxWidth: fullWidth ? .infinity : nil)
                .padding(.horizontal, fullWidth ? 6 : 12)
                .padding(.vertical, 9)
                .background {
                    if isProminent {
                        RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                            .fill(Ink.ink)
                    } else {
                        RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                            .strokeBorder(Ink.ruleSet, lineWidth: 1)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous))
        }
        .buttonStyle(PressableScaleStyle(scale: 0.94))
    }

    // MARK: - Actions

    private func followBack(_ profile: PublicProfile) async {
        guard !busy.contains(profile.id) else { return }
        busy.insert(profile.id)
        defer { busy.remove(profile.id) }
        do {
            try await socialStore.toggleFollow(uid: profile.id)
        } catch {
            Haptics.warning()
        }
    }

    private func respond(_ suggestion: Suggestion, accept: Bool) async {
        guard !busy.contains(suggestion.id) else { return }
        busy.insert(suggestion.id)
        defer { busy.remove(suggestion.id) }

        Haptics.impact(accept ? .medium : .light)
        held[suggestion.id] = suggestion
        let alreadySeen: Bool
        do {
            alreadySeen = try await socialStore.respond(to: suggestion.id, accept: accept)
        } catch {
            // Rien n'a été fait : pas de confirmation. Le magasin a remis la
            // ligne, elle reste à trancher.
            held[suggestion.id] = nil
            Haptics.warning()
            return
        }

        guard accept else {
            _ = withAnimation(.easeOut(duration: 0.2)) { held.removeValue(forKey: suggestion.id) }
            return
        }

        // Vu entretemps par un autre chemin : rien n'entre en watchlist.
        if !alreadySeen { onAccepted(suggestion.item.title) }
        withAnimation(.easeOut(duration: 0.2)) {
            settled[suggestion.id] = alreadySeen
                ? .alreadySeen(suggestion.item.title)
                : .added(suggestion.item.title)
        }

        try? await Task.sleep(for: .milliseconds(1500))
        withAnimation(.easeOut(duration: 0.2)) {
            settled[suggestion.id] = nil
            held[suggestion.id] = nil
        }
    }
}

/// La croix de fermeture, dans l'écriture de la famille.
private struct NotificationsCloseGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        return path
    }
}
