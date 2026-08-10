import SwiftUI

/// La fiche film — « La Fiche ».
///
/// Point d'arrivée de **tous** les parcours : accueil, deck, galerie, watchlist,
/// notification, profil d'un ami. C'est l'écran le plus vu de l'application, et
/// il n'a qu'un but : décider.
///
/// Trois décisions structurent le dessin :
///
/// - **La décision tient le plancher, et n'en bouge plus.** On peut dérouler le
///   synopsis, le casting, les plateformes : « Vu » et « À voir » restent sous le
///   pouce. C'était le seul écran de l'app dont l'action principale pouvait
///   sortir du champ.
/// - **Un seul accent.** L'écran comptait le vert du « vu », le bleu du « à
///   voir », l'indigo du bloc galerie et des plateformes, le jaune de l'étoile et
///   le cyan du bouton recommander. L'état sélectionné n'est plus une teinte mais
///   un aplat d'encre — la paire `PlanButton` / `PlanSecondaryButton` du parcours
///   d'authentification, reprise sans un composant de plus.
/// - **Le plafond est celui de l'app.** En haut de page le backdrop est nu, avec
///   les seules actions gravées ; passé le héros, le filet et le titre se posent.
///   La fiche était le seul écran à porter un bouton rond flottant.
struct ItemDetailView: View {
    let item: MediaItem

    @EnvironmentObject private var libraryStore: LibraryStore
    @EnvironmentObject private var socialStore: SocialStore
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    @State private var detail: TMDBDetailResponse?
    @State private var loading = true
    @State private var errorMessage: String?
    @State private var showComposer = false
    @State private var outcome: SuggestionOutcome?
    /// Position du haut du contenu par rapport au haut de l'écran. Sert au seul
    /// mouvement de l'écran : la matérialisation du plafond.
    @State private var scrollOffset: CGFloat = 0

    private static let heroHeight: CGFloat = 260

    private var displayItem: MediaItem {
        detail.map { $0.asMediaItem(mediaType: item.mediaType) } ?? item
    }

    private var currentStatus: DetailStatus {
        if libraryStore.isInGallery(displayItem) { return .seen }
        if libraryStore.isInWatchlist(displayItem) { return .toWatch }
        return .none
    }

    /// De 0 (backdrop nu) à 1 (plafond posé). La bascule se joue sur les 90
    /// derniers points du héros : assez long pour ne pas clignoter, assez court
    /// pour que le titre soit là quand on en a besoin.
    private var ceilingProgress: Double {
        let start = Self.heroHeight - 130
        let travel: CGFloat = 90
        return Double(min(1, max(0, (-scrollOffset - start) / travel)))
    }

