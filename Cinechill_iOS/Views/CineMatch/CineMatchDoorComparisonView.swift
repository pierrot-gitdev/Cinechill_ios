//
//  CineMatchDoorComparisonView.swift
//  Cinechill_iOS
//

import SwiftUI

/// Les douze comparaisons de la Porte — l'artéfact « Tes préférences ».
///
/// Il remplace les Horizons, qui comptaient des décennies et des pays : un
/// compte ne décrit rien de ce qu'on aime. Douze choix entre des films déjà vus
/// construisent un graphe de préférences avant la première proposition.
///
/// Chaque tour montre quatre films de la galerie : on garde celui qu'on
/// préfère, puis on écarte celui qu'on aime le moins, et le duel s'écrit côté
/// serveur. **« Passer » ne compte pas** : il demande quatre autres films pour
/// le même tour, parce que la Porte compte les duels réellement tranchés et
/// qu'un compteur d'écran qui avancerait sans eux mentirait.
///
/// La remesure de la porte revient à l'écran qui présente celui-ci, à la
/// fermeture, comme pour la planche des coups de cœur : chaque duel a déjà été
/// attendu avant de passer au tour suivant, donc rien n'est en route quand on
/// ferme.
struct CineMatchDoorComparisonView: View {
    private let client: any CineMatchFetching
    private let onClose: () -> Void

    /// La cible de l'artéfact, telle que le serveur la mesure.
    private static let rounds = 12

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(DoorStore.self) private var doorStore

    /// Le seuil de la Mémoire : le serveur ne compare pas une galerie plus
    /// petite, et c'est lui que l'écran vide doit nommer.
    private var memoryTarget: Int { doorStore.door.artifact(.memoire)?.target ?? 100 }

    @State private var round = 1
    @State private var films: [CineMatchGalleryFilm] = []
    @State private var shownIDs: [Int] = []
    @State private var history: [CineMatchComparison] = []
    @State private var keptID: Int?
    @State private var excludedID: Int?
    @State private var shownAt = Date()
    @State private var isLoading = false
    @State private var hasLoadedOnce = false
    @State private var errorMessage: String?

    init(client: any CineMatchFetching = BackendCineMatchClient(), onClose: @escaping () -> Void) {
        self.client = client
        self.onClose = onClose
    }

