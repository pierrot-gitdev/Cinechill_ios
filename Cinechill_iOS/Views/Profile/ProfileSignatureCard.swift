import SwiftUI

/// La signature du profil — badge sélectionné, nom, pseudo, palier.
///
/// Elle est volontairement quasi monochrome : si la surface a sa propre identité
/// chromatique et le badge la sienne, les deux se battent. En la laissant sobre,
/// changer de badge change réellement l'allure du profil — ce qui est tout
/// l'intérêt de pouvoir en choisir un.
///
/// Elle n'a plus de cadre. La carte pleine à rayon 22, son halo radial et sa
/// bordure teintée disaient exactement ce que le badge disait déjà, et le
/// couvraient à moitié. Ce qui reste : le puits du badge, le nom, et la mesure
/// du palier réduite à un filet d'un point.
///
/// Le mode éditable a disparu avec elle : les réglages ont désormais leur propre
/// bloc d'identité, et cette carte n'existait en double que pour lui.
struct ProfileSignatureCard: View {
    @EnvironmentObject private var profileStore: UserProfileStore
    @EnvironmentObject private var libraryStore: LibraryStore
    @EnvironmentObject private var socialStore: SocialStore
    @Environment(BadgesViewModel.self) private var badgesModel

    /// Taille du puits où loge le badge.
    private static let wellSize: CGFloat = 84
    /// Le PNG exporté garde une marge transparente autour de la monture, pour
    /// laisser respirer son ombre portée. Ce zoom rogne cette marge en cercle
    /// pour que ce soit le badge lui-même qui remplisse le puits, pas sa marge.
    private static let badgeZoom: CGFloat = 1.55

    private var galleryCount: Int { libraryStore.galleryItems.count }
    private var tier: CinephileTier { .tier(for: galleryCount) }

    private var displayedBadge: Badge? {
        if let id = libraryStore.displayedBadgeID, let badge = BadgeCatalog.badge(id: id) {
            return badge
        }
        return badgesModel.showcase.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 16) {
                badgeWell

                VStack(alignment: .leading, spacing: 4) {
                    Text(profileStore.displayName)
                        .planTitle(22)
                        .foregroundStyle(Ink.ink)
                        .lineLimit(1)

                    // La seule preuve visible, sur tout l'écran, qu'un pseudo a
                    // été choisi : sans elle, « Choisir un pseudo » réussit sans
                    // que rien ne change à l'écran hormis deux compteurs à 0.
                    if let handle = socialStore.myProfile?.handleDisplay {
                        Text(handle)
                            .font(.system(size: 12.5))
                            .foregroundStyle(Ink.ink2)
                            .lineLimit(1)
                    }

                    if let badge = displayedBadge {
                        Text(badge.name)
                            .planLabel()
                            .foregroundStyle(badge.rarity.accent)
                            .lineLimit(1)
                            .padding(.top, 6)
                    }
                }

                Spacer(minLength: 0)
            }

            // La mesure du palier : un libellé, un filet, et ce qui reste à
            // parcourir. Le même dispositif que la progression d'un badge.
            HStack(spacing: 12) {
                Text("Palier \(tier.label.lowercased())")
                    .planLabel()
                    .foregroundStyle(Ink.ink3)
                    .fixedSize()

                PlanProgressRule(fraction: tier.progress(count: galleryCount))

                if let remaining = tier.remainingText(count: galleryCount) {
                    Text(remaining)
                        .planLabel()
                        .monospacedDigit()
                        .foregroundStyle(Ink.ink3)
                        .fixedSize()
                }
            }
            .padding(.top, 20)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(profileStore.displayName), palier \(tier.label), \(galleryCount) films"
        )
    }

    // MARK: - Le puits du badge

    /// Un creux, pas un objet : le badge y est posé, et rien autour de lui n'a
    /// de matière propre.
    private var badgeWell: some View {
        ZStack {
            Circle()
                .fill(Color(hex: 0x101720))
                .overlay(Circle().strokeBorder(Ink.rule, lineWidth: 1))

            if let badge = displayedBadge {
                Image(badge.imageName)
                    .resizable()
                    .scaledToFill()
                    .frame(
                        width: Self.wellSize * Self.badgeZoom,
                        height: Self.wellSize * Self.badgeZoom
                    )
            } else {
                CinechillHallIconView(.salle)
                    .frame(width: 26, height: 26)
                    .foregroundStyle(Ink.ink3)
            }
        }
        .frame(width: Self.wellSize, height: Self.wellSize)
        .clipShape(Circle())
    }
}
