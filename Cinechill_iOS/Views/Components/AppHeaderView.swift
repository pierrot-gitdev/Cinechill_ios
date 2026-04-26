import SwiftUI

struct AppHeaderView: View {
    @EnvironmentObject private var profileStore: UserProfileStore
    var onProfileTap: () -> Void
    @State private var showNotifications = false

    var body: some View {
        HStack(spacing: 16) {
            appIcon
            Spacer()
            bellButton
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
                        .offset(x: -8, y: 48)
                }
                .zIndex(100)
            }
        }
    }

    // MARK: - App Icon

    private var appIcon: some View {
        Group {
            if let uiImage = Self.bundleAppIcon {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "film.stack")
                    .font(.title2)
                    .foregroundStyle(.primary)
            }
        }
        .frame(width: 34, height: 34)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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

    // MARK: - Bell

    private var bellButton: some View {
        Button {
            withAnimation(.easeOut(duration: 0.18)) { showNotifications.toggle() }
        } label: {
            Image(systemName: showNotifications ? "bell.fill" : "bell")
                .font(.title3)
                .foregroundStyle(.primary)
        }
    }

    // MARK: - Profile

    private var profileButton: some View {
        Button(action: onProfileTap) {
            avatarImage
                .frame(width: 34, height: 34)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Color(.systemGray4), lineWidth: 1))
        }
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

            VStack(spacing: 10) {
                Image(systemName: "bell.slash")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
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
