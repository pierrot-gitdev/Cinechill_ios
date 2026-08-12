import SwiftUI

/// La signature du profil : l'écu de la distinction, le nom, le rang.
///
/// La pièce est centrée, seule entorse à la composition fer à gauche de
/// l'application. Un écu se regarde de face : le décentrer le ferait lire comme
/// une vignette posée à côté d'un nom, alors qu'il est le sujet de l'écran.
///
/// Elle reste quasi monochrome. Si la surface a sa propre identité chromatique
/// et le badge la sienne, les deux se battent ; en la laissant sobre, changer de
/// badge change réellement l'allure du profil, ce qui est tout l'intérêt de
/// pouvoir en choisir un. La seule couleur admise est celle de la distinction,
/// et elle ne touche que le trait de la couronne et le nom du rang.
///
/// Le mode éditable a disparu avec l'ancienne carte : les réglages ont désormais
/// leur propre bloc d'identité, et cette carte n'existait en double que pour lui.
struct ProfileSignatureCard: View {
    @EnvironmentObject private var profileStore: UserProfileStore
    @EnvironmentObject private var libraryStore: LibraryStore
    @EnvironmentObject private var socialStore: SocialStore
    @Environment(BadgesViewModel.self) private var badgesModel

    private var galleryCount: Int { libraryStore.galleryItems.count }
    private var distinction: Distinction { .distinction(for: galleryCount) }

    private var displayedBadge: Badge? {
        if let id = libraryStore.displayedBadgeID, let badge = BadgeCatalog.badge(id: id) {
            return badge
        }
        return badgesModel.showcase.first
    }

    var body: some View {
        VStack(spacing: 0) {
            // La taille vient de `DistinctionCrest` : la fixer ici aussi avait
            // laissé l'écu à 190 quand le rééquilibrage l'a porté à 200.
            DistinctionCrest(
                distinction: distinction,
                galleryCount: galleryCount,
                badge: displayedBadge
            )

            Text(profileStore.displayName)
                .planTitle(22)
                .foregroundStyle(Ink.ink)
                .lineLimit(1)

            // La seule preuve visible, sur tout l'écran, qu'un pseudo a été
            // choisi : sans elle, « Choisir un pseudo » réussit sans que rien ne
            // change à l'écran hormis deux compteurs à 0.
            if let handle = socialStore.myProfile?.handleDisplay {
                Text(handle)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Ink.ink2)
                    .lineLimit(1)
                    .padding(.top, 3)
            }

            Text(distinction.label)
                .planLabel()
                .foregroundStyle(distinction.accent)
                .padding(.top, 12)

            // Le prix du degré suivant, nommé et chiffré. Il n'est plus relégué
            // en note de bas de carte : c'est la seule ligne qui donne un
            // objectif, elle se lit au même rang que le reste.
            if let remaining = distinction.remainingText(count: galleryCount) {
                Text(remaining)
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(Ink.ink3)
                    .padding(.top, 5)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            String(localized: "\(profileStore.displayName), \(distinction.label), \(galleryCount) films", bundle: .app)
        )
    }
}
