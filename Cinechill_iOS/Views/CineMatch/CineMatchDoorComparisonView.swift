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
/// Chaque tour se joue en deux questions, sur deux groupes de quatre films de
/// la galerie : on garde celui qu'on préfère parmi les premiers, puis on
/// désigne celui qu'on aime le moins parmi quatre autres, et le duel s'écrit
/// côté serveur. Garder les mêmes affiches d'une question à l'autre faisait
/// passer le changement inaperçu : on écartait un film en croyant encore en
/// choisir un. Le passage se voit donc trois fois. L'interrupteur en tête
/// bascule de « Préféré » à « Moins aimé » et prend la teinte de l'écart, la
/// page change de films, et aux deux premiers tours la question occupe seule
/// l'écran un court instant. Le quiz du parcours de la soirée joue le même
/// passage (voir `CineMatchQuizView`). **« Passer » ne compte pas** : il demande quatre autres films pour
/// le même tour, parce que la Porte compte les duels réellement tranchés et
/// qu'un compteur d'écran qui avancerait sans eux mentirait.
///
/// La remesure de la porte revient à l'écran qui présente celui-ci, à la
/// fermeture, comme pour la planche des coups de cœur : chaque duel a déjà été
/// attendu avant de passer au tour suivant, donc rien n'est en route quand on
/// ferme.
///
/// Côté séries, la même planche compare des séries vues, six fois et non
/// douze : c'est la cible de la Porte des séries.
struct CineMatchDoorComparisonView: View {
    private let client: any CineMatchFetching
    private let format: MediaFormat
    private let onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(DoorStore.self) private var doorStore

    private var isSeries: Bool { format == .series }

    /// La cible de l'artéfact, telle que le serveur la mesure.
    private var rounds: Int {
        doorStore.door(for: format).artifact(.horizons)?.target ?? (isSeries ? 6 : 12)
    }

    /// Le seuil de la Mémoire : le serveur ne compare pas une galerie plus
    /// petite, et c'est lui que l'écran vide doit nommer.
    private var memoryTarget: Int {
        doorStore.door(for: format).artifact(.memoire)?.target ?? (isSeries ? 15 : 100)
    }

    private enum Stage { case prefer, least }

    @State private var round = 1
    @State private var stage: Stage = .prefer
    @State private var films: [CineMatchGalleryFilm] = []
    /// Les quatre films de la seconde question, tirés avec ceux de la première.
    @State private var leastFilms: [CineMatchGalleryFilm] = []
    @State private var shownIDs: [Int] = []
    @State private var history: [CineMatchComparison] = []
    @State private var kept: CineMatchGalleryFilm?
    /// Le film touché à la première question, marqué le temps que la page
    /// change.
    @State private var keptID: Int?
    @State private var excludedID: Int?
    /// La question seule à l'écran, entre les deux pages.
    @State private var showsBascule = false
    @State private var isSwitching = false
    @Namespace private var stageSwitch
    @State private var shownAt = Date()
    @State private var isLoading = false
    @State private var hasLoadedOnce = false
    @State private var errorMessage: String?

