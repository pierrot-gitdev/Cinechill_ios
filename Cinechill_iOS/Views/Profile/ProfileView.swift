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
    @EnvironmentObject private var socialStore: SocialStore
    @Environment(MediaCatalog.self) private var catalog
    @Environment(\.dismiss) private var dismiss

    @State private var showSettings = false
    @State private var showSearch = false
    @State private var showHandleSheet = false

    private var galleryCount: Int { libraryStore.galleryItems.count }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    signatureCard
                    hallRow
                    badgesSection
                    dnaSection
                }
                .padding(.horizontal, Metrics.margin)
                .padding(.top, 22)
                .padding(.bottom, 36)
            }
            .background(Ink.ground)
            .navigationBarHidden(true)
            .safeAreaInset(edge: .top) { topBar }
            .navigationDestination(for: MediaItem.self) { item in
                ItemDetailView(item: item)
            }
            .navigationDestination(for: HallRoute.self) { route in
                switch route {
                case .following:
                    FollowListView(mode: .following)
                case .followers:
                    FollowListView(mode: .followers)
                case .search:
                    ProfileSearchView()
                }
            }
        }
        .sheet(isPresented: $showSettings, onDismiss: { profileStore.refresh() }) {
            SettingsView()
                .environmentObject(profileStore)
                .environmentObject(authService)
                .environmentObject(libraryStore)
                .environmentObject(socialStore)
        }
        .sheet(isPresented: $showHandleSheet) {
            ClaimHandleSheet()
                .environmentObject(socialStore)
        }
        .task {
            profileStore.refresh()
            await catalog.loadIfNeeded()
            await badgesModel.refresh()
            // Rattrape les profils publics créés avant que le nom affiché ne
            // soit synchronisé avec les réglages — sans ça, un profil déjà
            // existant resterait cherchable par pseudo seulement.
            await socialStore.syncDisplayName(profileStore.displayName)
        }
    }

    // MARK: - Barre

    /// Le plafond commun, avec ses deux actions. L'écran avait sa propre barre
    /// translucide, quatrième plafond de l'application pour un seul volume.
    private var topBar: some View {
        PlanHeader(String(localized: "Profil", bundle: .app), leading: .close) {
            HStack(spacing: 4) {
                // La recherche de profils n'a pas de place permanente dans la
                // navigation : on la trouve là où l'on gère ses relations.
                NavigationLink(value: HallRoute.search) {
                    CinechillHallIconView(.chercher)
                        .frame(width: 18, height: 18)
                        .foregroundStyle(Ink.ink2)
                        .frame(width: 34, height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableScaleStyle(scale: 0.9))
                .accessibilityLabel(String(localized: "Rechercher un profil", bundle: .app))

                Button { showSettings = true } label: {
                    SettingsGlyph()
                        .stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                        .foregroundStyle(Ink.ink2)
                        .frame(width: 18, height: 18)
                        .frame(width: 34, height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableScaleStyle(scale: 0.9))
                .accessibilityLabel(String(localized: "Réglages", bundle: .app))
            }
        }
    }

    // MARK: - La carte

    private var signatureCard: some View {
        ProfileSignatureCard()
    }

    // MARK: - Le Hall

    /// Les deux compteurs du Hall, posés juste sous la carte de signature.
    /// Une seule ligne neuve sur tout l'écran : abonnés et abonnements sont
    /// une propriété du profil, pas une destination de la navigation.
    @ViewBuilder
    private var hallRow: some View {
        if socialStore.myProfile == nil, socialStore.hasLoadedProfileOnce {
            claimHandleBanner
        } else {
            // Cinq compteurs sur deux cartes séparées disaient la même chose de
            // deux façons. Une seule rangée, entre deux filets : les chiffres du
            // profil sont une propriété du profil, pas cinq objets posés dessus.
            VStack(spacing: 0) {
                PlanEdge()
                HStack(spacing: 0) {
                    statCell(value: socialStore.myProfile?.followingCount ?? 0, label: String(localized: "Abonnements", bundle: .app), route: .following)
                    statCell(value: socialStore.myProfile?.followerCount ?? 0, label: String(localized: "Abonnés", bundle: .app), route: .followers)
                    statCell(value: galleryCount, label: String(localized: "Vus", bundle: .app))
                    statCell(value: libraryStore.watchlistItems.count, label: String(localized: "À voir", bundle: .app))
                }
                PlanEdge()
            }
        }
    }

    private func statCell(value: Int, label: String, route: HallRoute? = nil) -> some View {
        let content = VStack(spacing: 5) {
            Text(verbatim: "\(value)")
                .planTitle(21)
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(Ink.ink)
            Text(label)
                .planLabel()
                .foregroundStyle(Ink.ink3)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .contentShape(Rectangle())

        return Group {
            if let route {
                NavigationLink(value: route) { content }
                    .buttonStyle(PressableScaleStyle(scale: 0.97))
            } else {
                content
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: "\(value) \(label)"))
    }

    /// Sans pseudo, on n'est ni trouvable ni suivable : l'invitation remplace
    /// donc les compteurs plutôt que de les afficher vides.
    private var claimHandleBanner: some View {
        Button {
            showHandleSheet = true
        } label: {
            HStack(alignment: .top, spacing: 11) {
                PlanLight().padding(.top, 6)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Choisis ton pseudo", bundle: .app)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Ink.ink)
                    Text("Pour qu'on puisse te retrouver et te recommander des films.", bundle: .app)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Ink.ink2)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
            .overlay(alignment: .top) { PlanEdge() }
            .overlay(alignment: .bottom) { PlanEdge() }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Badges

    private var badgesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Mes badges", bundle: .app)
                    .planTitle(21)
                    .foregroundStyle(Ink.ink)
                Spacer()
                NavigationLink(destination: BadgeGalleryView(model: badgesModel)) {
                    HStack(spacing: 7) {
                        Text(verbatim: "\(badgesModel.unlockedCount)")
                            .planLabel()
                            .monospacedDigit()
                            .foregroundStyle(Ink.ink3)
                        Text("Tout voir", bundle: .app)
                            .font(.system(size: 12))
                            .foregroundStyle(Ink.ink2)
                            .overlay(alignment: .bottom) {
                                Rectangle().fill(Ink.ruleSet).frame(height: 1).offset(y: 2)
                            }
                    }
                    .contentShape(Rectangle().inset(by: -10))
                }
                .buttonStyle(.plain)
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
            HStack(spacing: 14) {
                if let first = BadgeCatalog.all.first {
                    BadgeView(badge: first, isUnlocked: false, size: 52)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Quinze badges à décrocher", bundle: .app)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Ink.ink)
                    Text("Le premier tombe dès ton premier film.", bundle: .app)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Ink.ink2)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
            .overlay(alignment: .top) { PlanEdge() }
            .overlay(alignment: .bottom) { PlanEdge() }
        }
        .buttonStyle(.plain)
    }

    // MARK: - ADN

    @ViewBuilder
    private var dnaSection: some View {
        let shares = genreShares
        if !shares.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text("Ton ADN cinéphile", bundle: .app)
                    .planTitle(21)
                    .foregroundStyle(Ink.ink)

                GeometryReader { proxy in
                    HStack(spacing: 1.5) {
                        ForEach(shares) { share in
                            Rectangle()
                                .fill(share.color)
                                .frame(width: max(2, proxy.size.width * share.share - 1.5))
                        }
                    }
                }
                .frame(height: 6)

                FlowLayout(spacing: 14) {
                    ForEach(shares.prefix(4)) { share in
                        HStack(spacing: 6) {
                            Rectangle().fill(share.color).frame(width: 5, height: 5)
                            Text(share.name).foregroundStyle(Ink.ink2)
                            Text(share.percentText).foregroundStyle(Ink.ink).monospacedDigit()
                        }
                        .font(.system(size: 11))
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
                name: catalog.genreNames[pair.key] ?? String(localized: "Genre \(pair.key)", bundle: .app),
                share: Double(pair.value) / total,
                colorIndex: index
            )
        }
        let remainder = ranked.dropFirst(5).map(\.value).reduce(0, +)
        if remainder > 0 {
            shares.append(GenreShare(id: -1, name: String(localized: "Autres", bundle: .app), share: Double(remainder) / total, colorIndex: -1))
        }
        return shares
    }
}

/// L'icône des réglages, dans l'écriture « La Gravure » : deux glissières et
/// leurs curseurs. Un engrenage plein aurait été le second élément plein d'une
/// famille qui n'en admet qu'un, le point de lumière.
private struct SettingsGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * scale, y: rect.minY + y * scale)
        }

        var path = Path()
        path.move(to: p(3.5, 8.5))
        path.addLine(to: p(20.5, 8.5))
        path.move(to: p(3.5, 15.5))
        path.addLine(to: p(20.5, 15.5))
        path.addEllipse(in: CGRect(
            x: p(9, 8.5).x - 2.6 * scale, y: p(9, 8.5).y - 2.6 * scale,
            width: 5.2 * scale, height: 5.2 * scale
        ))
        path.addEllipse(in: CGRect(
            x: p(15.5, 15.5).x - 2.6 * scale, y: p(15.5, 15.5).y - 2.6 * scale,
            width: 5.2 * scale, height: 5.2 * scale
        ))
        return path
    }
}
