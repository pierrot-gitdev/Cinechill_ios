//
//  HallComponents.swift
//  Cinechill_iOS
//

import SwiftUI

/// Les destinations du Hall, atteintes depuis le profil.
///
/// Le social n'ajoute aucun onglet : « Le Seuil » tient cinq positions
/// calculées, et une sixième casserait autant le rythme de la barre que la
/// taille des cibles. Ces trois routes se greffent donc sur le profil, qui
/// existait déjà.
enum HallRoute: Hashable {
    case following
    case followers
    case search
}

/// L'avatar d'un utilisateur, à n'importe quelle taille.
///
/// Le repli n'est jamais une silhouette générique : c'est l'initiale sur un
/// aplat dérivé de l'identifiant. Deux profils sans photo restent ainsi
/// distinguables dans une liste, ce qu'une même icône grise rendrait
/// impossible.
struct HallAvatar: View {
    let seed: String
    let initial: String
    var url: URL?
    var size: CGFloat = 34

    var body: some View {
        Group {
            if url != nil {
                PosterImageView(url: url)
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
        .accessibilityHidden(true)
    }

    private var fallback: some View {
        ZStack {
            LinearGradient(
                colors: Self.palette(for: seed),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Text(initial)
                .font(.system(size: size * 0.40, weight: .semibold))
                .foregroundStyle(Color(hex: 0x06101A))
        }
    }

    /// Cinq duos repris de la palette de l'app — étain, or, améthyste, jade,
    /// acier. Le choix est déterministe : le même profil garde sa couleur
    /// d'un écran à l'autre.
    private static func palette(for seed: String) -> [Color] {
        let sets: [[Color]] = [
            [Color(hex: 0x9EEBFF), Color(hex: 0x5FA8D3)],
            [Color(hex: 0xE0B24A), Color(hex: 0xA97C52)],
            [Color(hex: 0xA98CE8), Color(hex: 0x6F5BC4)],
            [Color(hex: 0x5EE0C0), Color(hex: 0x2F9E86)],
            [Color(hex: 0xB8C2D0), Color(hex: 0x75808E)],
        ]
        let hash = seed.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFFFF }
        return sets[hash % sets.count]
    }
}

/// Plusieurs avatars superposés — utilisé quand un film a été recommandé par
/// plus d'une personne. Trois au maximum : au-delà, c'est le libellé qui
/// porte le compte.
struct HallAvatarStack: View {
    let recommenders: [Recommender]
    var size: CGFloat = 26

    private var shown: [Recommender] { Array(recommenders.prefix(3)) }

    var body: some View {
        HStack(spacing: -size * 0.34) {
            ForEach(Array(shown.enumerated()), id: \.offset) { index, person in
                HallAvatar(
                    seed: person.uid,
                    initial: person.initial,
                    url: person.avatarURL,
                    size: size
                )
                .overlay(Circle().strokeBorder(Ink.ground, lineWidth: 1.5))
                .zIndex(Double(shown.count - index))
            }
        }
    }
}

/// Le bouton de suivi, dans ses deux états.
///
/// « Suivi » se vide de sa couleur : l'action accomplie n'a pas à continuer
/// d'attirer l'œil. Aucune confirmation au désabonnement — c'est réversible
/// d'un tap, une alerte y ajouterait une cérémonie injustifiée.
struct HallFollowButton: View {
    let isFollowing: Bool
    var isBusy: Bool = false
    var fullWidth: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if isBusy {
                    CinechillSpinner(size: 13, tint: isFollowing ? .brand : .onAccent)
                } else {
                    Text(isFollowing ? String(localized: "Suivi", bundle: .app) : String(localized: "Suivre", bundle: .app))
                        .font(.system(size: 12.5, weight: isFollowing ? .regular : .semibold))
                }
            }
            .foregroundStyle(isFollowing ? Ink.ink2 : Ink.ground)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .padding(.horizontal, fullWidth ? 0 : 14)
            .padding(.vertical, fullWidth ? 13 : 7)
            .background {
                if isFollowing {
                    RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                        .strokeBorder(Ink.ruleSet, lineWidth: 1)
                } else {
                    RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                        .fill(Ink.ink)
                }
            }
        }
        .buttonStyle(PressableScaleStyle(scale: 0.94))
        .disabled(isBusy)
        .accessibilityLabel(isFollowing ? String(localized: "Se désabonner", bundle: .app) : String(localized: "Suivre", bundle: .app))
    }
}