    init(
        client: any CineMatchFetching = BackendCineMatchClient(),
        format: MediaFormat = .film,
        onClose: @escaping () -> Void
    ) {
        self.client = client
        self.format = format
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

                Text(String(localized: "\(round) sur \(rounds)", bundle: .app))
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
        let fraction = Double(round - 1) / Double(max(1, rounds))
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
                title: isSeries
                    ? String(localized: "Impossible de charger les séries", bundle: .app)
                    : String(localized: "Impossible de charger les films", bundle: .app),
                message: errorMessage,
                actionTitle: String(localized: "Réessayer", bundle: .app),
                action: { Task { await load() } },
                secondaryTitle: String(localized: "Fermer", bundle: .app),
                secondaryAction: onClose
            )
            .frame(maxHeight: .infinity)
        } else if films.isEmpty, !isLoading, hasLoadedOnce {
            PlanEmptyState(
                title: isSeries
                    ? String(localized: "Pas assez de séries vues", bundle: .app)
                    : String(localized: "Pas assez de films vus", bundle: .app),
                message: isSeries
                    ? String(localized: "Ajoute d'abord \(memoryTarget) séries à ta galerie pour pouvoir comparer.", bundle: .app)
                    : String(localized: "Ajoute d'abord \(memoryTarget) films à ta galerie pour pouvoir comparer.", bundle: .app),
                actionTitle: String(localized: "Fermer", bundle: .app),
                action: onClose
            )
            .frame(maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                stageSwitchBar
                    .padding(.top, isCompact ? 12 : 18)

                ZStack(alignment: .topLeading) {
                    if showsBascule {
                        bascule(isCompact: isCompact)
                            .transition(.opacity)
                    } else {
                        page(isCompact: isCompact)
                            .id(stage)
                            .transition(pageTransition)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)

                Button(action: skip) {
                    Text("Passer", bundle: .app)
                        .planFont(13, weight: .medium)
                        .foregroundStyle(Ink.ink2)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
                .disabled(isBusy || films.isEmpty)
            }
            .animation(stageAnimation, value: stage)
            .animation(.easeOut(duration: 0.2), value: showsBascule)
        }
    }

    private func page(isCompact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(question)
                .planFont(isCompact ? 20 : 24, weight: .regular, design: .serif)
                .kerning(0.1)
                .foregroundStyle(Ink.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, isCompact ? 12 : 18)
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
        }
    }

    /// Le passage d'une question à l'autre, en grand : la seconde question ne
    /// se lit pas comme une suite de la première, elle la retourne.
    private func bascule(isCompact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isSeries
                 ? String(localized: "Quatre autres séries", bundle: .app)
                 : String(localized: "Quatre autres films", bundle: .app))
                .planLabel()
                .foregroundStyle(Ink.warn)
            Text(question)
                .planFont(isCompact ? 28 : 36, weight: .regular, design: .serif)
                .foregroundStyle(Ink.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.bottom, 60)
        .accessibilityHidden(true)
    }

    private var stageAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.42, dampingFraction: 0.86)
    }

    /// La seconde page arrive par la droite et pousse la première : on avance,
    /// on ne revient pas.
    private var pageTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }

    // MARK: - L'interrupteur

    /// Il ne se touche pas : il dit où l'on en est. La moitié active est
    /// pleine ; à la seconde question elle prend la teinte de l'écart, et la
    /// première garde l'affiche du film préféré.
    private var stageSwitchBar: some View {
        let isLeast = stage == .least
        return HStack(spacing: 4) {
            stageSegment(
                title: String(localized: "Préféré", bundle: .app),
                isActive: !isLeast,
                fill: Ink.ink,
                kept: isLeast ? kept : nil
            )
            stageSegment(
                title: String(localized: "Moins aimé", bundle: .app),
                isActive: isLeast,
                fill: Ink.warn,
                kept: nil
            )
        }
        .padding(3)
        .background(Ink.ground2, in: RoundedRectangle(cornerRadius: Metrics.radius + 3, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.radius + 3, style: .continuous)
                .strokeBorder(Ink.ruleSet, lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(stageAccessibilityLabel)
    }

    private func stageSegment(title: String, isActive: Bool, fill: Color, kept: CineMatchGalleryFilm?) -> some View {
        HStack(spacing: 7) {
            if let kept {
                PosterImageView(url: kept.posterURL, contentMode: .fill)
                    .frame(width: 16, height: 24)
                    .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
            Text(title)
                .planLabel()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(isActive ? Ink.ground : kept != nil ? Ink.ink2 : Ink.ink3)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 36)
        .background {
            if isActive {
                RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                    .fill(fill)
                    .matchedGeometryEffect(id: "stage", in: stageSwitch)
            }
        }
    }

    private var stageAccessibilityLabel: String {
        guard stage == .least, let kept else {
            return isSeries
                ? String(localized: "Question 1 sur 2 : la série que tu préfères", bundle: .app)
                : String(localized: "Question 1 sur 2 : le film que tu préfères", bundle: .app)
        }
        return isSeries
            ? String(localized: "Question 2 sur 2 : la série que tu aimes le moins, parmi quatre autres. Tu as préféré \(kept.title).", bundle: .app)
            : String(localized: "Question 2 sur 2 : le film que tu aimes le moins, parmi quatre autres. Tu as préféré \(kept.title).", bundle: .app)
    }

    private var isBusy: Bool { isLoading || excludedID != nil || isSwitching }

    /// La question, avec « le moins » à la teinte de l'écart : c'est le mot qui
    /// retourne la question, il doit se lire avant le reste.
    private var question: AttributedString {
        var text: AttributedString
        switch (isSeries, stage) {
        case (false, .prefer): text = AttributedString(localized: "Lequel tu préfères ?", bundle: .app)
        case (false, .least): text = AttributedString(localized: "Et celui que tu aimes **le moins** ?", bundle: .app)
        case (true, .prefer): text = AttributedString(localized: "Laquelle tu préfères ?", bundle: .app)
        case (true, .least): text = AttributedString(localized: "Et celle que tu aimes **le moins** ?", bundle: .app)
        }
        for run in text.runs where run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true {
            text[run.range].inlinePresentationIntent = nil
            text[run.range].swiftUI.foregroundColor = Ink.warn
        }
        return text
    }

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
        let isKept = stage == .prefer && keptID == film.id
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
                        shape.strokeBorder(
                            isKept ? Ink.light : isOut ? Ink.warn : Ink.ink.opacity(0.18),
                            lineWidth: isKept || isOut ? 2 : 1
                        )
                    )
                    .overlay(alignment: .top) {
                        if isOut {
                            outLabel
                                .planLabel()
                                .foregroundStyle(Ink.warn)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Ink.ground3, in: RoundedRectangle(cornerRadius: 2, style: .continuous))
                                .padding(.top, 6)
                                .transition(.opacity)
                        }
                    }

                Text(film.title)
                    .planFont(12)
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

    /// « Le moins aimé », accordé : une série est la moins aimée.
    @ViewBuilder
    private var outLabel: some View {
        Group {
            if isSeries {
                Text("La moins aimée", bundle: .app)
            } else {
                Text("Le moins aimé", bundle: .app)
            }
        }
    }

    // MARK: - Les gestes

    /// Préférer, puis désigner le moins aimé, chacun sur ses quatre films. Le
    /// premier geste ne se reprend pas : la page a déjà changé de films.
    private func pick(_ film: CineMatchGalleryFilm) {
        guard !isBusy else { return }
        Haptics.selection()
        switch stage {
        case .prefer: prefer(film)
        case .least: markLeast(film)
        }
    }

    private func prefer(_ film: CineMatchGalleryFilm) {
        keptID = film.id
        kept = film
        isSwitching = true
        let fresh = leastFilms.count >= 3 ? leastFilms : films.filter { $0.id != film.id }
        // La bascule en grand aux deux premiers tours seulement : elle apprend
        // le passage, puis l'interrupteur et la page suffisent. Douze fois, elle
        // ne serait plus qu'une attente.
        let showsInterlude = round <= 2

        Task {
            // Le film préféré reste marqué le temps qu'on le voie choisi.
            try? await Task.sleep(for: .milliseconds(180))
            if showsInterlude { showsBascule = true }
            stage = .least
            films = fresh
            for id in fresh.map(\.id) where !shownIDs.contains(id) {
                shownIDs.append(id)
            }
            recordExposure(fresh.map(\.id))
            AccessibilityNotification.Announcement(isSeries
                ? String(localized: "Et celle que tu aimes le moins, parmi quatre autres séries ?", bundle: .app)
                : String(localized: "Et celui que tu aimes le moins, parmi quatre autres films ?", bundle: .app)
            ).post()
            if showsInterlude {
                try? await Task.sleep(for: .milliseconds(800))
                showsBascule = false
            }
            shownAt = Date()
            isSwitching = false
        }
    }

    private func markLeast(_ film: CineMatchGalleryFilm) {
        guard let kept, kept.id != film.id else { return }
        excludedID = film.id
        let latency = Int(Date().timeIntervalSince(shownAt) * 1000)
        history.append(.pick(keptID: kept.id, excludedID: film.id, latencyMs: latency))

        Task {
            // Le duel est attendu avant de passer au tour suivant : la porte se
            // remesure à la fermeture, et elle doit trouver chaque duel écrit.
            try? await client.recordDuel(winnerID: kept.id, loserID: film.id, format: format)
            if round >= rounds {
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
        Task { await load() }
    }

    private func recordExposure(_ ids: [Int]) {
        guard !ids.isEmpty else { return }
        let client = client
        let format = format
        Task { try? await client.recordExposure(kind: .poster, tmdbIDs: ids, format: format) }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let next = try await client.comparisonRound(
                round: round, shownIDs: shownIDs, history: history, forDoor: true, format: format
            )
            // Un seul film ne se compare à rien : l'état « pas assez de films
            // vus » prend le relais plutôt qu'une question sans réponse.
            films = next.films.count >= 2 ? next.films : []
            leastFilms = next.excludeFilms
            stage = .prefer
            kept = nil
            keptID = nil
            excludedID = nil
            for id in next.films.map(\.id) where !shownIDs.contains(id) {
                shownIDs.append(id)
            }
            shownAt = Date()
            recordExposure(next.films.map(\.id))
        } catch {
            // L'écran d'erreur prend la place du tour. Garder l'ancien quatuor
            // laissait enregistrer un duel sur des films déjà joués.
            films = []
            leastFilms = []
            stage = .prefer
            kept = nil
            keptID = nil
            excludedID = nil
            errorMessage = String(localized: "Le serveur n'a pas répondu comme prévu. Réessaie dans un instant.", bundle: .app)
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
