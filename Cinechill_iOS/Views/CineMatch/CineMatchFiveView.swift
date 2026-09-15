//
//  CineMatchFiveView.swift
//  Cinechill_iOS
//

import SwiftUI

/// Ce que le carrousel présente : les cinq propositions du parcours guidé, ou
/// la proposition du jour.
enum CineMatchFiveMode {
    case five, daily
}

/// Les cinq films, un par écran — et la proposition du jour, dans le même
/// langage visuel : une seule façon de dire « voici ton film ».
///
/// Cinq plutôt qu'un : un coup de cœur pèse deux fois plus qu'un raté, il faut
/// maximiser la chance qu'il y en ait un. Un seul à l'écran plutôt que cinq :
/// ce qui monte avec la taille d'un ensemble, c'est la difficulté ressentie.
/// Les quatre autres restent à un geste.
///
/// La carte reprend « la planche » de Découvrir : l'affiche entière, une plaque
/// de nuit fermée par un filet, l'année et le genre au-dessus du titre. Le
/// synopsis ne vit pas dans la carte ; le bouton « i » l'ouvre en feuille.
/// **Balayer vers la droite amène le film suivant**, vers la gauche revient au
/// précédent, et la carte résiste aux deux extrémités.
struct CineMatchFiveView: View {
    let viewModel: CineMatchViewModel
    let mode: CineMatchFiveMode

    @EnvironmentObject private var libraryStore: LibraryStore
    @Environment(MediaCatalog.self) private var catalog
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Le déplacement de la carte sous le doigt, et pendant son départ.
    @State private var dragOffset: CGFloat = 0
    @State private var rotation: Double = 0
    @State private var cardOpacity: Double = 1
    /// Prise par le haut, la carte bascule autour de son bord bas ; prise par
    /// le bas, autour de son bord haut.
    @State private var isGrabbedHigh = true
    /// Une carte part : aucun geste n'est pris tant que la suivante n'est pas
    /// arrivée.
    @State private var isTurning = false
    @State private var synopsis: SynopsisContent?

    init(viewModel: CineMatchViewModel, mode: CineMatchFiveMode) {
        self.viewModel = viewModel
        self.mode = mode
    }

    private var films: [CineMatchFilm] {
        switch mode {
        case .five: viewModel.films
        case .daily: viewModel.dailyFilm.map { [$0] } ?? []
        }
    }

    private var index: Int {
        guard mode == .five, !films.isEmpty else { return 0 }
        return min(max(0, viewModel.currentIndex), films.count - 1)
    }

    private var current: CineMatchFilm? {
        films.isEmpty ? nil : films[index]
    }

    /// Les plateformes de la soirée d'abord, celles déclarées dans les réglages
    /// à défaut : c'est ce qui choisit le logo affiché et l'app ouverte.
    private var preferredPlatformIDs: [String] {
        let situation = viewModel.situation.platformIDs
        return situation.isEmpty ? Array(libraryStore.preferredPlatformIDs).sorted() : situation
    }

    var body: some View {
        VStack(spacing: 0) {
            strip
                .padding(.top, 14)

            if let current {
                deck(current)
                    .padding(.top, 12)

                actions(for: current)
                    .padding(.top, 10)
            } else if mode == .daily, let message = viewModel.errorMessage {
                PlanEmptyState(
                    title: String(localized: "Impossible de charger les films", bundle: .app),
                    message: message,
                    actionTitle: String(localized: "Réessayer", bundle: .app),
                    action: { Task { await viewModel.retry() } },
                    secondaryTitle: String(localized: "Retour", bundle: .app),
                    secondaryAction: { viewModel.backToHome() }
                )
                .frame(maxHeight: .infinity)
            } else {
                CinechillSpinner(size: 28)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if mode == .daily { backLink }
            }
        }
        .padding(.horizontal, Metrics.margin)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Ink.ground)
        .sheet(item: $synopsis) { content in
            CineMatchSynopsisSheet(content: content, onClose: { synopsis = nil })
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .onAppear {
            PosterImageCache.shared.prefetch(films.map(\.item.posterURL))
            showCurrentCard()
        }
        .onChange(of: films.map(\.id)) { _, _ in
            PosterImageCache.shared.prefetch(films.map(\.item.posterURL))
            showCurrentCard()
        }
        // En quittant les résultats, l'exposition accumulée part d'un bloc.
        .onDisappear {
            Task { await viewModel.flushExposure() }
        }
    }