/// Une ligne de profil : avatar, nom, pseudo, et l'action de suivi.
/// Le nombre de films vus départage deux homonymes mieux qu'un identifiant.
struct HallProfileRow: View {
    let profile: PublicProfile
    var showsGalleryCount: Bool = true
    var isFollowing: Bool
    var isBusy: Bool = false
    let onToggleFollow: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            HallAvatar(
                seed: profile.id,
                initial: profile.initials,
                url: profile.avatarURL,
                size: 38
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(profile.displayName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Ink.ink)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Ink.ink2)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            HallFollowButton(isFollowing: isFollowing, isBusy: isBusy, action: onToggleFollow)
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        guard showsGalleryCount, profile.galleryCount > 0 else {
            return profile.handleDisplay
        }
        return String(localized: "\(profile.handleDisplay) · \(profile.galleryCount) vus", bundle: .app)
    }
}

/// L'état vide du Hall.
///
/// Il ne dessine plus rien : les six états vides de l'application — galerie,
/// watchlist, deck (deux cas), hall, genre — avaient chacun leur mise en page et
/// tous s'appuyaient sur `.borderedProminent` teinté d'indigo. `PlanEmptyState`
/// est désormais le seul, et ce nom reste comme point d'entrée du Hall pour ne
/// pas réécrire ses appels.
struct HallEmptyState: View {
    let icon: CinechillHallIcon
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        PlanEmptyState(
            icon: icon,
            title: title,
            message: message,
            actionTitle: actionTitle,
            action: action
        )
        .padding(.horizontal, Metrics.margin)
    }
}

/// Le bandeau de confirmation d'un envoi.
///
/// Trois secondes, pas un écran de succès : on revient d'où l'on venait. Il
/// nomme les personnes et le film — « Recommandé à Léa et Sofiane », jamais
/// « Envoyé ! ». Quand un destinataire avait vu le film entretemps, il le dit
/// aussi précisément, sans faire disparaître les envois réussis.
struct SuggestionOutcomeBanner: View {
    let outcome: SuggestionOutcome

    private var isPartial: Bool { !outcome.alreadySeen.isEmpty }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Le point de lumière quand tout est parti, l'écart quand une partie
            // n'a pas pu l'être. Deux signes déjà connus, pas deux pictogrammes.
            Group {
                if isPartial {
                    PlanLight(tint: Ink.warn)
                } else {
                    PlanLight()
                }
            }
            .padding(.top, 6)

            VStack(alignment: .leading, spacing: 3) {
                Text(outcome.title)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(Ink.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let message = outcome.message {
                    Text(message)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Ink.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Ink.ground)
        .overlay(alignment: .top) { PlanEdge(tint: isPartial ? Ink.warn : Ink.ruleSet) }
        .overlay(alignment: .bottom) { PlanEdge() }
        .padding(.bottom, 18)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

/// Le champ de recherche du Hall — la loupe est la lentille-salle, pas le
/// symbole système.
struct HallSearchField: View {
    let placeholder: String
    @Binding var text: String
    var isBusy: Bool = false

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                CinechillHallIconView(.chercher)
                    .frame(width: 16, height: 16)
                    .foregroundStyle(isFocused ? Ink.ink : Ink.ink2)

                TextField("", text: $text, prompt: Text(placeholder).foregroundColor(Ink.ink3))
                    .font(.system(size: 15))
                    .foregroundStyle(Ink.ink)
                    .tint(Ink.ink)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($isFocused)

                if isBusy {
                    CinechillSpinner(size: 14)
                } else if !text.isEmpty {
                    Button {
                        text = ""
                    } label: {
                        // La croix de la famille, pas le bouton plein du système.
                        PlanClearGlyph()
                            .stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                            .foregroundStyle(Ink.ink3)
                            .frame(width: 14, height: 14)
                            .contentShape(Rectangle().inset(by: -10))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "Effacer la recherche", bundle: .app))
                }
            }
            .frame(height: Metrics.field)

            // L'état ne s'exprime que par la valeur du filet — comme dans
            // `PlanField`. Pas de fond qui s'allume, pas de bordure qui apparaît.
            Rectangle()
                .fill(isFocused ? Ink.ink : (text.isEmpty ? Ink.rule : Ink.ruleSet))
                .frame(height: 1)
        }
        .animation(Metrics.shift, value: isFocused)
    }
}

/// La croix d'effacement, dans l'écriture de la famille.
private struct PlanClearGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        return path
    }
}
