import SwiftUI

/// Le profil, lu comme un relevé de palmarès.
///
/// L'écran suit l'ordre d'une cérémonie : la distinction et le badge couronné,
/// les chiffres du Hall, puis la liste datée de ce qui a été décerné. Les badges
/// ne sont plus une rangée de vignettes posée au milieu de la page ; celui qui
/// est en vitrine se voit en grand dans l'écu, les autres sont cités.
///
/// L'écran reste quasi monochrome. Si la surface a sa propre identité
/// chromatique et le badge la sienne, les deux se battent : la seule couleur
/// admise est celle de la distinction, sur le trait de la couronne et le nom du
/// rang.
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
                    palmaresSection
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

    // MARK: - Palmarès

    /// Les badges cessent d'être une rangée de vignettes à faire défiler pour
    /// devenir la **liste datée de ce qui t'a été décerné**, et la distinction
    /// est le rang que cette liste te vaut. Les vignettes ne manquent pas : le
    /// badge choisi est montré en grand, couronné, au-dessus.
    ///
    /// La date existait déjà dans le modèle, sous `BadgeProgress.unlockedAt`, et
    /// n'avait jamais été affichée nulle part ailleurs que sur la fiche d'un
    /// badge.
    private var palmaresSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Palmarès", bundle: .app)
                    .planLabel()
                    .foregroundStyle(Ink.ink2)
                Spacer()
                NavigationLink(destination: BadgeGalleryView(model: badgesModel)) {
                    HStack(spacing: 7) {
                        Text(verbatim: "\(badgesModel.unlockedCount) / \(badgesModel.totalCount)")
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
            .padding(.bottom, 9)

            PlanEdge()

            if badgesModel.showcase.isEmpty {
                emptyPalmares
            } else {
                ForEach(badgesModel.showcase.prefix(4)) { badge in
                    citationRow(badge)
                }
            }
        }
    }

    private func citationRow(_ badge: Badge) -> some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(badge.rarity.accent)
                .frame(width: 5, height: 5)

            Text(badge.name)
                .font(.system(size: 12.5))
                .foregroundStyle(Ink.ink)
                .lineLimit(1)

            Spacer(minLength: 8)

            if let date = badgesModel.progress(for: badge).unlockedAt {
                Text(verbatim: Millesime.citation(for: date))
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(Ink.ink3)
            }
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { PlanEdge() }
        .accessibilityElement(children: .combine)
    }

    private var emptyPalmares: some View {
        NavigationLink(destination: BadgeGalleryView(model: badgesModel)) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Quinze distinctions à décrocher", bundle: .app)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Ink.ink)
                Text("La première tombe dès ton premier film.", bundle: .app)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Ink.ink2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
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