    /// La carte à l'écran compte comme montrée. La proposition du jour, elle,
    /// est enregistrée par le modèle à son chargement.
    private func showCurrentCard() {
        guard mode == .five, !films.isEmpty else { return }
        viewModel.showCard(at: index)
    }

    // MARK: - Le bandeau

    private var strip: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                switch mode {
                case .five:
                    if films.count > 1 { dots }
                    if !films.isEmpty {
                        Text(String(localized: "\(index + 1) sur \(films.count)", bundle: .app))
                            .planLabel()
                            .monospacedDigit()
                            .foregroundStyle(Ink.ink2)
                    }
                case .daily:
                    Text("La proposition du jour", bundle: .app)
                        .planLabel()
                        .foregroundStyle(Ink.ink2)
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 16)

            if mode == .five, let widening = viewModel.widening {
                if widening.duration {
                    wideningLine(String(localized: "On a été plus souple sur la durée", bundle: .app))
                }
                if widening.platforms {
                    wideningLine(String(localized: "On a ajouté des films d'autres plateformes", bundle: .app))
                }
            }
        }
    }

    private var dots: some View {
        HStack(spacing: 5) {
            ForEach(films.indices, id: \.self) { position in
                Rectangle()
                    .fill(position == index ? Ink.ink : Ink.ink3)
                    .frame(width: 5, height: 5)
            }
        }
        .animation(Metrics.shift, value: index)
        .accessibilityHidden(true)
    }

    private func wideningLine(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(Ink.ink2)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Le paquet

    private func deck(_ film: CineMatchFilm) -> some View {
        GeometryReader { proxy in
            let chevronWidth: CGFloat = mode == .five ? 26 : 0
            let size = Self.cardSize(
                in: CGSize(width: proxy.size.width - chevronWidth * 2, height: proxy.size.height)
            )

            ZStack {
                card(film, size: size)
                    .id(film.id)

                if mode == .five {
                    HStack(spacing: 0) {
                        chevron(.previous, cardWidth: size.width)
                        Spacer(minLength: 0)
                        chevron(.next, cardWidth: size.width)
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .frame(maxHeight: .infinity)
    }

    /// Sur un grand écran, la proportion de Découvrir (1,62). Quand la hauteur
    /// manque, la carte s'élargit plutôt que de rétrécir : une carte de 150
    /// points de large tronque le titre, alors que l'affiche, tenue entière
    /// dans son cadre, supporte très bien une proportion plus basse.
    private static func cardSize(in space: CGSize) -> CGSize {
        let width = max(0, space.width)
        let height = max(0, space.height)
        var w = min(width, height / 1.62)
        var h = min(height, w * 1.62)
        if h < 380 {
            w = min(width, height / 1.22)
            h = min(height, w * 1.22)
        }
        return CGSize(width: w, height: h)
    }

    private func card(_ film: CineMatchFilm, size: CGSize) -> some View {
        let isCompact = size.height < 380
        let shape = RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)

        return VStack(spacing: 0) {
            PosterImageView(url: film.item.posterURL, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 9)
                .offset(x: max(-9, min(9, -dragOffset * 0.05)))
                .accessibilityHidden(true)

            plate(film, isCompact: isCompact)
        }
        .frame(width: size.width, height: size.height)
        .background(Ink.ground)
        .overlay(shape.strokeBorder(Ink.rule, lineWidth: 1))
        .clipShape(shape)
        .contentShape(shape)
        .rotationEffect(.degrees(rotation), anchor: isGrabbedHigh ? .bottom : .top)
        .offset(x: dragOffset)
        .opacity(cardOpacity)
        .gesture(dragGesture(cardHeight: size.height, cardWidth: size.width))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(film.item.title)
        .accessibilityValue(mode == .five ? String(localized: "\(index + 1) sur \(films.count)", bundle: .app) : "")
        .accessibilityAction(named: String(localized: "Film suivant", bundle: .app)) { turn(1, cardWidth: size.width) }
        .accessibilityAction(named: String(localized: "Film précédent", bundle: .app)) { turn(-1, cardWidth: size.width) }
        .accessibilityAction(named: String(localized: "Synopsis", bundle: .app)) { openSynopsis(film) }
    }

    private func plate(_ film: CineMatchFilm, isCompact: Bool) -> some View {
        VStack(spacing: 0) {
            PlanEdge(tint: Ink.ruleSet)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Text(eyebrow(for: film))
                        .planLabel()
                        .foregroundStyle(Ink.ink2)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        openSynopsis(film)
                    } label: {
                        FiveInfoGlyph()
                            .foregroundStyle(Ink.ink2)
                            .frame(width: 19, height: 19)
                            .frame(width: 34, height: 34)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableScaleStyle(scale: 0.92))
                    .accessibilityLabel(String(localized: "Synopsis de \(film.item.title)", bundle: .app))
                }
                .padding(.top, -8)
                .padding(.trailing, -9)
                .padding(.bottom, -6)

                Text(film.item.title)
                    .planTitle(isCompact ? 19 : 25)
                    .foregroundStyle(Ink.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)

                FiveMetaRow(
                    runtime: film.runtimeMinutes,
                    platform: platform(for: film),
                    fontSize: 12
                )
                .padding(.top, 6)
            }
            .padding(.horizontal, isCompact ? 14 : 16)
            .padding(.top, isCompact ? 11 : 14)
            .padding(.bottom, isCompact ? 10 : 13)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Ink.ground)
    }

    private enum Direction { case previous, next }

    private func chevron(_ direction: Direction, cardWidth: CGFloat) -> some View {
        let isDisabled = direction == .previous ? index == 0 : index >= films.count - 1

        return Button {
            turn(direction == .next ? 1 : -1, cardWidth: cardWidth)
        } label: {
            FiveArrowGlyph(pointsRight: direction == .next)
                .stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                .foregroundStyle(Ink.ink2)
                .frame(width: 16, height: 16)
                .frame(width: 26, height: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isDisabled ? 0.22 : 1)
        .disabled(isDisabled || isTurning)
        .accessibilityLabel(
            direction == .next
                ? String(localized: "Film suivant", bundle: .app)
                : String(localized: "Film précédent", bundle: .app)
        )
    }

    // MARK: - Le geste

    private func dragGesture(cardHeight: CGFloat, cardWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                guard !isTurning else { return }
                if dragOffset == 0, rotation == 0 {
                    isGrabbedHigh = value.startLocation.y < cardHeight / 2
                }
                let raw = value.translation.width
                // Aux extrémités la carte résiste fort : vers la gauche sur le
                // premier film, vers la droite sur le dernier.
                let atEnd = mode == .daily
                    || (raw < 0 && index == 0)
                    || (raw > 0 && index >= films.count - 1)
                let offset = atEnd ? raw * 0.3 : Self.resisted(raw, threshold: 90)
                dragOffset = offset
                rotation = Double(offset / 22) * (isGrabbedHigh ? 1 : -1)
            }
            .onEnded { value in
                guard !isTurning else { return }
                let offset = dragOffset
                let direction = offset > 0 ? 1 : -1
                let velocity = value.velocity.width
                let target = index + direction
                let commits = mode == .five
                    && films.indices.contains(target)
                    && (abs(offset) > 90 || (abs(velocity) > 550 && abs(offset) > 28))
                if commits {
                    turn(direction, cardWidth: cardWidth)
                } else {
                    withAnimation(Self.recenter) {
                        dragOffset = 0
                        rotation = 0
                    }
                }
            }
    }

    /// Le rappel au centre : il dépasse légèrement, la carte est tenue par un
    /// ressort et non posée.
    private static let recenter = Animation.spring(response: 0.36, dampingFraction: 0.62)

    /// Au-delà du seuil le doigt continue mais la carte résiste, en s'approchant
    /// d'une limite sans jamais l'atteindre (même loi que `SwipeMotion`).
    private static func resisted(_ value: CGFloat, threshold: CGFloat) -> CGFloat {
        let magnitude = abs(value)
        guard magnitude > threshold else { return value }
        let slack = 84.0
        let compressed = CGFloat(slack * (1 - exp(-Double(magnitude - threshold) / slack)))
        return (value < 0 ? -1 : 1) * (threshold + compressed)
    }

    /// Tourner une carte : la courante part du côté du geste, la suivante
    /// arrive par l'autre. Hors des bornes, la carte bute et revient.
    private func turn(_ direction: Int, cardWidth: CGFloat) {
        guard mode == .five, !isTurning else { return }
        let target = index + direction
        guard films.indices.contains(target) else {
            bump(direction)
            return
        }

        Haptics.impact(.light, intensity: 0.6)

        if reduceMotion {
            dragOffset = 0
            rotation = 0
            viewModel.showCard(at: target)
            return
        }

        isTurning = true
        let travel = cardWidth + 70
        Task {
            withAnimation(.timingCurve(0.2, 0.7, 0.3, 1, duration: 0.26)) {
                dragOffset = CGFloat(direction) * travel
                rotation = Double(direction) * 7
                cardOpacity = 0
            }
            try? await Task.sleep(for: .milliseconds(240))

            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) {
                viewModel.showCard(at: target)
                dragOffset = -CGFloat(direction) * travel
                rotation = -Double(direction) * 7
            }
            // Une image pour que la carte suivante soit posée hors champ avant
            // de revenir : sans elle les deux écritures se confondraient.
            try? await Task.sleep(for: .milliseconds(16))

            withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.34)) {
                dragOffset = 0
                rotation = 0
                cardOpacity = 1
            }
            try? await Task.sleep(for: .milliseconds(300))
            isTurning = false
        }
    }

    private func bump(_ direction: Int) {
        guard !reduceMotion else { return }
        withAnimation(.easeOut(duration: 0.12)) {
            dragOffset = CGFloat(direction) * 16
            rotation = 0
        }
        Task {
            try? await Task.sleep(for: .milliseconds(120))
            withAnimation(Self.recenter) { dragOffset = 0 }
        }
    }

    // MARK: - Les actions

    @ViewBuilder
    private func actions(for film: CineMatchFilm) -> some View {
        VStack(spacing: 7) {
            PlanButton(title: String(localized: "Démarrer le film", bundle: .app)) {
                start(film)
            }

            switch mode {
            case .five:
                PlanSecondaryButton(
                    title: String(localized: "Bande-annonce", bundle: .app),
                    isEnabled: film.trailerURL != nil || film.trailerAppURL != nil,
                    height: 44
                ) {
                    openTrailer(film)
                }
            case .daily:
                backLink
            }
        }
    }

    private var backLink: some View {
        Button {
            viewModel.backToHome()
        } label: {
            Text("Retour", bundle: .app)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(Ink.ink2)
                .padding(.horizontal, 18)
                .frame(minHeight: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Ouvre l'app native de la plateforme si elle est installée, sinon son
    /// site. Le lancement est noté même si rien ne s'ouvre : la décision a été
    /// prise, c'est elle qui compte.
    private func start(_ film: CineMatchFilm) {
        let platformIDs = preferredPlatformIDs
        viewModel.start(film)
        for candidate in film.watchAppURLCandidates(preferring: platformIDs)
        where UIApplication.shared.canOpenURL(candidate) {
            UIApplication.shared.open(candidate)
            return
        }
        guard let webURL = film.watchWebURL(preferring: platformIDs) else { return }
        openURL(webURL)
    }

    private func openTrailer(_ film: CineMatchFilm) {
        if let appURL = film.trailerAppURL, UIApplication.shared.canOpenURL(appURL) {
            UIApplication.shared.open(appURL)
        } else if let webURL = film.trailerURL {
            openURL(webURL)
        }
    }

    private func openSynopsis(_ film: CineMatchFilm) {
        synopsis = SynopsisContent(
            id: film.id,
            eyebrow: eyebrow(for: film),
            title: film.item.title,
            runtime: film.runtimeMinutes,
            platform: platform(for: film),
            overview: film.item.overview
        )
    }

    // MARK: - Ce que la carte affiche

    private func eyebrow(for film: CineMatchFilm) -> String {
        var parts = [film.item.displayYear]
        if let genreID = film.item.genreIds.first, let genre = catalog.name(forGenre: genreID) {
            parts.append(genre)
        }
        return parts.joined(separator: " · ")
    }

    private func platform(for film: CineMatchFilm) -> StreamingPlatform? {
        guard let providerID = film.providerID(preferring: preferredPlatformIDs) else { return nil }
        return catalog.platform(forProvider: providerID)
    }
}

// MARK: - Le synopsis

/// Ce que la feuille montre, résolu par le carrousel : la feuille ne dépend
/// ainsi d'aucun objet d'environnement.
private struct SynopsisContent: Identifiable {
    let id: Int
    let eyebrow: String
    let title: String
    let runtime: Int?
    let platform: StreamingPlatform?
    let overview: String?
}

/// Le synopsis s'ouvre par-dessus la vue : la carte reste légère, et le texte
/// long a toute la largeur de l'écran pour lui.
private struct CineMatchSynopsisSheet: View {
    let content: SynopsisContent
    let onClose: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Text(content.eyebrow)
                        .planLabel()
                        .foregroundStyle(Ink.ink2)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button(action: onClose) {
                        FiveCloseGlyph()
                            .stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                            .foregroundStyle(Ink.ink2)
                            .frame(width: 18, height: 18)
                            .frame(width: 38, height: 38)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableScaleStyle(scale: 0.92))
                    .accessibilityLabel(String(localized: "Fermer le synopsis", bundle: .app))
                }
                .padding(.trailing, -10)

                Text(content.title)
                    .planTitle(26)
                    .foregroundStyle(Ink.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
                    .accessibilityAddTraits(.isHeader)

                FiveMetaRow(runtime: content.runtime, platform: content.platform, fontSize: 12.5)
                    .padding(.top, 6)

                if let overview = content.overview, !overview.isEmpty {
                    Text("Synopsis", bundle: .app)
                        .planLabel()
                        .foregroundStyle(Ink.ink2)
                        .padding(.top, 18)

                    Text(overview)
                        .font(.system(size: 14.5))
                        .foregroundStyle(Ink.ink)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 7)
                }
            }
            .padding(.horizontal, Metrics.margin)
            .padding(.top, 22)
            .padding(.bottom, Metrics.margin)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .presentationBackground(Ink.ground2)
    }
}

