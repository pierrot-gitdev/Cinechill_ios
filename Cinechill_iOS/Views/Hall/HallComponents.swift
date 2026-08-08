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
                .font(.system(size: size * 0.42, weight: .heavy, design: .rounded))
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
                .overlay(Circle().strokeBorder(Color(.systemBackground), lineWidth: 1.5))
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
                    Text(isFollowing ? "Suivi" : "Suivre")
                        .font(.system(size: 12.5, weight: .bold, design: .rounded))
                }
            }
            .foregroundStyle(isFollowing ? Color.secondary : Color.white)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .padding(.horizontal, fullWidth ? 0 : 14)
            .padding(.vertical, fullWidth ? 11 : 7)
            .background {
                if isFollowing {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.35), lineWidth: 1)
                } else {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.indigo)
                }
            }
        }
        .buttonStyle(PressableScaleStyle(scale: 0.94))
        .disabled(isBusy)
        .accessibilityLabel(isFollowing ? "Se désabonner" : "Suivre")
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

            VStack(alignment: .leading, spacing: 1) {
                Text(profile.displayName)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
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
        return "\(profile.handleDisplay) · \(profile.galleryCount) vus"
    }
}

/// L'état vide type du Hall : une icône de la famille, ce qui manque, la
/// conséquence, et une sortie. Jamais un encouragement creux.
struct HallEmptyState: View {
    let icon: CinechillHallIcon
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            CinechillHallIconView(icon)
                .frame(width: 42, height: 42)
                .foregroundStyle(.tertiary)

            Text(title)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)

            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(.indigo)
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 30)
        .frame(maxWidth: .infinity)
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
        HStack(spacing: 10) {
            Image(systemName: isPartial
                ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .font(.system(size: 17))
                .foregroundStyle(isPartial ? Color.orange : CinechillPalette.light)

            VStack(alignment: .leading, spacing: 2) {
                Text(outcome.title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                if let message = outcome.message {
                    Text(message)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.22), radius: 14, y: 4)
        .padding(.horizontal, 18)
        .padding(.bottom, 22)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

/// Le champ de recherche du Hall — la loupe est la lentille-salle, pas le
/// symbole système.
struct HallSearchField: View {
    let placeholder: String
    @Binding var text: String
    var isBusy: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            CinechillHallIconView(.chercher)
                .frame(width: 15, height: 15)
                .foregroundStyle(.secondary)

            TextField(placeholder, text: $text)
                .font(.system(size: 14))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)

            if isBusy {
                CinechillSpinner(size: 14)
            } else if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Effacer la recherche")
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}
