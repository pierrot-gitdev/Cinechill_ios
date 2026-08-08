import SwiftUI

/// La fiche film — « La Fiche ».
///
/// Point d'arrivée de tous les autres écrans. L'affiche et le backdrop portent
/// l'écran ; le statut y parle le même vocabulaire que le deck (vu / à voir),
/// et le bloc « Dans votre galerie » relie le film à votre collection plutôt
/// que d'en faire une page TMDB de plus.
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

    private var displayItem: MediaItem {
        detail.map { $0.asMediaItem(mediaType: item.mediaType) } ?? item
    }

    private var currentStatus: DetailStatus {
        if libraryStore.isInGallery(displayItem) { return .seen }
        if libraryStore.isInWatchlist(displayItem) { return .toWatch }
        return .none
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                hero
                factsLine
                decisionBar

                if let connection = galleryConnection {
                    connectionCard(connection)
                }

                watchSection
                synopsisSection

                if let cast = detail?.credits?.cast, !cast.isEmpty {
                    castSection(cast)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 20)
                }
            }
            .padding(.bottom, 32)
        }
        .background(Color(.systemBackground))
        .ignoresSafeArea(edges: .top)
        .navigationBarHidden(true)
        .overlay(alignment: .topLeading) { backButton }
        .overlay(alignment: .bottom) { outcomeBanner }
        .sheet(isPresented: $showComposer) {
            SuggestionComposerSheet(item: displayItem) { result in
                guard !result.isSilent else { return }
                withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                    outcome = result
                }
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

    // MARK: - Confirmation

    @ViewBuilder
    private var outcomeBanner: some View {
        if let outcome {
            SuggestionOutcomeBanner(outcome: outcome)
        }
    }

    // MARK: - Hero

    /// Le `backdrop_path` était déjà renvoyé par le backend et n'était affiché
    /// nulle part : il devient l'image d'ouverture, avec l'affiche posée dessus.
    private var hero: some View {
        ZStack(alignment: .bottom) {
            // `Color.clear` fixe la boîte, l'image est posée en `overlay` : un
            // overlay ne participe jamais au calcul de taille du parent. Sans
            // ça, une image en `scaledToFill` impose sa largeur à toute la vue,
            // `.clipped()` ne rognant que le dessin, pas la mise en page.
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: 260)
                .overlay { backdrop }
                .clipped()
                .overlay(scrim)

            HStack(alignment: .bottom, spacing: 14) {
                PosterTile(
                    posterPath: detail?.posterPath ?? item.posterPath,
                    title: displayItem.title,
                    width: 84,
                    cornerRadius: 10
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(displayItem.title)
                        .font(.system(size: 24, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(3)
                        .minimumScaleFactor(0.7)
                        .shadow(color: .black.opacity(0.5), radius: 8, y: 2)

                    if let tagline = detail?.tagline, !tagline.isEmpty {
                        Text(tagline)
                            .font(.system(size: 11))
                            .italic()
                            .foregroundStyle(.white.opacity(0.82))
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 14)
        }
        .frame(height: 260)
        .overlay(alignment: .center) { trailerButton }
    }

    @ViewBuilder
    private var backdrop: some View {
        if let url = detail?.backdropURL {
            PosterImageView(url: url)
        } else {
            LinearGradient(
                colors: [.indigo.opacity(0.55), .pink.opacity(0.35), Color(.systemBackground)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var scrim: some View {
        LinearGradient(
            stops: [
                .init(color: .black.opacity(0.35), location: 0),
                .init(color: .black.opacity(0.15), location: 0.35),
                .init(color: .black.opacity(0.72), location: 0.8),
                .init(color: Color(.systemBackground), location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var trailerButton: some View {
        if detail?.trailerKey != nil {
            Button(action: openTrailer) {
                Image(systemName: "play.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.5), lineWidth: 1.5))
                    .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
            }
            .buttonStyle(PressableScaleStyle(scale: 0.9))
            .offset(y: -22)
            .accessibilityLabel("Voir la bande-annonce")
        }
    }

    private var backButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Color.black.opacity(0.35), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.2), lineWidth: 1))
        }
        .buttonStyle(PressableScaleStyle(scale: 0.9))
        .padding(.leading, 16)
        .padding(.top, 54)
        .accessibilityLabel("Retour")
    }

    // MARK: - Faits

    private var factsLine: some View {
        HStack(spacing: 0) {
            Text(facts)
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            if loading {
                CinechillSpinner(size: 15)
            }

            if let rating = detail?.voteAverage ?? item.voteAverage {
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.yellow)
                    Text(String(format: "%.1f", rating))
                        .font(.system(size: 12.5, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                }
            }
        }
        .padding(.horizontal, 20)
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

    // MARK: - Décision

    /// Trois boutons explicites plutôt qu'un menu déroulant : toute l'app dit
    /// déjà « vu / à voir », la fiche était le seul écran à parler autrement.
    private var decisionBar: some View {
        HStack(spacing: 8) {
            decisionButton(.seen, label: "Vu", icon: "checkmark", tint: .green)
            decisionButton(.toWatch, label: "À voir", icon: "bookmark.fill", tint: .blue)

            // « Recommander » n'apparaît que si le film est vu : la règle
            // « on ne recommande que ce qu'on a vu » n'est jamais énoncée,
            // elle est simplement vraie à l'écran. Le cyan de l'identité, et
            // non l'indigo des décisions — c'est une action d'un autre ordre.
            if currentStatus == .seen {
                Button {
                    Haptics.impact(.light)
                    showComposer = true
                } label: {
                    CinechillHallIconView(.recommander)
                        .frame(width: 17, height: 17)
                        .foregroundStyle(CinechillPalette.light)
                        .frame(width: 44, height: 40)
                        .background(
                            CinechillPalette.light.opacity(0.15),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(CinechillPalette.light.opacity(0.55), lineWidth: 1.5)
                        )
                }
                .buttonStyle(PressableScaleStyle(scale: 0.94))
                .transition(.scale.combined(with: .opacity))
                .accessibilityLabel("Recommander à un ami")
            }

            if currentStatus != .none {
                Button {
                    Haptics.impact(.light)
                    if currentStatus == .seen {
                        libraryStore.removeFromGallery(displayItem)
                    } else {
                        libraryStore.removeFromWatchlist(displayItem)
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 40)
                        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(PressableScaleStyle(scale: 0.94))
                .transition(.scale.combined(with: .opacity))
                .accessibilityLabel("Retirer de mes listes")
            }
        }
        .padding(.horizontal, 20)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: currentStatus)
    }

    private func decisionButton(
        _ status: DetailStatus, label: String, icon: String, tint: Color
    ) -> some View {
        let isOn = currentStatus == status
        return Button {
            Haptics.impact(.medium)
            if status == .seen {
                // La fiche est le seul écran à connaître le réalisateur et la
                // saga : c'est ici qu'ils entrent en galerie, pour les badges
                // « Signature » et « L'Intégrale ».
                libraryStore.addToGallery(
                    displayItem,
                    director: detail?.director,
                    collectionID: detail?.collectionID,
                    collectionTotal: detail?.collectionCount
                )
            } else {
                libraryStore.addToWatchlist(displayItem)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                Text(label)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
            }
            .foregroundStyle(isOn ? tint : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(
                isOn ? tint.opacity(0.15) : Color(.tertiarySystemFill),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isOn ? tint : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(PressableScaleStyle(scale: 0.96))
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }

    // MARK: - Lien avec la galerie

    /// Ce qui distingue la fiche d'une page TMDB : elle sait ce que vous avez
    /// déjà vu. Calculé en local, sans un appel réseau de plus.
    private var galleryConnection: String? {
        let gallery = libraryStore.galleryItems
        guard gallery.count >= 3 else { return nil }

        // Le réalisateur n'est pas stocké dans les entrées de galerie : le seul
        // recoupement possible sans appel réseau supplémentaire est le genre,
        // affiné par la décennie quand elle est connue.
        guard let genreID = displayItem.genreIds.first else { return nil }

        if let decade = decadeOfItem {
            let sameVein = gallery.filter { entry in
                entry.genreIds.contains(genreID) && decadeOf(entry.releaseDate) == decade
            }.count
            if sameVein >= 2 {
                return "Vous avez déjà \(sameVein) films du même genre sur cette décennie."
            }
        }

        let sameGenre = gallery.filter { $0.genreIds.contains(genreID) }.count
        guard sameGenre >= 3 else { return nil }
        return "Vous avez déjà \(sameGenre) films de ce genre dans votre galerie."
    }

    private var decadeOfItem: Int? {
        decadeOf(detail?.releaseDate ?? item.releaseDate)
    }

    private func decadeOf(_ releaseDate: String?) -> Int? {
        guard let releaseDate, releaseDate.count >= 4,
              let year = Int(releaseDate.prefix(4)) else { return nil }
        return year / 10 * 10
    }

    private func connectionCard(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 13))
                .foregroundStyle(.indigo)

            Text(text)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.indigo.opacity(0.09), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.indigo.opacity(0.22), lineWidth: 1)
        )
        .padding(.horizontal, 20)
    }

    // MARK: - Où le voir

    /// Vos plateformes d'abord, les autres en retrait — mais jamais rien de
    /// caché : l'ancienne version masquait toute la section quand vous n'étiez
    /// abonné à aucune, alors que l'information existait.
    @ViewBuilder
    private var watchSection: some View {
        let all = detail?.watchProvidersFR ?? []
        if !all.isEmpty {
            let mine = all.filter { libraryStore.preferredPlatformIDs.contains(String($0.providerID)) }
            let others = all.filter { !libraryStore.preferredPlatformIDs.contains(String($0.providerID)) }

            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("OÙ LE VOIR")

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(mine, id: \.providerID) { provider in
                            providerButton(provider, isMine: true)
                        }

                        if !mine.isEmpty, !others.isEmpty {
                            Rectangle()
                                .fill(Color.secondary.opacity(0.25))
                                .frame(width: 1, height: 26)
                                .padding(.horizontal, 2)
                        }

                        ForEach(others, id: \.providerID) { provider in
                            providerButton(provider, isMine: false)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .scrollClipDisabled()
            }
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
                    Text(provider.providerName)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(.tertiarySystemFill))
                }
            }
            .frame(width: 46, height: 46)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isMine ? Color.indigo : Color.clear, lineWidth: 2)
            )
            .opacity(isMine ? 1 : 0.42)
            .saturation(isMine ? 1 : 0.3)
        }
        .buttonStyle(PressableScaleStyle(scale: 0.92))
        .accessibilityLabel(provider.providerName)
        .accessibilityValue(isMine ? "Dans vos abonnements" : "Hors de vos abonnements")
    }

    // MARK: - Synopsis

    @ViewBuilder
    private var synopsisSection: some View {
        if let text = detail?.overview ?? item.overview, !text.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("SYNOPSIS")
                Text(text)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .padding(.horizontal, 20)
            }
        }
    }

    // MARK: - Casting

    private func castSection(_ cast: [TMDBDetailCastMember]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("CASTING")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(cast, id: \.name) { member in
                        VStack(spacing: 6) {
                            Group {
                                if let url = member.profileURL {
                                    PosterImageView(url: url)
                                } else {
                                    personPlaceholder
                                }
                            }
                            .frame(width: 60, height: 60)
                            .clipShape(Circle())
                            .overlay(Circle().strokeBorder(Color.primary.opacity(0.07), lineWidth: 1))

                            Text(member.name)
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .multilineTextAlignment(.center)
                                .lineLimit(2)

                            if let character = member.character, !character.isEmpty {
                                Text(character)
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                            }
                        }
                        .frame(width: 70)
                    }
                }
                .padding(.horizontal, 20)
            }
            .scrollClipDisabled()
        }
    }

    private var personPlaceholder: some View {
        Circle()
            .fill(Color(.tertiarySystemFill))
            .overlay(Image(systemName: "person.fill").foregroundStyle(.secondary))
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .heavy, design: .rounded))
            .kerning(1)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 20)
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
