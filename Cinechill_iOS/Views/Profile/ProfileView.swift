import SwiftUI

/// Le profil, construit autour du badge sélectionné.
///
/// La carte est volontairement quasi monochrome : si elle a sa propre identité
/// chromatique et le badge la sienne, les deux se battent. En la laissant
/// sobre, changer de badge change réellement l'allure du profil — ce qui est
/// tout l'intérêt de pouvoir en choisir un.
struct ProfileView: View {
    @Bindable var badgesModel: BadgesViewModel

    @EnvironmentObject private var profileStore: UserProfileStore
    @EnvironmentObject private var libraryStore: LibraryStore
    @EnvironmentObject private var authService: AuthService
    @Environment(MediaCatalog.self) private var catalog
    @Environment(\.dismiss) private var dismiss

    @State private var showSettings = false

    private var galleryCount: Int { libraryStore.galleryItems.count }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    Color.clear.frame(height: 44)

                    signatureCard
                    quickStats
                    badgesSection
                    dnaSection
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 36)
            }
            .background(Color(.systemBackground))
            .navigationBarHidden(true)
            .overlay(alignment: .top) { topBar }
            .navigationDestination(for: MediaItem.self) { item in
                ItemDetailView(item: item)
            }
        }
        .sheet(isPresented: $showSettings, onDismiss: { profileStore.refresh() }) {
            SettingsView()
                .environmentObject(profileStore)
                .environmentObject(authService)
                .environmentObject(libraryStore)
        }
        .task {
            profileStore.refresh()
            await catalog.loadIfNeeded()
            await badgesModel.refresh()
        }
    }

    // MARK: - Barre

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 34, height: 34)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(PressableScaleStyle(scale: 0.92))

            Spacer()

            Text("Profil")
                .font(.system(size: 15, weight: .bold, design: .rounded))

            Spacer()

            Button { showSettings = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 34, height: 34)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(PressableScaleStyle(scale: 0.92))
        }
        .padding(.horizontal, 18)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .background(.ultraThinMaterial)
    }

    // MARK: - La carte

    private var signatureCard: some View {
        ProfileSignatureCard()
    }

    // MARK: - Chiffres

    private var quickStats: some View {
        HStack(spacing: 8) {
            statCell(value: badgesModel.unlockedCount, label: "BADGES")
            statCell(value: galleryCount, label: "VUS")
            statCell(value: libraryStore.watchlistItems.count, label: "À VOIR")
        }
    }

    private func statCell(value: Int, label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.system(size: 19, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(label)
                .font(.system(size: 8.5, weight: .bold, design: .rounded))
                .kerning(0.5)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 11)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    // MARK: - Badges

    private var badgesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Mes badges")
                    .font(.system(size: 19, weight: .heavy, design: .rounded))
                Spacer()
                NavigationLink(destination: BadgeGalleryView(model: badgesModel)) {
                    Text("Tout voir →")
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        .foregroundStyle(.indigo)
                }
            }

            if badgesModel.showcase.isEmpty {
                emptyBadges
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(badgesModel.showcase) { badge in
                            BadgeView(badge: badge, isUnlocked: true, size: 62)
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.vertical, 6)
                }
                .scrollClipDisabled()
            }
        }
    }

    private var emptyBadges: some View {
        NavigationLink(destination: BadgeGalleryView(model: badgesModel)) {
            HStack(spacing: 12) {
                if let first = BadgeCatalog.all.first {
                    BadgeView(badge: first, isUnlocked: false, size: 52)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Quinze badges à décrocher")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text("Le premier tombe dès votre premier film.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(13)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(PressableScaleStyle(scale: 0.98))
    }

    // MARK: - ADN

    @ViewBuilder
    private var dnaSection: some View {
        let shares = genreShares
        if !shares.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Votre ADN cinéphile")
                    .font(.system(size: 19, weight: .heavy, design: .rounded))

                GeometryReader { proxy in
                    HStack(spacing: 1.5) {
                        ForEach(shares) { share in
                            Capsule()
                                .fill(share.color)
                                .frame(width: max(2, proxy.size.width * share.share - 1.5))
                        }
                    }
                }
                .frame(height: 9)

                FlowLayout(spacing: 12) {
                    ForEach(shares.prefix(4)) { share in
                        HStack(spacing: 5) {
                            Circle().fill(share.color).frame(width: 6, height: 6)
                            Text(share.name).foregroundStyle(.secondary)
                            Text(share.percentText).foregroundStyle(.primary)
                        }
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    }
                }
            }
        }
    }

    /// Réutilise la même barre proportionnelle que la galerie plutôt que
    /// d'inventer un second langage visuel pour la même information.
    private var genreShares: [GenreShare] {
        var counts: [Int: Int] = [:]
        for entry in libraryStore.galleryItems {
            guard let genreID = entry.genreIds.first(where: { catalog.genreNames[$0] != nil })
                ?? entry.genreIds.first else { continue }
            counts[genreID, default: 0] += 1
        }
        let total = Double(counts.values.reduce(0, +))
        guard total > 0 else { return [] }

        let ranked = counts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
        var shares = ranked.prefix(5).enumerated().map { index, pair in
            GenreShare(
                id: pair.key,
                name: catalog.genreNames[pair.key] ?? "Genre \(pair.key)",
                share: Double(pair.value) / total,
                colorIndex: index
            )
        }
        let remainder = ranked.dropFirst(5).map(\.value).reduce(0, +)
        if remainder > 0 {
            shares.append(GenreShare(id: -1, name: "Autres", share: Double(remainder) / total, colorIndex: -1))
        }
        return shares
    }
}
