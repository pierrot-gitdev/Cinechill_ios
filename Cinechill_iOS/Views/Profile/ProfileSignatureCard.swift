import SwiftUI
import PhotosUI

/// La carte de signature du profil — badge sélectionné, nom, palier.
///
/// Un seul composant pour les deux endroits où l'identité du profil doit
/// apparaître : le profil lui-même (lecture seule) et les réglages, où
/// l'avatar et le nom deviennent éditables sur place plutôt que de dupliquer
/// la mise en page dans une seconde carte.
struct ProfileSignatureCard: View {
    var isEditable = false
    var nameField: Binding<String> = .constant("")
    var photoItem: Binding<PhotosPickerItem?> = .constant(nil)
    var onNameFocusChange: ((Bool) -> Void)? = nil

    @EnvironmentObject private var profileStore: UserProfileStore
    @EnvironmentObject private var libraryStore: LibraryStore
    @Environment(BadgesViewModel.self) private var badgesModel
    @FocusState private var isNameFocused: Bool

    /// Taille du puits où loge le badge — réduite pour resserrer la carte, le
    /// badge étant désormais zoomé pour l'occuper en entier.
    private static let wellSize: CGFloat = 80
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
        HStack(spacing: 15) {
            badgeWell

            VStack(alignment: .leading, spacing: 3) {
                nameLabel

                Text(displayedBadge?.name.uppercased() ?? "AUCUN BADGE CHOISI")
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .kerning(0.6)
                    .foregroundStyle(tier.accent)
                    .lineLimit(1)

                Text("PALIER \(tier.label) · \(galleryCount) FILMS")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .kerning(0.8)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.1))
                        Capsule()
                            .fill(tier.accent)
                            .frame(width: max(4, proxy.size.width * tier.progress(count: galleryCount)))
                    }
                }
                .frame(height: 4)
                .padding(.top, 2)

                if let remaining = tier.remainingText(count: galleryCount) {
                    Text(remaining)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(.secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(
                            RadialGradient(
                                colors: [tier.accent.opacity(0.16), .clear],
                                center: UnitPoint(x: 0.12, y: 0),
                                startRadius: 4, endRadius: 220
                            )
                        )
                )
        }
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(tier.accent.opacity(0.35), lineWidth: 1)
        )
        .overlay(alignment: .topTrailing) { avatarBubble.padding(12) }
    }

    @ViewBuilder
    private var nameLabel: some View {
        if isEditable {
            TextField("Nom d'affichage", text: nameField)
                .font(.system(size: 21, weight: .heavy, design: .rounded))
                .focused($isNameFocused)
                .onChange(of: isNameFocused) { _, now in onNameFocusChange?(now) }
        } else {
            Text(profileStore.displayName)
                .font(.system(size: 21, weight: .heavy, design: .rounded))
                .lineLimit(1)
        }
    }

    // MARK: - Le puits du badge

    private var badgeWell: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.white.opacity(0.07), .black.opacity(0.45)],
                        center: .center, startRadius: 4, endRadius: 42
                    )
                )

            if let badge = displayedBadge {
                Image(badge.imageName)
                    .resizable()
                    .scaledToFill()
                    .frame(
                        width: Self.wellSize * Self.badgeZoom,
                        height: Self.wellSize * Self.badgeZoom
                    )
            } else {
                Image(systemName: "rosette")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: Self.wellSize, height: Self.wellSize)
        .clipShape(Circle())
    }

    // MARK: - Avatar

    @ViewBuilder
    private var avatarBubble: some View {
        if isEditable {
            PhotosPicker(selection: photoItem, matching: .images) {
                avatarContent
            }
            .buttonStyle(PressableScaleStyle(scale: 0.9))
        } else {
            avatarContent
        }
    }

    private var avatarContent: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let data = profileStore.avatarData, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage).resizable().scaledToFill()
                } else if let url = profileStore.avatarURL {
                    PosterImageView(url: url)
                } else {
                    Image(systemName: "person.circle.fill")
                        .resizable()
                        .foregroundStyle(Color(.systemGray3))
                }
            }
            .frame(width: 30, height: 30)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Color.primary.opacity(0.14), lineWidth: 1.5))

            if isEditable {
                Image(systemName: "camera.fill")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(3.5)
                    .background(
                        Circle().fill(
                            LinearGradient(colors: [.indigo, .pink], startPoint: .top, endPoint: .bottom)
                        )
                    )
                    .overlay(Circle().strokeBorder(Color(.secondarySystemBackground), lineWidth: 1.5))
                    .offset(x: 3, y: 3)
            }
        }
    }
}
