//
//  AppHeaderView.swift
//  Cinechill_iOS
//

import SwiftUI

/// L'en-tête — direction « Le Seuil ».
///
/// Comme la barre du bas, elle n'a pas de conteneur : le mark, le titre de la vue et les actions
/// flottent sur le contenu, et un filet d'un point les sépare de lui. Un plafond en haut, un
/// plancher en bas, le contenu entre les deux — c'est le plan de salle appliqué à l'écran.
///
/// Le titre de la vue est la nouveauté fonctionnelle : l'ancienne barre affichait le mot-symbole
/// « Cinéchill » à l'identique sur les cinq écrans et ne disait donc jamais où l'on se trouvait.
/// Le nom de la marque est déjà sur l'icône de l'app et dans le splash ; ici, la place revient à
/// l'information utile.
struct AppHeaderView: View {
    /// Le nom de la vue courante. Il double le libellé de l'onglet actif, à dessein : dans
    /// « Le Seuil », ce libellé est écrit petit et disparaît dès qu'on change d'onglet.
    let title: String
    var onProfileTap: () -> Void

    @EnvironmentObject private var profileStore: UserProfileStore
    @EnvironmentObject private var socialStore: SocialStore
    @State private var showNotifications = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                // Le mark, réduit à ce qui tient à 26 points : le mur, le liseré, la cabine
                // allumée. La salle reste dans le noir — son détail ne survivrait pas.
                CinechillMark(
                    wallReveal: 1,
                    rimTrim: 1,
                    lightReach: 44,
                    seatsOpacity: 0,
                    boothGlow: 1
                )
                .frame(width: 26, height: 26)

                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer(minLength: 8)

                notificationButton
                profileButton
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 10)

            ceiling
        }
        // Sans conteneur, la lisibilité dépend de ce qui défile dessous. Le voile s'éteint
        // juste avant le filet : c'est lui, et non un bord de matériau, qui marque la limite.
        .background {
            LinearGradient(
                stops: [
                    .init(color: Color(.systemBackground), location: 0),
                    .init(color: Color(.systemBackground).opacity(0.94), location: 0.7),
                    .init(color: Color(.systemBackground).opacity(0), location: 1)
                ],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea(edges: .top)
        }
        .overlay(alignment: .topTrailing) {
            if showNotifications {
                ZStack(alignment: .topTrailing) {
                    Color.clear
                        .frame(width: 1000, height: 1000)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.easeOut(duration: 0.18)) { showNotifications = false }
                        }
                    notificationDropdown
                        .offset(x: -8, y: 56)
                }
                .zIndex(100)
            }
        }
    }

    /// Le plafond : exactement le même filet que le seuil de la barre du bas, aux mêmes
    /// valeurs. C'est cette égalité qui fait lire les deux comme les parois d'un même volume.
    private var ceiling: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: railTint, location: 0.12),
                .init(color: railTint, location: 0.88),
                .init(color: .clear, location: 1)
            ],
            startPoint: .leading, endPoint: .trailing
        )
        .frame(height: 1)
    }

    // MARK: - Notifications

    private var notificationButton: some View {
        Button {
            withAnimation(.easeOut(duration: 0.18)) { showNotifications.toggle() }
            if showNotifications { socialStore.acknowledgeFollowers() }
        } label: {
            Image("notification")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 19, height: 19)
                .foregroundStyle(showNotifications ? Color.primary : Color.secondary)
                .frame(width: 34, height: 34)
                .overlay(alignment: .topTrailing) { unreadDot }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            socialStore.unreadCount > 0
                ? "Notifications, \(socialStore.unreadCount) en attente"
                : "Notifications"
        )
    }

    /// L'indicateur de non-lu est le **point de lumière** de la famille
    /// d'icônes, dans le cyan de l'identité — pas une pastille rouge, qui
    /// serait le premier élément de l'app à ne rien devoir à sa marque.
    @ViewBuilder
    private var unreadDot: some View {
        if socialStore.unreadCount > 0, !showNotifications {
            Circle()
                .fill(CinechillPalette.light)
                .frame(width: 7, height: 7)
                .shadow(color: CinechillPalette.light.opacity(0.9), radius: 4)
                .overlay(
                    Circle().strokeBorder(Color(.systemBackground), lineWidth: 1.5)
                )
                .offset(x: -5, y: 5)
                .transition(.scale.combined(with: .opacity))
        }
    }

    // MARK: - Profil

    private var profileButton: some View {
        Button(action: onProfileTap) {
            avatarImage
                .frame(width: 27, height: 27)
                .clipShape(Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Profil")
    }

    @ViewBuilder
    private var avatarImage: some View {
        if let data = profileStore.avatarData, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage).resizable().scaledToFill()
        } else if let url = profileStore.avatarURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFill()
                default: avatarPlaceholder
                }
            }
        } else {
            avatarPlaceholder
        }
    }

    private var avatarPlaceholder: some View {
        Image(systemName: "person.fill")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.tertiarySystemFill))
    }

    // MARK: - Panneau de notifications

    private var notificationDropdown: some View {
        NotificationsPanel(
            onClose: {
                withAnimation(.easeOut(duration: 0.18)) { showNotifications = false }
            },
            onAccepted: { _ in
                // La confirmation vit dans le panneau lui-même, sur la ligne
                // qu'on vient de trancher : un second bandeau ferait doublon.
            }
        )
    }

    // MARK: - Palette

    // L'app est verrouillée en sombre (voir `Cinechill_iOSApp`) : l'identité étain/cyan n'est
    // dessinée que pour ce fond, donc une seule palette suffit ici.
    private let railTint = CinechillPalette.rimMid.opacity(0.20)
}

#Preview {
    VStack(spacing: 0) {
        AppHeaderView(title: "Accueil", onProfileTap: {})
        Spacer()
    }
    .background(
        LinearGradient(
            colors: [CinechillPalette.night, CinechillPalette.nightDeep],
            startPoint: .top, endPoint: .bottom
        )
        .ignoresSafeArea()
    )
    .environmentObject(UserProfileStore())
    .environmentObject(SocialStore())
}