    var body: some View {
        GeometryReader { proxy in
            let isCompact = proxy.size.height < 520

            VStack(alignment: .leading, spacing: 0) {
                header

                content(isCompact: isCompact)
            }
            .padding(.horizontal, Metrics.margin)
            .padding(.top, 22)
            .padding(.bottom, 8)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
        .background(Ink.ground.ignoresSafeArea())
        .task {
            guard !hasLoadedOnce else { return }
            hasLoadedOnce = true
            await load()
        }
    }

    // MARK: - L'en-tête

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Text("Tes préférences", bundle: .app)
                    .planLabel()
                    .foregroundStyle(Color(hex: DoorArtifactKey.horizons.hue))

                Spacer(minLength: 0)

                Text(String(localized: "\(round) sur \(Self.rounds)", bundle: .app))
                    .planLabel()
                    .monospacedDigit()
                    .foregroundStyle(Ink.ink2)
                    .contentTransition(.numericText())

                Button(action: onClose) {
                    DoorCloseGlyph()
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle().inset(by: -8))
                }
                .buttonStyle(PressableScaleStyle(scale: 0.9))
                .accessibilityLabel(String(localized: "Fermer", bundle: .app))
            }

            gauge
        }
        .animation(Metrics.shift, value: round)
    }

    /// La jauge tracée de l'app, dans la teinte de l'artéfact.
    private var gauge: some View {
        let fraction = Double(round - 1) / Double(Self.rounds)
        let tint = Color(hex: DoorArtifactKey.horizons.hue)

        return GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle().fill(Ink.rule).frame(height: 1)
                Rectangle()
                    .fill(tint)
                    .frame(width: max(1, proxy.size.width * fraction), height: 1)
                if fraction > 0 {
                    Rectangle()
                        .fill(tint)
                        .frame(width: 1, height: 5)
                        .offset(x: max(0, proxy.size.width * fraction - 0.5))
                }
            }
            .frame(height: 5)
        }
        .frame(height: 5)
        .accessibilityHidden(true)
    }

    // MARK: - Le tour

    @ViewBuilder
    private func content(isCompact: Bool) -> some View {
        if let errorMessage, films.isEmpty {
            PlanEmptyState(
                title: String(localized: "Impossible de charger les films", bundle: .app),
                message: errorMessage,
                actionTitle: String(localized: "Réessayer", bundle: .app),
                action: { Task { await load() } },
                secondaryTitle: String(localized: "Fermer", bundle: .app),
                secondaryAction: onClose
            )
            .frame(maxHeight: .infinity)
        } else if films.isEmpty, !isLoading, hasLoadedOnce {
            PlanEmptyState(
                title: String(localized: "Pas assez de films vus", bundle: .app),
                message: String(
                    localized: "Ajoute d'abord \(memoryTarget) films à ta galerie pour pouvoir comparer.",
                    bundle: .app
                ),
                actionTitle: String(localized: "Fermer", bundle: .app),
                action: onClose
            )
            .frame(maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Text(
                    keptID == nil
                        ? String(localized: "Lequel tu préfères ?", bundle: .app)
                        : String(localized: "Et celui que tu aimes le moins ?", bundle: .app)
                )
                .font(.system(size: isCompact ? 20 : 24, weight: .regular, design: .serif))
                .kerning(0.1)
                .foregroundStyle(Ink.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, isCompact ? 14 : 24)
                .accessibilityAddTraits(.isHeader)

                GeometryReader { proxy in
                    if films.isEmpty {
                        CinechillSpinner(size: 26)
                            .frame(width: proxy.size.width, height: proxy.size.height)
                    } else {
                        grid(in: proxy.size)
                            .opacity(isLoading ? 0.6 : 1)
                    }
                }
                .frame(minHeight: 130)
                .padding(.top, isCompact ? 10 : 14)

                Button(action: skip) {
                    Text("Passer", bundle: .app)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Ink.ink2)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
                .disabled(isBusy || films.isEmpty)
            }
            .animation(Metrics.shift, value: keptID)
        }
    }

    private var isBusy: Bool { isLoading || excludedID != nil }

    private func grid(in size: CGSize) -> some View {
        let layout = DoorPosterLayout(size: size)
        let rows: [[Int]] = layout.columns == 2 ? [[0, 1], [2, 3]] : [[0, 1, 2, 3]]

        return VStack(spacing: layout.gap) {
            ForEach(rows, id: \.self) { row in
                HStack(alignment: .bottom, spacing: layout.gap) {
                    ForEach(row, id: \.self) { index in
                        if index < films.count {
                            tile(films[index], layout: layout)
                                .id(films[index].id)
                        } else {
                            Color.clear
                                .frame(width: layout.cellWidth, height: layout.cellHeight)
                        }
                    }
                }
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private func tile(_ film: CineMatchGalleryFilm, layout: DoorPosterLayout) -> some View {
        let isKept = keptID == film.id
        let isOut = excludedID == film.id
        let shape = RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)

        return Button {
            pick(film)
        } label: {
            VStack(spacing: DoorPosterLayout.captionSpacing) {
                PosterImageView(url: film.posterURL, contentMode: .fill)
                    .frame(width: layout.posterWidth, height: layout.posterHeight)
                    .clipShape(shape)
                    .overlay(
                        shape.strokeBorder(isKept ? Ink.light : Ink.ink.opacity(0.18), lineWidth: isKept ? 2 : 1)
                    )
                    .opacity(isOut ? 0.22 : 1)
                    .overlay(alignment: .top) {
                        if isOut {
                            Text("Écarté", bundle: .app)
                                .planLabel()
                                .foregroundStyle(Ink.ink2)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Ink.ground3, in: RoundedRectangle(cornerRadius: 2, style: .continuous))
                                .padding(.top, 6)
                                .transition(.opacity)
                        }
                    }

                Text(film.title)
                    .font(.system(size: 12))
                    .foregroundStyle(isKept ? Ink.ink : Ink.ink2)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: layout.cellWidth, height: DoorPosterLayout.caption, alignment: .top)
            }
            .frame(width: layout.cellWidth, height: layout.cellHeight, alignment: .bottom)
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.15), value: isKept)
            .animation(.easeOut(duration: 0.2), value: isOut)
        }
        .buttonStyle(PressableScaleStyle(scale: 0.97))
        .disabled(isBusy)
        .accessibilityLabel(film.title)
        .accessibilityAddTraits(isKept ? [.isSelected] : [])
    }

    // MARK: - Les gestes

    /// Garder, puis écarter. Toucher à nouveau le film gardé le relâche : on
    /// peut se reprendre avant d'avoir tranché.
    private func pick(_ film: CineMatchGalleryFilm) {
        guard !isBusy else { return }
        Haptics.selection()

        guard let kept = keptID else {
            keptID = film.id
            return
        }
        guard kept != film.id else {
            keptID = nil
            return
        }

        excludedID = film.id
        let latency = Int(Date().timeIntervalSince(shownAt) * 1000)
        history.append(.pick(keptID: kept, excludedID: film.id, latencyMs: latency))

        Task {
            // Le duel est attendu avant de passer au tour suivant : la porte se
            // remesure à la fermeture, et elle doit trouver chaque duel écrit.
            try? await client.recordDuel(winnerID: kept, loserID: film.id)
            if round >= Self.rounds {
                onClose()
                return
            }
            round += 1
            await load()
        }
    }

    private func skip() {
        guard !isBusy, !films.isEmpty else { return }
        Haptics.selection()
        history.append(.none(shownIDs: films.map(\.id)))
        keptID = nil
        Task { await load() }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let next = try await client.comparisonRound(
                round: round, shownIDs: shownIDs, history: history, forDoor: true
            )
            films = next.films
            keptID = nil
            excludedID = nil
            for id in next.films.map(\.id) where !shownIDs.contains(id) {
                shownIDs.append(id)
            }
            shownAt = Date()

            let ids = next.films.map(\.id)
            if !ids.isEmpty {
                let client = client
                Task { try? await client.recordExposure(kind: .poster, tmdbIDs: ids) }
            }
        } catch {
            excludedID = nil
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

// MARK: - La grille

/// La maille des quatre affiches : deux par deux si la hauteur le permet,
/// sinon sur une ligne, selon ce qui donne les plus grandes affiches.
private struct DoorPosterLayout {
    static let caption: CGFloat = 30
    static let captionSpacing: CGFloat = 6

    let columns: Int
    let gap: CGFloat
    let cellWidth: CGFloat
    let cellHeight: CGFloat
    let posterWidth: CGFloat
    let posterHeight: CGFloat

    init(size: CGSize) {
        let textBlock = Self.caption + Self.captionSpacing

        let squareGap: CGFloat = 10
        let squareCell = CGSize(width: max(0, (size.width - squareGap) / 2), height: max(0, (size.height - squareGap) / 2))
        let squarePoster = max(0, min(squareCell.height - textBlock, squareCell.width * 1.5))

        let rowGap: CGFloat = 8
        let rowCell = CGSize(width: max(0, (size.width - rowGap * 3) / 4), height: max(0, size.height))
        let rowPoster = max(0, min(rowCell.height - textBlock, rowCell.width * 1.5))

        if squarePoster >= rowPoster {
            columns = 2
            gap = squareGap
            cellWidth = squareCell.width
            cellHeight = squareCell.height
            posterHeight = squarePoster
        } else {
            columns = 4
            gap = rowGap
            cellWidth = rowCell.width
            cellHeight = rowCell.height
            posterHeight = rowPoster
        }
        posterWidth = posterHeight / 1.5
    }
}

/// La croix de fermeture, cerclée : celle de la planche des coups de cœur.
private struct DoorCloseGlyph: View {
    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Ink.ruleSet, lineWidth: 1)
            DoorCloseCross()
                .stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .foregroundStyle(Ink.ink2)
                .padding(9)
        }
        .accessibilityHidden(true)
    }
}

private struct DoorCloseCross: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        return path
    }
}