// MARK: - La ligne de mesure

/// La durée et le logo de la plateforme, séparés d'un point.
private struct FiveMetaRow: View {
    let runtime: Int?
    let platform: StreamingPlatform?
    let fontSize: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            if let runtime, runtime > 0 {
                Text(verbatim: Self.format(runtime))
                    .font(.system(size: fontSize))
                    .monospacedDigit()
                    .foregroundStyle(Ink.ink2)
            }
            if runtime ?? 0 > 0, platform != nil {
                Text(verbatim: "·")
                    .font(.system(size: fontSize))
                    .foregroundStyle(Ink.ink3)
                    .padding(.horizontal, 6)
                    .accessibilityHidden(true)
            }
            if let platform {
                logo(platform)
            }
        }
        .frame(minHeight: 18)
    }

    private func logo(_ platform: StreamingPlatform) -> some View {
        Group {
            if let url = platform.logoURL {
                PosterImageView(url: url)
            } else {
                Text(verbatim: platform.shortLabel)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Ink.ink2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Ink.ground3)
            }
        }
        .frame(width: 18, height: 18)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous))
        .accessibilityElement()
        .accessibilityLabel(platform.name)
    }

    /// « 1h52 » : des chiffres, pas une phrase, donc rien à traduire.
    static func format(_ minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        return hours > 0 ? "\(hours)h\(String(format: "%02d", rest))" : "\(rest) min"
    }
}

