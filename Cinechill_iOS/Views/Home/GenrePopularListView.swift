import SwiftUI

/// Un genre, ouvert en grille — « Le Rayon ».
///
/// C'est l'écran qui n'avait jamais été repris : `ProgressView`, deux
/// `ContentUnavailableView`, une carte à pastilles vertes et bleues qu'aucun
/// autre écran n'employait, et `AsyncImage` qui contournait le cache d'affiches.
///
/// Trois décisions le remettent dans l'application :
///
/// - **Trois colonnes, pas deux.** Neuf affiches par écran au lieu de quatre.
///   Sur un écran de balayage, la densité *est* la fonction : c'est le nombre de
///   titres qu'on écarte d'un coup d'œil qui décide de son utilité.
/// - **Le filtre des plateformes descend dans le contenu**, avec les logos
///   actifs visibles. On sait ce qu'on filtre sans ouvrir de feuille — et la
///   feuille qui doublonnait les réglages a pu disparaître.
/// - **`PosterCell` remplace `ContentCardView`.** Un composant retiré vaut mieux
///   qu'un composant repeint.
struct GenrePopularListView: View {
    let category: HomeBrowseCategory
    let homeModel: HomeViewModel

    @EnvironmentObject private var libraryStore: LibraryStore
    @Environment(MediaCatalog.self) private var catalog

    @State private var items: [MediaItem] = []
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var showPlatforms = false

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: Metrics.gutter),
        count: 3
    )

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                platformRow

                if loading {
                    loadingState
                } else if let errorMessage {
                    PlanEmptyState(
                        icon: .salle,
                        title: String(localized: "Chargement impossible", bundle: .app),
                        message: errorMessage,
                        actionTitle: String(localized: "Réessayer", bundle: .app),
                        action: { Task { await load() } }
                    )
                    .padding(.top, 60)
                } else if items.isEmpty {
                    PlanEmptyState(
                        icon: .chercher,
                        title: String(localized: "Rien dans cette catégorie", bundle: .app),
                        message: emptyMessage,
                        actionTitle: hasPlatformFilter ? String(localized: "Voir sans filtre", bundle: .app) : nil,
                        action: hasPlatformFilter ? { libraryStore.setPreferredPlatforms([]) } : nil
                    )
                    .padding(.top, 60)
                } else {
                    grid
                }
            }
            .padding(.bottom, 28)
        }
        .background(Ink.ground)
        .safeAreaInset(edge: .top) {
            PlanHeader(category.title) {
                if !items.isEmpty {
                    PlanHeaderCount(value: items.count.formatted())
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showPlatforms) {
            PlatformPickerSheet()
                .environmentObject(libraryStore)
                .environment(catalog)
        }
        .task(id: category.id) { await load() }
        .task(id: libraryStore.preferredPlatformIDs) {
            guard !items.isEmpty || errorMessage != nil else { return }
            await load()
        }
    }

    // MARK: - Le filtre, en ligne

    /// Une ligne, pas une feuille : on voit ce qu'on filtre sans rien ouvrir, et
    /// le réglage reste celui des réglages — un seul, à un seul endroit.
    private var platformRow: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                Text(selectedPlatforms.isEmpty
                     ? String(localized: "Toutes plateformes", bundle: .app)
                     : String(localized: "Chez vous", bundle: .app))
                    .planLabel()
                    .foregroundStyle(Ink.ink3)

                if !selectedPlatforms.isEmpty {
                    HStack(spacing: 5) {
                        ForEach(selectedPlatforms.prefix(4)) { platform in
                            platformLogo(platform)
                        }
                        if selectedPlatforms.count > 4 {
                            Text(verbatim: "+\(selectedPlatforms.count - 4)")
                                .font(.system(size: 10))
                                .monospacedDigit()
                                .foregroundStyle(Ink.ink3)
                        }
                    }
                }

                Spacer(minLength: 8)

                Button {
                    showPlatforms = true
                } label: {
                    Text("Modifier", bundle: .app)
                        .font(.system(size: 12))
                        .foregroundStyle(Ink.ink2)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(Ink.ruleSet).frame(height: 1).offset(y: 2)
                        }
                        .contentShape(Rectangle().inset(by: -10))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Modifier mes plateformes", bundle: .app))
            }
            .frame(height: 44)
            .padding(.horizontal, Metrics.margin)

            PlanEdge().padding(.horizontal, Metrics.margin)
        }
    }

    private var selectedPlatforms: [StreamingPlatform] {
        catalog.platforms.filter { libraryStore.preferredPlatformIDs.contains($0.id) }
    }

    private var hasPlatformFilter: Bool {
        !libraryStore.preferredPlatformIDs.isEmpty
    }

    private func platformLogo(_ platform: StreamingPlatform) -> some View {
        Group {
            if let url = platform.logoURL {
                PosterImageView(url: url)
            } else {
                Text(platform.shortLabel.prefix(2))
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Ink.ink2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(hex: 0x151B23))
            }
        }
        .frame(width: 20, height: 20)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                .strokeBorder(Ink.rule, lineWidth: 1)
        )
        .accessibilityLabel(platform.name)
    }

    // MARK: - La grille

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(items) { item in
                NavigationLink(value: item) {
                    PosterCell(
                        posterPath: item.posterPath,
                        title: item.title,
                        inGallery: libraryStore.isInGallery(item),
                        inWatchlist: libraryStore.isInWatchlist(item)
                    )
                }
                .buttonStyle(PressableScaleStyle(scale: 0.95))
            }
        }
        .padding(.horizontal, Metrics.margin)
        .padding(.top, 18)
    }

    private var loadingState: some View {
        VStack(spacing: 14) {
            CinechillSpinner(size: 30)
            Text("Chargement…", bundle: .app)
                .font(.system(size: 12.5))
                .foregroundStyle(Ink.ink3)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 90)
    }

    private var emptyMessage: String {
        hasPlatformFilter
            ? String(localized: "Aucun film de cette catégorie n'est disponible sur vos plateformes en ce moment.", bundle: .app)
            : String(localized: "Essayez une autre catégorie.", bundle: .app)
    }

    private func load() async {
        loading = true
        errorMessage = nil
        defer { loading = false }
        do {
            items = try await homeModel.loadTopForCategory(category)
        } catch {
            if error is CancellationError { return }
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            items = []
        }
    }
}
