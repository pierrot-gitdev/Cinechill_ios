import SwiftUI

struct ItemDetailView: View {
    let item: MediaItem

    @EnvironmentObject private var libraryStore: LibraryStore
    @Environment(\.openURL) private var openURL

    @State private var detail: TMDBDetailResponse?
    @State private var loading = true
    @State private var errorMessage: String?
    @State private var showStatusPicker = false

    private var displayItem: MediaItem {
        detail.map { $0.asMediaItem(mediaType: item.mediaType) } ?? item
    }

    private var currentStatus: MediaStatus {
        if libraryStore.isInGallery(displayItem) { return .seen }
        if libraryStore.isInWatchlist(displayItem) { return .toWatch }
        return .none
    }

    private var statusLabel: String {
        switch currentStatus {
        case .seen: return "Vu"
        case .toWatch: return "À voir"
        case .none: return "Ajouter"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                statusRatingRow
                if let d = detail {
                    watchOnlineSection(d)
                }
                synopsisSection
                if let cast = detail?.credits?.cast, !cast.isEmpty {
                    castSection(cast)
                }
            }
            .padding()
        }
        .navigationTitle(displayItem.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadDetail() }
        .confirmationDialog("Statut", isPresented: $showStatusPicker) {
            Button("À voir") { libraryStore.addToWatchlist(displayItem) }
            Button("Vu") { libraryStore.addToGallery(displayItem) }
            if currentStatus != .none {
                Button("Retirer de la liste", role: .destructive) {
                    if currentStatus == .seen { libraryStore.removeFromGallery(displayItem) }
                    else { libraryStore.removeFromWatchlist(displayItem) }
                }
            }
            Button("Annuler", role: .cancel) {}
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(alignment: .top, spacing: 14) {
            posterView
            VStack(alignment: .leading, spacing: 6) {
                Text(detail?.displayTitle ?? item.title)
                    .font(.title3.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)

                if let director = detail?.director {
                    Text("De \(director)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                let year = detail?.displayYear ?? item.displayYear
                let genre = detail?.firstGenre
                Text([year, genre].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if loading {
                    ProgressView().scaleEffect(0.8).padding(.top, 4)
                }

                if let error = errorMessage {
                    Text(error).font(.caption).foregroundStyle(.red)
                }

                Spacer(minLength: 8)

                if detail?.trailerKey != nil {
                    trailerButton
                }
            }
        }
    }

    private var posterView: some View {
        Group {
            if let url = detail?.posterDetailURL ?? item.posterURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        Color.secondary.opacity(0.25)
                    }
                }
            } else {
                Color.secondary.opacity(0.25)
            }
        }
        .frame(width: 110, height: 165)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var trailerButton: some View {
        Button {
            openTrailer()
        } label: {
            Label("Bande-annonce", systemImage: "play.fill")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(.primary)
    }

    // MARK: - Status + Rating

    private var statusRatingRow: some View {
        HStack(spacing: 10) {
            Button {
                showStatusPicker = true
            } label: {
                HStack(spacing: 6) {
                    Text(statusLabel)
                        .font(.subheadline.weight(.semibold))
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(statusTint)

            if let rating = detail?.voteAverage ?? item.voteAverage {
                HStack(spacing: 5) {
                    Image(systemName: "star.fill")
                    Text(String(format: "%.1f/10", rating))
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .foregroundStyle(.white)
            }
        }
    }

    private var statusTint: Color {
        switch currentStatus {
        case .seen: return .green
        case .toWatch: return .accentColor
        case .none: return .primary
        }
    }

    // MARK: - Watch Online

    @ViewBuilder
    private func watchOnlineSection(_ d: TMDBDetailResponse) -> some View {
        let providers = (d.watchProvidersFR ?? []).filter {
            libraryStore.preferredPlatformIDs.contains(String($0.providerID))
        }
        if !providers.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Regarder en ligne")
                    .font(.headline)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(providers, id: \.providerID) { provider in
                            Button {
                                openProvider(provider)
                            } label: {
                                providerLogo(provider)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func providerLogo(_ provider: TMDBDetailWatchProviderItem) -> some View {
        Group {
            if let url = provider.logoURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit()
                    default:
                        Color.secondary.opacity(0.2)
                    }
                }
            } else {
                Text(provider.providerName)
                    .font(.caption2)
                    .padding(6)
                    .background(Color.secondary.opacity(0.15))
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Synopsis

    @ViewBuilder
    private var synopsisSection: some View {
        if let text = detail?.overview ?? item.overview, !text.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Synopsis")
                    .font(.headline)
                Text(text)
                    .font(.body)
                    .foregroundStyle(.primary)
            }
        }
    }

    // MARK: - Cast

    private func castSection(_ cast: [TMDBDetailCastMember]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Casting")
                .font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(cast, id: \.name) { member in
                        VStack(spacing: 6) {
                            Group {
                                if let url = member.profileURL {
                                    AsyncImage(url: url) { phase in
                                        switch phase {
                                        case .success(let image):
                                            image.resizable().scaledToFill()
                                        default:
                                            personPlaceholder
                                        }
                                    }
                                } else {
                                    personPlaceholder
                                }
                            }
                            .frame(width: 64, height: 64)
                            .clipShape(Circle())

                            Text(member.name)
                                .font(.caption.weight(.semibold))
                                .multilineTextAlignment(.center)
                                .lineLimit(2)

                            if let character = member.character, !character.isEmpty {
                                Text(character)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                            }
                        }
                        .frame(width: 72)
                    }
                }
                .padding(.bottom, 4)
            }
        }
    }

    private var personPlaceholder: some View {
        Circle()
            .fill(Color.secondary.opacity(0.2))
            .overlay(Image(systemName: "person.fill").foregroundStyle(.secondary))
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

    private func openProvider(_ provider: TMDBDetailWatchProviderItem) {
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

// MARK: - Status enum (miroir de LibraryStore)

private enum MediaStatus {
    case toWatch, seen, none
}
