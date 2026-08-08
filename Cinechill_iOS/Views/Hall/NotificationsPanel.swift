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
    @State private var settled: [String: String] = [:]
    @State private var busy: Set<String> = []

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
    }

    private var header: some View {
        HStack {
            Text("Notifications")
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
            .accessibilityLabel("Fermer")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 11) {
            CinechillHallIconView(.salle)
                .frame(width: 30, height: 30)
                .foregroundStyle(Ink.ink3)

            Text("Aucune notification")
                .font(.system(size: 13.5))
                .foregroundStyle(Ink.ink2)
            Text("Les films qu'on vous recommande arriveront ici.")
                .font(.system(size: 11.5))
                .foregroundStyle(Ink.ink3)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }

    private var rows: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(socialStore.suggestions) { suggestion in
                    suggestionRow(suggestion)
                    Divider()
                }
                ForEach(Array(settled.keys.sorted()), id: \.self) { key in
                    if let title = settled[key] {
                        settledRow(title)
                        Divider()
                    }
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
                            .font(.system(size: 13, weight: .semibold))
                        + Text(" vous recommande")
                            .font(.system(size: 13))
                    )
                    .lineLimit(2)

                    Text("\(suggestion.item.title) · \(suggestion.item.displayYear)")
                        .font(.system(size: 11.5))
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
                actionButton("Accepter", isProminent: true, fullWidth: true) {
                    Task { await respond(suggestion, accept: true) }
                }
                actionButton("Refuser", isProminent: false, fullWidth: true) {
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
    private func settledRow(_ title: String) -> some View {
        HStack(spacing: 9) {
            PlanLight()
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text("Ajouté à votre watchlist")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Ink.light)
                Text(title)
                    .font(.system(size: 11.5))
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
                        .font(.system(size: 13, weight: .semibold))
                    + Text(" vous suit")
                        .font(.system(size: 13))
                )
                .lineLimit(2)

                Spacer(minLength: 0)
            }

            // Même gabarit que la recommandation : l'action prend sa propre
            // ligne, sa largeur ne dépend donc pas de celle du nom.
            if !socialStore.isFollowing(profile.id) {
                actionButton("Suivre en retour", isProminent: false, fullWidth: true) {
                    Haptics.impact(.light)
                    Task { try? await socialStore.toggleFollow(uid: profile.id) }
                }
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
                .font(.system(size: 12.5, weight: isProminent ? .semibold : .regular))
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

    private func respond(_ suggestion: Suggestion, accept: Bool) async {
        guard !busy.contains(suggestion.id) else { return }
        busy.insert(suggestion.id)
        defer { busy.remove(suggestion.id) }

        Haptics.impact(accept ? .medium : .light)
        let alreadySeen = (try? await socialStore.respond(
            to: suggestion.id, accept: accept
        )) ?? false

        guard accept else { return }

        if alreadySeen {
            // Vu entretemps par un autre chemin : la recommandation n'a plus
            // d'objet, et rien n'entre en watchlist.
            withAnimation(.easeOut(duration: 0.2)) {
                settled[suggestion.id] = "\(suggestion.item.title) — vous l'aviez déjà vu"
            }
        } else {
            onAccepted(suggestion.item.title)
            withAnimation(.easeOut(duration: 0.2)) {
                settled[suggestion.id] = suggestion.item.title
            }
        }

        try? await Task.sleep(for: .milliseconds(1500))
        _ = withAnimation(.easeOut(duration: 0.25)) {
            settled.removeValue(forKey: suggestion.id)
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
