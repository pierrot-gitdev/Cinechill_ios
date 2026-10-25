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
///   synopsis, le casting, les plateformes : où est le film, et ce qu'on peut en
///   faire, restent sous le pouce. C'était le seul écran de l'app dont l'action principale pouvait
///   sortir du champ.
/// - **Un seul accent.** L'écran comptait le vert du « vu », le bleu du « à
///   voir », l'indigo du bloc galerie et des plateformes, le jaune de l'étoile et
///   le cyan du bouton recommander. L'état sélectionné n'est plus une teinte mais
///   un aplat d'encre — la paire `PlanButton` / `PlanSecondaryButton` du parcours
///   d'authentification, reprise sans un composant de plus.
/// - **Le plafond est celui de l'app.** En haut de page le backdrop est nu, avec
///   les seules actions gravées ; passé le héros, le filet et le titre se posent.
///   La fiche était le seul écran à porter un bouton rond flottant.
struct FilmDetailView: View {
    let item: MediaItem
    /// Ouverte depuis la question du lendemain : les quatre réponses passent
    /// en tête, sous le héros, jusqu'à ce qu'on en ait choisi une.
    var asksVerdict: Bool = false

    @EnvironmentObject private var libraryStore: LibraryStore
    @EnvironmentObject private var socialStore: SocialStore
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    @State private var detail: TMDBDetailResponse?
    @State private var loading = true
    @State private var errorMessage: String?
    @State private var showComposer = false
    /// « Remettre dans ma watchlist » sur un film adoré : le cœur partirait
    /// avec la galerie, on le demande avant.
    @State private var confirmsBackToWatchlist = false
    @State private var outcome: SuggestionOutcome?
    /// La saga proposée après un « Vu », s'il y en a une. Elle ne se propose
    /// qu'une fois par visite de la fiche : on ne la repose pas à chaque
    /// aller-retour sur le bouton.
    @State private var sagaOffer: SagaOffer?
    @State private var hasOfferedSaga = false
    /// Position du haut du contenu par rapport au haut de l'écran. Sert au seul
    /// mouvement de l'écran : la matérialisation du plafond.
    @State private var scrollOffset: CGFloat = 0
    /// Les réponses du lendemain sont encore affichées.
    @State private var showsVerdict = true
    /// « Lequel est le plus sombre ? », posée à la place de la question du
    /// lendemain une fois celle-ci répondue, si le serveur en a une.
    @State private var darkerQuestion: CineMatchDarkerQuestion?
    /// La clé YouTube de la bande-annonce qui joue, s'il y en a une.
    @State private var playingTrailer: String?
    private let cineMatchClient: any CineMatchFetching = BackendCineMatchClient()

    private static let heroHeight: CGFloat = 260
    /// La taille réelle du titre, qui suit Dynamic Type. Le héros grandit du
    /// surplus de ses trois lignes : à hauteur fixe, un titre agrandi montait
    /// jusque sous les boutons du haut.
    @ScaledMetric(relativeTo: .title2) private var heroTitleSize: CGFloat = 24
    private var heroFrameHeight: CGFloat { Self.heroHeight + max(0, heroTitleSize - 24) * 3 }