    var body: some View {
        ZStack(alignment: .top) {
            Ink.ground.ignoresSafeArea()
            content
            ceiling
        }
        .safeAreaInset(edge: .bottom) { decisionFloor }
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .bottom) { outcomeBanner }
        .sheet(isPresented: $showComposer) {
            SuggestionComposerSheet(item: displayItem) { result in
                guard !result.isSilent else { return }
                withAnimation(.easeOut(duration: 0.25)) { outcome = result }
            }
            .environmentObject(socialStore)
        }
        .task { await loadDetail() }
        .task(id: outcome) {
            guard outcome != nil else { return }
            try? await Task.sleep(for: .seconds(3))
            withAnimation(.easeOut(duration: 0.25)) { outcome = nil }
        }
    }

    // MARK: - Le contenu

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Sonde de défilement : le seul mouvement de l'écran en dépend.
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: HeroOffsetKey.self,
                        value: proxy.frame(in: .named("fiche")).minY
                    )
                }
                .frame(height: 0)

                hero
                generique

                if let connection = galleryConnection {
                    remark(connection)
                }

                watchSection
                synopsisSection

                if let cast = detail?.credits?.cast, !cast.isEmpty {
                    castSection(cast)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Ink.warn)
                        .padding(.horizontal, Metrics.margin)
                        .padding(.top, 24)
                }
            }
            .padding(.bottom, 32)
        }
        .coordinateSpace(name: "fiche")
        .onPreferenceChange(HeroOffsetKey.self) { scrollOffset = $0 }
        .ignoresSafeArea(edges: .top)
        .scrollIndicators(.hidden)
    }

    // MARK: - Le plafond

    /// Nu sur le backdrop, posé une fois le héros passé. Le filet et le voile
    /// sont ceux de `AppHeaderView`, aux mêmes valeurs — c'est cette égalité qui
    /// fait lire la fiche comme une pièce du même volume.
    private var ceiling: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                glyphButton(.back, label: String(localized: "Retour", bundle: .app)) { dismiss() }

                Text(displayItem.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Ink.ink)
                    .lineLimit(1)
                    .opacity(ceilingProgress)

                Spacer(minLength: 8)

                if detail?.trailerKey != nil {
                    glyphButton(.play, label: String(localized: "Voir la bande-annonce", bundle: .app), action: openTrailer)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 10)

            PlanRail().opacity(ceilingProgress)
        }
        .background {
            PlanScrim()
                .opacity(ceilingProgress)
                .ignoresSafeArea(edges: .top)
        }
        .animation(.easeOut(duration: 0.15), value: ceilingProgress < 0.5)
    }

    private func glyphButton(
        _ glyph: DetailGlyph.Kind, label: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            DetailGlyph(kind: glyph)
                .stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                .foregroundStyle(Ink.ink)
                .frame(width: 22, height: 22)
                // Sur le backdrop, le tracé seul ne tiendrait pas sur une image
                // claire : une ombre courte le détache sans poser d'objet.
                .shadow(color: .black.opacity(1 - ceilingProgress), radius: 5)
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableScaleStyle(scale: 0.9))
        .accessibilityLabel(label)
    }

    // MARK: - Le héros

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: Self.heroHeight)
                .overlay { backdrop }
                .clipped()
                .overlay(scrim)

            HStack(alignment: .bottom, spacing: 14) {
                PosterTile(
                    posterPath: detail?.posterPath ?? item.posterPath,
                    title: displayItem.title,
                    width: 64
                )

                VStack(alignment: .leading, spacing: 7) {
                    Text(displayItem.title)
                        .planTitle(24)
                        .foregroundStyle(Ink.ink)
                        .lineLimit(3)
                        .minimumScaleFactor(0.75)

                    if let tagline = detail?.tagline, !tagline.isEmpty {
                        Text(tagline)
                            .font(.system(size: 12))
                            .foregroundStyle(Ink.ink2)
                            .lineLimit(2)
                    }
                }
                .padding(.bottom, 2)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, Metrics.margin)
            .padding(.bottom, 14)
        }
        .frame(height: Self.heroHeight)
    }

    @ViewBuilder
    private var backdrop: some View {
        if let url = detail?.backdropURL {
            PosterImageView(url: url)
        } else {
            // Sans backdrop, la nuit plutôt qu'un dégradé inventé : c'est le
            // fond de l'app, et l'affiche suffit à porter le héros.
            Ink.ground
        }
    }

    private var scrim: some View {
        LinearGradient(
            stops: [
                .init(color: Ink.ground.opacity(0.55), location: 0),
                .init(color: Ink.ground.opacity(0.10), location: 0.30),
                .init(color: Ink.ground.opacity(0.80), location: 0.78),
                .init(color: Ink.ground, location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .allowsHitTesting(false)
    }

    // MARK: - Le générique

    /// Année, durée, genre, réalisateur : les faits, au niveau de service. La
    /// note perd son étoile jaune — c'était le dernier meuble d'app générique de
    /// l'écran — et devient un nombre, avec son dénominateur en ardoise.
    private var generique: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !facts.isEmpty {
                Text(facts)
                    .planLabel()
                    .foregroundStyle(Ink.ink2)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(alignment: .firstTextBaseline, spacing: 7) {
                if let rating = detail?.voteAverage ?? item.voteAverage, rating > 0 {
                    Text(rating.formatted(.number.precision(.fractionLength(1))))
                        .planTitle(22)
                        .monospacedDigit()
                        .foregroundStyle(Ink.ink)

                    Text(voteText)
                        .font(.system(size: 11))
                        .foregroundStyle(Ink.ink3)
                }

                Spacer(minLength: 0)

                if loading {
                    CinechillSpinner(size: 15)
                }
            }
        }
        .padding(.horizontal, Metrics.margin)
        .padding(.top, 20)
    }

    private var facts: String {
        var parts: [String] = []
        let year = detail?.displayYear ?? item.displayYear
        if !year.isEmpty, year != "—" { parts.append(year) }
        if let runtime = detail?.runtimeText { parts.append(runtime) }
        if let genres = detail?.genreNames, !genres.isEmpty {
            parts.append(genres.prefix(2).joined(separator: ", "))
        }
        if let director = detail?.director, !director.isEmpty { parts.append(director) }
        return parts.joined(separator: " · ")
    }

    private var voteText: String {
        guard let count = detail?.voteCount, count > 0 else { return String(localized: "/ 10", bundle: .app) }
        return String(localized: "/ 10 · \(count.formatted(.number.grouping(.automatic))) votes", bundle: .app)
    }

    // MARK: - La remarque

    /// Ce qui distingue la fiche d'une page TMDB : elle sait ce que vous avez
    /// déjà vu. Calculé en local, sans un appel réseau de plus.
    ///
    /// Ce n'était pas une carte. Une carte annonce une information du même poids
    /// que le reste de l'écran ; ceci est une remarque — une ligne, précédée du
    /// point de lumière, qui dit partout dans l'app la même chose : *acquis*.
    private func remark(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 11) {
            PlanLight().padding(.top, 6)

            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(Ink.ink2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Metrics.margin)
        .padding(.top, 18)
        .accessibilityElement(children: .combine)
    }

    private var galleryConnection: String? {
        let gallery = libraryStore.galleryItems
        guard gallery.count >= 3 else { return nil }

        // Le réalisateur n'est pas stocké dans les entrées de galerie : le seul
        // recoupement possible sans appel réseau supplémentaire est le genre,
        // affiné par la décennie quand elle est connue.
        guard let genreID = displayItem.genreIds.first else { return nil }
        let genreName = detail?.genreNames?.first?.lowercased()

        if let decade = decadeOfItem {
            let sameVein = gallery.filter { entry in
                entry.genreIds.contains(genreID) && decadeOf(entry.releaseDate) == decade
            }.count
            if sameVein >= 2 {
                // Le rang est écrit dans la phrase plutôt que fabriqué à part :
                // le suffixe ordinal ne se pose pas de la même façon d'une
                // langue à l'autre — « 3ᵉ » ici, « 3rd » ailleurs.
                let rank = sameVein + 1
                if let genreName {
                    return String(localized: "\(rank)ᵉ \(genreName) des années \(decade) dans votre galerie.", bundle: .app)
                }
                return String(localized: "\(rank)ᵉ films du même genre sur cette décennie dans votre galerie.", bundle: .app)
            }
        }

        let sameGenre = gallery.filter { $0.genreIds.contains(genreID) }.count
        guard sameGenre >= 3 else { return nil }
        if let genreName {
            return String(localized: "\(sameGenre + 1)ᵉ \(genreName) de votre galerie.", bundle: .app)
        }
        return String(localized: "Vous avez déjà \(sameGenre) films de ce genre dans votre galerie.", bundle: .app)
    }

    private var decadeOfItem: Int? {
        decadeOf(detail?.releaseDate ?? item.releaseDate)
    }

    private func decadeOf(_ releaseDate: String?) -> Int? {
        guard let releaseDate, releaseDate.count >= 4,
              let year = Int(releaseDate.prefix(4)) else { return nil }
        return year / 10 * 10
    }

    // MARK: - Où le voir

    /// Remonté au-dessus du synopsis : c'est la seule information actionnable de
    /// la moitié basse, et elle passait derrière un texte de quarante lignes.
    ///
    /// Vos plateformes d'abord, les autres en retrait — mais jamais rien de
    /// caché : l'ancienne version masquait toute la section quand vous n'étiez
    /// aucune des siennes, alors que l'information existait.
    @ViewBuilder
    private var watchSection: some View {
        let all = detail?.watchProvidersFR ?? []
        if !all.isEmpty {
            let mine = all.filter { libraryStore.preferredPlatformIDs.contains(String($0.providerID)) }
            let others = all.filter { !libraryStore.preferredPlatformIDs.contains(String($0.providerID)) }

            VStack(alignment: .leading, spacing: 0) {
                PlanEdge().padding(.horizontal, Metrics.margin)

                Text("Où le voir", bundle: .app)
                    .planLabel()
                    .foregroundStyle(Ink.ink2)
                    .padding(.horizontal, Metrics.margin)
                    .padding(.top, 20)
                    .padding(.bottom, 14)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Metrics.gutter) {
                        ForEach(mine, id: \.providerID) { provider in
                            providerButton(provider, isMine: true)
                        }

                        if !mine.isEmpty, !others.isEmpty {
                            Rectangle()
                                .fill(Ink.ruleSet)
                                .frame(width: 1, height: 22)
                                .padding(.horizontal, 3)
                        }

                        ForEach(others, id: \.providerID) { provider in
                            providerButton(provider, isMine: false)
                        }
                    }
                    .padding(.horizontal, Metrics.margin)
                }
                .scrollClipDisabled()
            }
            .padding(.top, 24)
        }
    }

    private func providerButton(_ provider: TMDBDetailWatchProviderItem, isMine: Bool) -> some View {
        Button {
            openProvider(provider)
        } label: {
            Group {
                if let url = provider.logoURL {
                    PosterImageView(url: url)
                } else {
                    Text(provider.providerName.prefix(3).uppercased())
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Ink.ink2)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(hex: 0x151B23))
                }
            }
            .frame(width: 42, height: 42)
            .clipShape(RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                    .strokeBorder(isMine ? Ink.ink : Ink.rule, lineWidth: 1)
            )
            // Retenue : pleine saturation. Hors de vos plateformes : en retrait. Le même
            // couple que dans les réglages, pour le même objet.
            .opacity(isMine ? 1 : 0.4)
            .saturation(isMine ? 1 : 0.25)
        }
        .buttonStyle(PressableScaleStyle(scale: 0.92))
        .accessibilityLabel(provider.providerName)
        .accessibilityValue(isMine
                            ? String(localized: "Sur vos plateformes", bundle: .app)
                            : String(localized: "Hors de vos plateformes", bundle: .app))
    }

    // MARK: - Synopsis

    @ViewBuilder
    private var synopsisSection: some View {
        if let text = detail?.overview ?? item.overview, !text.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                PlanEdge().padding(.horizontal, Metrics.margin)

                Text("Synopsis", bundle: .app)
                    .planLabel()
                    .foregroundStyle(Ink.ink2)
                    .padding(.top, 20)
                    .padding(.bottom, 12)

                Text(text)
                    .font(.system(size: 14))
                    .foregroundStyle(Ink.ink2)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Metrics.margin)
            .padding(.top, 24)
        }
    }

    // MARK: - Casting

    private func castSection(_ cast: [TMDBDetailCastMember]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            PlanEdge().padding(.horizontal, Metrics.margin)

            Text("Casting", bundle: .app)
                .planLabel()
                .foregroundStyle(Ink.ink2)
                .padding(.horizontal, Metrics.margin)
                .padding(.top, 20)
                .padding(.bottom, 14)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(cast, id: \.name) { member in
                        VStack(spacing: 8) {
                            Group {
                                if let url = member.profileURL {
                                    PosterImageView(url: url)
                                } else {
                                    Color(hex: 0x151B23)
                                }
                            }
                            .frame(width: 56, height: 56)
                            .clipShape(Circle())
                            .overlay(Circle().strokeBorder(Ink.rule, lineWidth: 1))

                            VStack(spacing: 2) {
                                Text(member.name)
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundStyle(Ink.ink)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)

                                if let character = member.character, !character.isEmpty {
                                    Text(character)
                                        .font(.system(size: 9.5))
                                        .foregroundStyle(Ink.ink3)
                                        .multilineTextAlignment(.center)
                                        .lineLimit(2)
                                }
                            }
                        }
                        .frame(width: 68)
                    }
                }
                .padding(.horizontal, Metrics.margin)
            }
            .scrollClipDisabled()
        }
        .padding(.top, 24)
    }

    // MARK: - Le plancher de décision

    /// **Le cœur de l'écran.** Deux issues, toujours atteignables.
    ///
    /// L'état retenu est un aplat d'encre, l'autre un contour : c'est une
    /// hiérarchie, pas une convention de couleur à apprendre. Le point posé sur
    /// l'aplat dit lequel — plein pour « vu », creux pour « à voir » — si bien
    /// que l'écran reste lisible en niveaux de gris.
    ///
    /// Retaper le choix courant le retire. L'ancienne barre offrait un quatrième
    /// bouton `✕` pour ça : un contrôle de plus pour une action que le bouton
    /// déjà présent pouvait porter.
    private var decisionFloor: some View {
        VStack(spacing: 0) {
            PlanEdge()

            HStack(spacing: Metrics.gutter) {
                decisionButton(.seen, label: String(localized: "Vu", bundle: .app))
                decisionButton(.toWatch, label: String(localized: "À voir", bundle: .app))

                // « Recommander » n'apparaît que si le film est vu : la règle
                // « on ne recommande que ce qu'on a vu » n'est jamais énoncée,
                // elle est simplement vraie à l'écran.
                if currentStatus == .seen {
                    Button {
                        Haptics.impact(.light)
                        showComposer = true
                    } label: {
                        CinechillHallIconView(.recommander)
                            .frame(width: 18, height: 18)
                            .foregroundStyle(Ink.ink)
                            .frame(width: 48, height: Metrics.control)
                            .overlay(
                                RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                                    .strokeBorder(Ink.ruleSet, lineWidth: 1)
                            )
                    }
                    .buttonStyle(PressableScaleStyle(scale: 0.94))
                    .transition(.opacity)
                    .accessibilityLabel(String(localized: "Recommander à un ami", bundle: .app))
                }
            }
            .padding(.horizontal, Metrics.margin)
            .padding(.top, 14)
            .padding(.bottom, 10)
        }
        .background(Ink.ground)
        .animation(Metrics.shift, value: currentStatus)
    }

    private func decisionButton(_ status: DetailStatus, label: String) -> some View {
        let isOn = currentStatus == status
        return Button {
            Haptics.impact(isOn ? .light : .medium)
            toggle(status)
        } label: {
            HStack(spacing: 7) {
                Text(label)
                    .font(.system(size: 14, weight: isOn ? .semibold : .regular))

                if isOn {
                    if status == .seen {
                        PlanLight(tint: Ink.ground)
                    } else {
                        PlanLightOutline(tint: Ink.ground)
                    }
                }
            }
            .foregroundStyle(isOn ? Ink.ground : Ink.ink)
            .frame(maxWidth: .infinity)
            .frame(height: Metrics.control)
            .background {
                if isOn {
                    RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                        .fill(Ink.ink)
                } else {
                    RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                        .strokeBorder(Ink.ruleSet, lineWidth: 1)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous))
        }
        .buttonStyle(PressableScaleStyle(scale: 0.96))
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
        .accessibilityHint(isOn ? String(localized: "Toucher à nouveau pour retirer de vos listes", bundle: .app) : "")
    }

    private func toggle(_ status: DetailStatus) {
        guard currentStatus != status else {
            if status == .seen {
                libraryStore.removeFromGallery(displayItem)
            } else {
                libraryStore.removeFromWatchlist(displayItem)
            }
            return
        }

        if status == .seen {
            // La fiche est le seul écran à connaître le réalisateur et la saga :
            // c'est ici qu'ils entrent en galerie, pour les badges « Signature »
            // et « L'Intégrale ».
            libraryStore.addToGallery(
                displayItem,
                director: detail?.director,
                collectionID: detail?.collectionID,
                collectionTotal: detail?.collectionCount
            )
        } else {
            libraryStore.addToWatchlist(displayItem)
        }
    }

    // MARK: - Confirmation

    @ViewBuilder
    private var outcomeBanner: some View {
        if let outcome {
            SuggestionOutcomeBanner(outcome: outcome)
        }
    }

    // MARK: - Actions

    private func openTrailer() {
        guard let appURL = detail?.trailerAppURL,
              let webURL = detail?.trailerURL else { return }
        if UIApplication.shared.canOpenURL(appURL) {
            UIApplication.shared.open(appURL)
        } else {
            openURL(webURL)
        }
    }

    /// Ouvre l'app native de la plateforme si elle est installée (ex. Netflix via `nflx://`),
    /// sinon retombe sur le site web du service.
    private func openProvider(_ provider: TMDBDetailWatchProviderItem) {
        for candidate in StreamingProviderLink.appURLs(forProviderID: provider.providerID, title: displayItem.title)
        where UIApplication.shared.canOpenURL(candidate) {
            UIApplication.shared.open(candidate)
            return
        }
        guard let url = provider.webURL else { return }
        openURL(url)
    }

    private func loadDetail() async {
        loading = true
        errorMessage = nil
        defer { loading = false }
        let client = BackendDetailClient()
        do {
            detail = try await client.itemDetails(id: item.tmdbId, mediaType: item.mediaType)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

// MARK: - Statut (miroir de LibraryStore)

private enum DetailStatus {
    case toWatch, seen, none
}

// MARK: - Sonde de défilement

private struct HeroOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Les glyphes de la fiche

/// Le retour et la lecture, dans l'écriture « La Gravure » : grille de 24, trait
/// de 1,5, extrémités rondes. La pointe de lecture est ouverte — une flèche
/// pleine serait un second élément plein, ce que la famille n'admet pas.
private struct DetailGlyph: Shape {
    enum Kind { case back, play }

    let kind: Kind

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * scale, y: rect.minY + y * scale)
        }

        var path = Path()
        switch kind {
        case .back:
            path.move(to: p(14.6, 4.8))
            path.addLine(to: p(8, 12))
            path.addLine(to: p(14.6, 19.2))
        case .play:
            path.move(to: p(8.6, 5.6))
            path.addLine(to: p(18.4, 12))
            path.addLine(to: p(8.6, 18.4))
            path.closeSubpath()
        }
        return path
    }
}