// MARK: - Les glyphes

/// Le « i » du synopsis : un cercle, une hampe, un point.
private struct FiveInfoGlyph: View {
    var body: some View {
        GeometryReader { proxy in
            let s = min(proxy.size.width, proxy.size.height) / 24
            ZStack {
                Circle()
                    .stroke(lineWidth: 1.5)
                    .frame(width: 18 * s, height: 18 * s)
                Path { path in
                    path.move(to: CGPoint(x: 12 * s, y: 11 * s))
                    path.addLine(to: CGPoint(x: 12 * s, y: 16.6 * s))
                }
                .stroke(style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                Circle()
                    .frame(width: 2.2 * s, height: 2.2 * s)
                    .position(x: 12 * s, y: 7.7 * s)
            }
            .frame(width: 24 * s, height: 24 * s)
        }
        .accessibilityHidden(true)
    }
}

/// La flèche des chevrons du carrousel, grille de 24.
private struct FiveArrowGlyph: Shape {
    let pointsRight: Bool

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + (pointsRight ? x : 24 - x) * s, y: rect.minY + y * s)
        }
        var path = Path()
        path.move(to: p(4, 12))
        path.addLine(to: p(20, 12))
        path.move(to: p(14, 6))
        path.addLine(to: p(20, 12))
        path.addLine(to: p(14, 18))
        return path
    }
}

private struct FiveCloseGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 6.4 * s, y: rect.minY + 6.4 * s))
        path.addLine(to: CGPoint(x: rect.minX + 17.6 * s, y: rect.minY + 17.6 * s))
        path.move(to: CGPoint(x: rect.minX + 17.6 * s, y: rect.minY + 6.4 * s))
        path.addLine(to: CGPoint(x: rect.minX + 6.4 * s, y: rect.minY + 17.6 * s))
        return path
    }
}
