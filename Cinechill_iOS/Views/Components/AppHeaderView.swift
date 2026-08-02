import SwiftUI

struct AppHeaderView: View {
    @EnvironmentObject private var profileStore: UserProfileStore
    var onProfileTap: () -> Void
    @State private var showNotifications = false

    var body: some View {
        HStack(spacing: 12) {
            appLogo
            Spacer()
            notificationButton
            profileButton
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
                        .offset(x: -8, y: 62)
                }
                .zIndex(100)
            }
        }
    }

    // MARK: - App Logo

    private var appLogo: some View {
        HStack(spacing: 10) {
            Group {
                if let uiImage = Self.bundleAppIcon {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                } else {
                    ZStack {
                        LinearGradient(colors: [.indigo, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
                        Image(systemName: "popcorn.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .frame(width: 40, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )

            Text("Cinéchill")
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
        }
    }

    private static var bundleAppIcon: UIImage? {
        guard
            let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
            let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
            let files = primary["CFBundleIconFiles"] as? [String],
            let name = files.last
        else { return nil }
        return UIImage(named: name)
    }

    // MARK: - Notification

    private var notificationButton: some View {
        Button {
            withAnimation(.easeOut(duration: 0.18)) { showNotifications.toggle() }
        } label: {
            Image("notification")
                .resizable()
                .scaledToFit()
                .frame(width: 19, height: 19)
                .opacity(showNotifications ? 0.5 : 1)
                .padding(10)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
        }
        .buttonStyle(PressableScaleStyle(scale: 0.92))
    }

    // MARK: - Profile

    private var profileButton: some View {
        Button(action: onProfileTap) {
            avatarImage
                .frame(width: 38, height: 38)
                .clipShape(Circle())
                .overlay(
                    Circle().strokeBorder(
                        LinearGradient(colors: [.indigo, .pink], startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1.5
                    )
                )
        }
        .buttonStyle(PressableScaleStyle(scale: 0.92))
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
        Image(systemName: "person.circle.fill")
            .resizable()
            .foregroundStyle(Color(.systemGray3))
    }

    // MARK: - Notification Dropdown

    private var notificationDropdown: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Notifications")
                    .font(.headline)
                Spacer()
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { showNotifications = false }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            VStack(spacing: 12) {
                Image("notification")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 26, height: 26)
                    .foregroundStyle(Color(.systemGray3))
                    .padding(16)
                    .background(Color(.tertiarySystemFill), in: Circle())
                Text("Aucune notification")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        }
        .padding()
        .frame(width: 280)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 16, y: 4)
    }
}