    /// Le détail complète l'item sans l'écraser. Les genres de l'item passent
    /// d'abord, ceux du détail quand l'item arrive sans (un récent de la
    /// recherche) : `genreIds: []` à l'écriture de « Vu » ou « À voir »
    /// faussait genres exclus, badges et profil CinéMatch.
    private var displayItem: MediaItem {
        guard let detail else { return item }
        let fresh = detail.asMediaItem(mediaType: item.mediaType)
        return MediaItem(
            tmdbId: fresh.tmdbId,
            mediaType: fresh.mediaType,
            title: fresh.title,
            posterPath: fresh.posterPath ?? item.posterPath,
            overview: fresh.overview ?? item.overview,
            voteAverage: fresh.voteAverage ?? item.voteAverage,
            voteCount: fresh.voteCount ?? item.voteCount,
            genreIds: item.genreIds.isEmpty ? fresh.genreIds : item.genreIds,
            releaseDate: fresh.releaseDate ?? item.releaseDate
        )
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
            // Le plafond des trois fiches : celui de la fiche film en était une
            // copie, et ses cibles de 34 pt n'avaient pas suivi.
            DetailCeiling(
                title: displayItem.title,
                progress: ceilingProgress,
                onBack: { dismiss() },
                onTrailer: trailerAction
            )
        }
        .safeAreaInset(edge: .bottom) { decisionFloor }
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .bottom) { outcomeBanner }
        .trailerTheater($playingTrailer)
        .sheet(isPresented: $showComposer) {
            SuggestionComposerSheet(item: displayItem) { result in
                guard !result.isSilent else { return }
                withAnimation(.easeOut(duration: 0.25)) { outcome = result }
            }
            .environmentObject(socialStore)
        }
        // La fiche est le second endroit où un « vu » peut ouvrir une saga, et
        // c'est le même composant qu'au deck : ranger un film n'a pas deux
        // suites possibles selon l'écran d'où on l'a rangé.
        .sheet(item: $sagaOffer) { offer in
            SagaSheet(offer: offer, onClose: { sagaOffer = nil })
                .environmentObject(libraryStore)
        }
        .task { await loadDetail() }
        // Ouvrir une fiche est le meilleur signe qu'un « Vu » approche. Le réveil de
        // l'ouverture a pu expirer depuis, et le magasin sait s'il est encore valable.
        .task { await libraryStore.warmUpStatusEndpoint() }
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

                if asksVerdict, showsVerdict {
                    FilmVerdictPrompt(item: displayItem) {
                        withAnimation(Metrics.unfold) { showsVerdict = false }
                        Task { await askDarker() }
                    }
                    .transition(.opacity)
                } else if let darkerQuestion {
                    DarkerQuestionPrompt(question: darkerQuestion, client: cineMatchClient) {
                        withAnimation(Metrics.unfold) { self.darkerQuestion = nil }
                    }
                    .transition(.opacity)
                }

                generique

                if errorMessage != nil, !loading {
                    DetailLoadFailure(
                        message: String(localized: "On n'a pas pu charger ce film.", bundle: .app),
                        retry: { Task { await loadDetail() } }
                    )
                }

                if let connection = galleryConnection {
                    remark(connection)
                }

                watchSection
                synopsisSection

                if let cast = detail?.credits?.cast, !cast.isEmpty {
                    castSection(cast)
                }
            }
            .padding(.bottom, 32)
        }
        .coordinateSpace(name: "fiche")
        .onPreferenceChange(HeroOffsetKey.self) { scrollOffset = $0 }
        .ignoresSafeArea(edges: .top)
        .scrollIndicators(.hidden)
    }

    // MARK: - Le héros

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: heroFrameHeight)
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
                            .planFont(12)
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
        .frame(height: heroFrameHeight)
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
                        .planFont(11)
                        .foregroundStyle(Ink.ink2)
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
        // Le nombre passe en `%@`, formaté : le catalogue ne peut pas en tirer le pluriel.
        if count == 1 { return String(localized: "/ 10 · 1 vote", bundle: .app) }
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
                .planFont(13)
                .foregroundStyle(Ink.ink2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Metrics.margin)
        .padding(.top, 18)
        .accessibilityElement(children: .combine)
    }

    private var galleryConnection: String? {
        // Sans le film lui-même : déjà en galerie, il se comptait, et un
        // 4ᵉ drame devenait le 5ᵉ.
        let gallery = libraryStore.galleryItems.filter { $0.id != displayItem.id }
        guard gallery.count >= 3 else { return nil }

        // Le réalisateur n'est pas stocké dans les entrées de galerie : le seul
        // recoupement possible sans appel réseau supplémentaire est le genre,
        // affiné par la décennie quand elle est connue.
        guard let genreID = displayItem.genreIds.first else { return nil }
        let genreName = detail?.genreNames?.first?.lowercased()

        // Le rang (« 4ᵉ drame de ta galerie ») ne vaut que pour un film qui y
        // est : avant le « Vu », il annonçait une place que le film n'avait pas.
        let isSeen = currentStatus == .seen

        if let decade = decadeOfItem {
            let sameVein = gallery.filter { entry in
                entry.genreIds.contains(genreID) && decadeOf(entry.releaseDate) == decade
            }.count
            if sameVein >= 2, !isSeen {
                return String(localized: "Tu as déjà vu \(sameVein) films de ce genre sortis dans les années \(decade).", bundle: .app)
            }
            if sameVein >= 2 {
                let rank = Self.ordinal(sameVein + 1)
                if let genreName {
                    return String(localized: "\(rank) \(genreName) des années \(decade) dans ta galerie.", bundle: .app)
                }
                return String(localized: "\(rank) film de ce genre et de cette décennie dans ta galerie.", bundle: .app)
            }
        }

        let sameGenre = gallery.filter { $0.genreIds.contains(genreID) }.count
        guard sameGenre >= 3 else { return nil }
        if isSeen, let genreName {
            return String(localized: "\(Self.ordinal(sameGenre + 1)) \(genreName) de ta galerie.", bundle: .app)
        }
        return String(localized: "Tu as déjà \(sameGenre) films de ce genre dans ta galerie.", bundle: .app)
    }

    /// Le rang, fabriqué dans le code : le suffixe ne se laisse pas écrire
    /// dans le catalogue. « 3ᵉ » en français ; en anglais 3rd, 21st, 22nd,
    /// que la règle « th » du catalogue écrivait 3th, 21th, 22th.
    private static func ordinal(_ n: Int) -> String {
        guard AppLanguage.current == .english else { return "\(n)ᵉ" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        formatter.locale = Locale(identifier: "en_US")
        return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
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
    /// Tes plateformes d'abord, les autres en retrait — mais jamais rien de
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
                        .planFont(9, weight: .semibold)
                        .foregroundStyle(Ink.ink2)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Ink.ground3)
                }
            }
            .frame(width: 42, height: 42)
            .clipShape(RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                    .strokeBorder(isMine ? Ink.ink : Ink.rule, lineWidth: 1)
            )
            // Retenue : pleine saturation. Hors de tes plateformes : en retrait. Le même
            // couple que dans les réglages, pour le même objet.
            .opacity(isMine ? 1 : 0.4)
            .saturation(isMine ? 1 : 0.25)
        }
        .buttonStyle(PressableScaleStyle(scale: 0.92))
        .accessibilityLabel(provider.providerName)
        .accessibilityValue(isMine
                            ? String(localized: "Sur tes plateformes", bundle: .app)
                            : String(localized: "Hors de tes plateformes", bundle: .app))
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
                    .planFont(14)
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
                    // Par position : un même acteur peut tenir plusieurs rôles.
                    ForEach(Array(cast.enumerated()), id: \.offset) { _, member in
                        VStack(spacing: 8) {
                            Group {
                                if let url = member.profileURL {
                                    PosterImageView(url: url)
                                } else {
                                    Ink.ground3
                                }
                            }
                            .frame(width: 56, height: 56)
                            .clipShape(Circle())
                            .overlay(Circle().strokeBorder(Ink.rule, lineWidth: 1))

                            VStack(spacing: 2) {
                                Text(member.name)
                                    .planFont(10.5, weight: .medium)
                                    .foregroundStyle(Ink.ink)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)

                                if let character = member.character, !character.isEmpty {
                                    Text(character)
                                        .planFont(9.5)
                                        .foregroundStyle(Ink.ink2)
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

    /// **Le cœur de l'écran.** Il dit où est le film, puis ce qu'on peut en
    /// faire, et rien d'autre.
    ///
    /// L'ancien plancher posait « Vu » et « À voir » côte à côte, à égalité,
    /// et rien ne disait qu'ils rangeaient le film dans deux endroits qui
    /// s'excluent, ni lequel il occupait. Désormais :
    ///
    /// - une ligne nomme l'endroit (« Dans ta watchlist », « Vu, dans ta
    ///   galerie ») et porte le geste inverse, écrit en toutes lettres ;
    /// - sous elle, l'action suivante, une seule, au plein : « Je l'ai vu »
    ///   pour un film en attente, « Recommander à un ami » pour un film vu.
    ///   Recommander devient l'action principale d'un film vu : c'est ce
    ///   qu'on peut encore en faire, et un bouton-icône ne le disait pas.
    private var decisionFloor: some View {
        VStack(spacing: 0) {
            PlanEdge()

            VStack(alignment: .leading, spacing: 10) {
                if currentStatus != .none {
                    placementLine
                        .transition(.opacity)
                }
                actionRow
            }
            .padding(.horizontal, Metrics.margin)
            .padding(.top, 12)
            .padding(.bottom, 10)
        }
        .background(Ink.ground)
        .animation(Metrics.shift, value: currentStatus)
        .animation(Metrics.shift, value: pendingTarget)
        .alert(
            String(localized: "Remettre dans ta watchlist", bundle: .app),
            isPresented: $confirmsBackToWatchlist
        ) {
            Button(String(localized: "Remettre", bundle: .app)) { moveBackToWatchlist() }
            Button(String(localized: "Annuler", bundle: .app), role: .cancel) {}
        } message: {
            Text("Le film quitte ta galerie, et ton coup de cœur avec lui.", bundle: .app)
        }
    }

    /// Où est le film, et le chemin du retour. Le point dit la même chose
    /// que partout : plein pour « vu », creux pour « prévu ». Quand les deux
    /// ne tiennent pas sur une ligne (petit écran, texte agrandi), le lien
    /// passe dessous plutôt que de se tronquer.
    private var placementLine: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 10) {
                placementLabel
                Spacer(minLength: 8)
                placementReturn
            }
            VStack(alignment: .leading, spacing: 4) {
                placementLabel
                placementReturn
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var placementLabel: some View {
        HStack(alignment: .center, spacing: 10) {
            Group {
                if currentStatus == .seen { PlanLight() } else { PlanLightOutline() }
            }
            .accessibilityHidden(true)

            Text(currentStatus == .seen
                 ? String(localized: "Vu, dans ta galerie", bundle: .app)
                 : String(localized: "Dans ta watchlist", bundle: .app))
                .planFont(13)
                .foregroundStyle(Ink.ink2)
                .fixedSize()
        }
    }

    @ViewBuilder
    private var placementReturn: some View {
        if isPending, pendingTarget != .seen {
            CinechillSpinner(size: 13)
                .frame(height: 28)
        } else {
            Button {
                Haptics.impact(.light)
                if currentStatus == .seen {
                    // Le coup de cœur part avec la galerie : on le dit
                    // avant, seulement quand il y en a un à perdre.
                    if libraryStore.isLoved(displayItem) {
                        confirmsBackToWatchlist = true
                    } else {
                        moveBackToWatchlist()
                    }
                } else {
                    libraryStore.removeFromWatchlist(displayItem)
                }
            } label: {
                Text(currentStatus == .seen
                     ? String(localized: "Remettre dans ma watchlist", bundle: .app)
                     : String(localized: "Retirer", bundle: .app))
                    .planFont(13, weight: .medium)
                    .foregroundStyle(Ink.ink)
                    .fixedSize()
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Ink.ruleSet).frame(height: 1).offset(y: 2)
                    }
                    .frame(minHeight: 28)
                    // 44 pt de cible autour d'un lien de 13 pt.
                    .contentShape(Rectangle().inset(by: -8))
            }
            .buttonStyle(PressableScaleStyle(scale: 0.96))
            .disabled(isPending)
            .accessibilityHint(currentStatus == .seen
                               ? String(localized: "Le film quitte ta galerie", bundle: .app)
                               : "")
        }
    }

    @ViewBuilder
    private var actionRow: some View {
        switch currentStatus {
        case .none:
            HStack(spacing: Metrics.gutter) {
                DetailFloorButton(
                    title: String(localized: "Je l'ai vu", bundle: .app),
                    style: .line,
                    isWaiting: pendingTarget == .seen
                ) { markSeen() }
                DetailFloorButton(
                    title: String(localized: "Je veux le voir", bundle: .app),
                    style: .line,
                    isWaiting: pendingTarget == .toWatch
                ) {
                    Haptics.impact(.medium)
                    libraryStore.addToWatchlist(displayItem)
                }
            }
            .disabled(isPending)

        case .toWatch:
            DetailFloorButton(
                title: String(localized: "Je l'ai vu", bundle: .app),
                style: .paper,
                isWaiting: pendingTarget == .seen
            ) { markSeen() }
            .disabled(isPending)

        case .seen:
            // Le coup de cœur et la recommandation n'existent que pour un film
            // vu : « on n'aime et on ne recommande que ce qu'on a vu » n'est
            // jamais énoncé, c'est simplement vrai à l'écran.
            HStack(spacing: Metrics.gutter) {
                loveButton
                recommendButton
            }
        }
    }

    /// L'action principale d'un film vu : le seul aplat clair du plancher,
    /// avec son verbe. L'icône seule ne se lisait pas comme « recommander ».
    private var recommendButton: some View {
        Button {
            Haptics.impact(.light)
            showComposer = true
        } label: {
            HStack(spacing: 9) {
                CinechillHallIconView(.recommander)
                    .frame(width: 17, height: 17)
                Text("Recommander à un ami", bundle: .app)
                    .planFont(14.5, weight: .semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(Ink.ground)
            .frame(maxWidth: .infinity)
            .frame(minHeight: Metrics.control)
            .background(Ink.paper, in: RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous))
        }
        .buttonStyle(PressableScaleStyle(scale: 0.97))
        .transition(.opacity)
    }

    /// Le coup de cœur, à côté de la recommandation. Le cœur tracé dit « rien
    /// déclaré », le cœur plein en cramoisi dit « adoré » : c'est le
    /// remplissage qui porte l'état, la teinte (une couleur de données, celle
    /// de l'artéfact du Cœur) ne fait que l'appuyer.
    private var loveButton: some View {
        let loved = libraryStore.isLoved(displayItem)
        let isPending = libraryStore.isLovePending(displayItem)

        return Button {
            Haptics.impact(.light, intensity: loved ? 0.5 : 0.8)
            libraryStore.setLove(displayItem, loved: !loved)
        } label: {
            // Pendant l'écriture le faisceau prend la place du cœur : le cœur
            // ne change qu'une fois Firestore revenu.
            Group {
                if isPending {
                    CinechillSpinner(size: 14)
                } else {
                    DetailHeartShape()
                        .stroke(
                            loved ? Color(hex: 0xC25562) : Ink.ink,
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                        )
                        .background(
                            DetailHeartShape()
                                .fill(loved ? Color(hex: 0xC25562) : .clear)
                        )
                        .frame(width: 18, height: 16)
                }
            }
            .frame(width: 52, height: Metrics.control)
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                    .strokeBorder(Ink.ruleSet, lineWidth: 1)
            )
        }
        .buttonStyle(PressableScaleStyle(scale: 0.94))
        // Un second tap pendant l'écriture en lançait une seconde, contraire,
        // dont personne ne contrôle l'ordre d'arrivée.
        .disabled(isPending)
        .transition(.opacity)
        .animation(Metrics.shift, value: loved)
        .animation(Metrics.shift, value: isPending)
        .accessibilityLabel(
            loved
                ? String(localized: "Retirer le coup de cœur", bundle: .app)
                : String(localized: "Coup de cœur", bundle: .app)
        )
        .accessibilityValue(isPending ? String(localized: "Enregistrement…", bundle: .app) : "")
    }

    /// L'écriture en cours, s'il y en a une. Tout le plancher se fige
    /// pendant ce temps : deux écritures concurrentes sur le même film
    /// arriveraient dans un ordre que personne ne contrôle.
    private var pendingTarget: LibraryStore.MediaStatus? {
        libraryStore.pendingStatus(for: displayItem)
    }

    private var isPending: Bool { pendingTarget != nil }

    private func markSeen() {
        Haptics.impact(.medium)
        // La fiche est le seul écran à connaître le réalisateur et la saga :
        // c'est ici qu'ils entrent en galerie, pour les badges « Signature »
        // et « L'Intégrale ».
        libraryStore.addToGallery(
            displayItem,
            director: detail?.director,
            collectionID: detail?.collectionID,
            collectionTotal: detail?.collectionCount
        )
        offerSagaIfAny()
    }

    private func moveBackToWatchlist() {
        libraryStore.addToWatchlist(displayItem)
    }

    /// « Tu l'as vu. Et le reste de la saga ? » La question ne se pose qu'une
    /// fois, et seulement si la saga compte au moins deux autres opus — sans
    /// quoi la feuille s'ouvrirait pour ne rien proposer.
    private func offerSagaIfAny() {
        guard !hasOfferedSaga,
              let collectionID = detail?.collectionID,
              (detail?.collectionCount ?? 0) >= 2 else { return }
        hasOfferedSaga = true
        let offer = SagaOffer(
            source: .collection(collectionID),
            originID: displayItem.id,
            title: displayItem.title
        )
        let owned = Set(libraryStore.galleryItems.map(\.id))
        // Ne s'ouvre que s'il reste un autre opus à cocher.
        Task { sagaOffer = await offer.prepared(excluding: owned) }
    }

    // MARK: - Confirmation

    @ViewBuilder
    private var outcomeBanner: some View {
        if let outcome {
            SuggestionOutcomeBanner(outcome: outcome)
        }
    }

    // MARK: - Actions

    /// Une propriété typée, comme sur les fiches série et saison : un ternaire
    /// mêlant `nil` et une méthode isolée faisait renoncer le vérificateur de types.
    private var trailerAction: (() -> Void)? {
        guard detail?.trailerKey != nil else { return nil }
        return { openTrailer() }
    }

    private func openTrailer() {
        guard let key = detail?.trailerKey else { return }
        withAnimation(.easeOut(duration: 0.2)) { playingTrailer = key }
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

    /// La question du jour, s'il y en a une. Une erreur ne se montre pas : la
    /// question attendra demain, la fiche n'a rien perdu.
    ///
    /// Seulement si l'on est encore en haut de la fiche : posé au-dessus de ce
    /// qu'on est en train de lire, le bloc ferait sauter le texte. Le serveur
    /// n'est pas appelé dans ce cas, et la question n'est pas perdue pour la
    /// journée.
    private func askDarker() async {
        guard scrollOffset > -Self.askDarkerScrollSlack,
              let question = try? await cineMatchClient.darkerQuestion(),
              scrollOffset > -Self.askDarkerScrollSlack
        else { return }
        withAnimation(Metrics.unfold) { darkerQuestion = question }
    }

    /// Le défilement toléré pour poser la question : un geste involontaire,
    /// pas une lecture.
    private static let askDarkerScrollSlack: CGFloat = 40

    private func loadDetail() async {
        loading = true
        errorMessage = nil
        defer { loading = false }
        let client = BackendDetailClient()
        do {
            detail = try await client.itemDetails(id: item.tmdbId, mediaType: item.mediaType)
        } catch is CancellationError {
            return
        } catch {
            // Le texte affiché est fixe ; on garde la cause pour le débogage.
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

// MARK: - Statut (miroir de LibraryStore)

private enum DetailStatus {
    case toWatch, seen, none
}
