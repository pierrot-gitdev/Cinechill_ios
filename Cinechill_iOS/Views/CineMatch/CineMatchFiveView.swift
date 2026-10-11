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
///
/// Une série a sa carte à elle, de même forme : le sourcil donne les saisons,
/// la ligne de mesure le nombre d'épisodes et leur durée, et une ligne dit où
/// en est l'histoire. « Je la commence » met la saison 1 dans la file, à son
/// premier épisode, puis ouvre la plateforme.
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
    /// Le film dont on demande « Tu l'as aimé ? », sur place, sous la carte.
    @State private var askingSeenID: Int?

    init(viewModel: CineMatchViewModel, mode: CineMatchFiveMode) {
        self.viewModel = viewModel
        self.mode = mode
    }

    private var isSeries: Bool { viewModel.format == .series }

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
            } else if mode == .daily, let message = viewModel.errorMessage, viewModel.failureIsNoCandidates {
                PlanEmptyState(
                    title: isSeries
                        ? String(localized: "Aucune série pour ce soir", bundle: .app)
                        : String(localized: "Aucun film pour ce soir", bundle: .app),
                    message: message,
                    actionTitle: String(localized: "Retour à l'accueil", bundle: .app),
                    action: { viewModel.backToHome() }
                )
                .frame(maxHeight: .infinity)
            } else if mode == .daily, let message = viewModel.errorMessage {
                PlanEmptyState(
                    title: isSeries
                        ? String(localized: "Impossible de charger les séries", bundle: .app)
                        : String(localized: "Impossible de charger les films", bundle: .app),
                    message: message,
                    actionTitle: String(localized: "Réessayer", bundle: .app),
                    action: { Task { await viewModel.retry() } },
                    secondaryTitle: String(localized: "Retour à l'accueil", bundle: .app),
                    secondaryAction: { viewModel.backToHome() }
                )
                .frame(maxHeight: .infinity)
            } else {
                // L'attente dit ce qu'on attend : un projecteur seul ne disait
                // pas si la proposition du jour arrivait ou si l'écran était figé.
                VStack(spacing: 14) {
                    CinechillSpinner(size: 28)
                    Text(waitingText)
                        .planFont(13.5)
                        .foregroundStyle(Ink.ink2)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityElement(children: .combine)
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

    private var waitingText: String {
        switch (mode, isSeries) {
        case (.daily, false): String(localized: "On cherche ton film du jour…", bundle: .app)
        case (.daily, true): String(localized: "On cherche ta série du jour…", bundle: .app)
        case (.five, false): String(localized: "On cherche tes cinq films…", bundle: .app)
        case (.five, true): String(localized: "On cherche tes cinq séries…", bundle: .app)
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
                    // Un pas en arrière : les six films de départ, ou les
                    // styles après « Peu importe ». Choisir un autre film de
                    // départ vaut mieux que de tout reprendre à l'accueil.
                    Button {
                        viewModel.goBack()
                    } label: {
                        Text("Retour", bundle: .app)
                            .planFont(13, weight: .medium)
                            .foregroundStyle(Ink.ink2)
                            .padding(.trailing, 12)
                            .frame(minHeight: Metrics.control)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableScaleStyle(scale: 0.96))
                    // Le bouton garde sa cible de 44 pt sans pousser la carte.
                    .padding(.vertical, -14)
                    .disabled(viewModel.isReplacing)

                    Spacer(minLength: 0)

                    if films.count > 1 { dots }
                    if !films.isEmpty {
                        Text(String(localized: "\(index + 1) sur \(films.count)", bundle: .app))
                            .planLabel()
                            .monospacedDigit()
                            .foregroundStyle(Ink.ink2)
                    }
                case .daily:
                    Group {
                        if isSeries {
                            Text("La série du jour", bundle: .app)
                        } else {
                            Text("La proposition du jour", bundle: .app)
                        }
                    }
                    .planLabel()
                    .foregroundStyle(Ink.ink2)

                    Spacer(minLength: 0)
                }
            }
            .frame(minHeight: 16)

            // Ce qu'on a demandé, en une ligne : le film touché, le second
            // film, la retouche. Sans elle, rien ne disait plus pourquoi ces
            // cinq-là. Absente après « Peu importe ».
            if mode == .five, let line = requestLine {
                Text(line)
                    .planFont(13)
                    .foregroundStyle(Ink.ink2)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if mode == .five, let outcome = viewModel.replaceOutcome {
                replaceLine(outcome)
            }

            if mode == .five, let widening = viewModel.widening {
                if widening.duration {
                    wideningLine(String(localized: "On a été plus souple sur la durée", bundle: .app))
                }
                if widening.platforms {
                    wideningLine(isSeries
                        ? String(localized: "On a ajouté des séries d'autres plateformes", bundle: .app)
                        : String(localized: "On a ajouté des films d'autres plateformes", bundle: .app))
                }
            }
        }
    }

    /// « Un film proche de Heat et Drive, plus récent ».
    private var requestLine: String? {
        guard let anchor = viewModel.anchor else { return nil }
        let base: String = switch (viewModel.secondFilm, isSeries) {
        case (let second?, false):
            String(localized: "Un film proche de \(anchor.title) et \(second.title)", bundle: .app)
        case (let second?, true):
            String(localized: "Une série proche de \(anchor.title) et \(second.title)", bundle: .app)
        case (nil, false):
            String(localized: "Un film proche de \(anchor.title)", bundle: .app)
        case (nil, true):
            String(localized: "Une série proche de \(anchor.title)", bundle: .app)
        }
        guard let tweak = viewModel.chosenTweak else { return base }
        return base + ", " + tweak.suffix(series: isSeries)
    }

    /// Un point par film ; creux pour un film marqué « déjà vu » ou écarté.
    private var dots: some View {
        HStack(spacing: 5) {
            ForEach(films.indices, id: \.self) { position in
                let tint = position == index ? Ink.ink : Ink.ink3
                if viewModel.marks[films[position].id] != nil {
                    Rectangle()
                        .strokeBorder(tint, lineWidth: 1)
                        .frame(width: 6, height: 6)
                } else {
                    Rectangle()
                        .fill(tint)
                        .frame(width: 5, height: 5)
                }
            }
        }
        .animation(Metrics.shift, value: index)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func replaceLine(_ outcome: CineMatchViewModel.ReplaceOutcome) -> some View {
        switch outcome {
        case .replaced(let count, let dropped, let seen):
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                PlanLight()
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                Text(Self.replacedText(count: count, dropped: dropped, seen: seen, isSeries: isSeries))
                    .planFont(13)
                    .foregroundStyle(Ink.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .failed:
            wideningLine(replaceFailedText)
        }
    }

    private var replaceFailedText: String {
        if viewModel.markedCount > 1 {
            return String(localized: "On n'a pas pu les remplacer. Réessaie dans un instant.", bundle: .app)
        }
        return isSeries
            ? String(localized: "On n'a pas pu la remplacer. Réessaie dans un instant.", bundle: .app)
            : String(localized: "On n'a pas pu le remplacer. Réessaie dans un instant.", bundle: .app)
    }

    /// `seen` : combien des films partis étaient déjà vus. Seuls ceux-là
    /// sont entrés en galerie ; un film écarté n'y va pas, et la phrase ne le
    /// prétend pas.
    static func replacedText(count: Int, dropped: Int, seen: Int, isSeries: Bool) -> String {
        if count == 0 {
            return isSeries
                ? String(localized: "On n'a pas d'autre série à te proposer ce soir.", bundle: .app)
                : String(localized: "On n'a pas d'autre film à te proposer ce soir.", bundle: .app)
        }
        // Deux phrases accordées chacune à son compte : deux films vus et un
        // seul remplaçant donnaient « 1 film remplacé. Celui que tu as vu… »,
        // alors que les deux étaient partis en galerie.
        let replaced: String
        let kept: String?
        if isSeries {
            replaced = count == 1
                ? String(localized: "1 série remplacée.", bundle: .app)
                : String(localized: "\(count) séries remplacées.", bundle: .app)
            kept = switch seen {
            case 0: nil
            case 1: String(localized: "Celle que tu as vue est dans ta galerie.", bundle: .app)
            default: String(localized: "Celles que tu as vues sont dans ta galerie.", bundle: .app)
            }
        } else {
            replaced = count == 1
                ? String(localized: "1 film remplacé.", bundle: .app)
                : String(localized: "\(count) films remplacés.", bundle: .app)
            kept = switch seen {
            case 0: nil
            case 1: String(localized: "Celui que tu as vu est dans ta galerie.", bundle: .app)
            default: String(localized: "Ceux que tu as vus sont dans ta galerie.", bundle: .app)
            }
        }
        return [replaced, kept].compactMap { $0 }.joined(separator: " ")
    }

    private func wideningLine(_ text: String) -> some View {
        Text(text)
            .planFont(13)
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

        let mark = mode == .five ? viewModel.marks[film.id] : nil

        return VStack(spacing: 0) {
            PosterImageView(url: film.item.posterURL, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 9)
                .offset(x: max(-9, min(9, -dragOffset * 0.05)))
                .opacity(mark == nil ? 1 : 0.3)
                .overlay(alignment: .topLeading) { cardTag(for: film, mark: mark) }
                .accessibilityHidden(true)

            plate(film, isCompact: isCompact)
                .opacity(mark == nil ? 1 : 0.55)
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
        .accessibilityValue(cardAccessibilityValue(film))
        .accessibilityAction(named: nextLabel) { turn(1, cardWidth: size.width) }
        .accessibilityAction(named: previousLabel) { turn(-1, cardWidth: size.width) }
        .accessibilityAction(named: String(localized: "Synopsis", bundle: .app)) { openSynopsis(film) }
    }

    /// « Déjà vu » ou « Écarté » sur un film marqué, « Nouveau » sur un
    /// remplaçant.
    @ViewBuilder
    private func cardTag(for film: CineMatchFilm, mark: CineMatchViewModel.Mark?) -> some View {
        let text: String? = if let mark {
            switch mark {
            case .seen(loved: true): String(localized: "Déjà vu · coup de cœur", bundle: .app)
            case .seen(loved: false): String(localized: "Déjà vu", bundle: .app)
            case .refused where isSeries: String(localized: "Écartée", bundle: .app)
            case .refused: String(localized: "Écarté", bundle: .app)
            }
        } else if mode == .five, viewModel.freshFilmIDs.contains(film.id) {
            String(localized: "Nouveau", bundle: .app)
        } else {
            nil
        }
        if let text {
            Text(text)
                .planLabel()
                .foregroundStyle(Ink.ink)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Ink.ground3, in: RoundedRectangle(cornerRadius: 2, style: .continuous))
                .padding(12)
                .transition(.opacity)
        }
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
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableScaleStyle(scale: 0.92))
                    .accessibilityLabel(String(localized: "Synopsis de \(film.item.title)", bundle: .app))
                }
                // Les retraits suivent la cible de 44 pt : le glyphe reste
                // où il était, seule la zone qu'on touche a grandi.
                .padding(.top, -13)
                .padding(.trailing, -14)
                .padding(.bottom, -11)

                Text(film.item.title)
                    .planTitle(isCompact ? 19 : 25)
                    .foregroundStyle(Ink.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)

                FiveMetaRow(
                    episodes: film.isSeries ? film.episodeCount : nil,
                    runtime: film.runtimeMinutes,
                    platform: platform(for: film),
                    fontSize: 12
                )
                .padding(.top, 6)

                if let status = film.status {
                    Text(Self.statusLine(status))
                        .planFont(12)
                        .foregroundStyle(Ink.ink2)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
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
                // 26 pt de large dans la mise en page, 44 au toucher : la
                // zone déborde un peu sur la carte plutôt que de la rétrécir.
                .contentShape(Rectangle().inset(by: -9))
        }
        .buttonStyle(PressableScaleStyle(scale: 0.9))
        .opacity(isDisabled ? 0.22 : 1)
        .disabled(isDisabled || isTurning)
        .accessibilityLabel(direction == .next ? nextLabel : previousLabel)
    }

    private var nextLabel: String {
        isSeries
            ? String(localized: "Série suivante", bundle: .app)
            : String(localized: "Film suivant", bundle: .app)
    }

    private var previousLabel: String {
        isSeries
            ? String(localized: "Série précédente", bundle: .app)
            : String(localized: "Film précédent", bundle: .app)
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

    private func cardAccessibilityValue(_ film: CineMatchFilm) -> String {
        guard mode == .five else { return "" }
        let position = String(localized: "\(index + 1) sur \(films.count)", bundle: .app)
        switch viewModel.marks[film.id] {
        case nil:
            return position
        case .seen:
            return position + ", " + String(localized: "déjà vu", bundle: .app)
        case .refused:
            return position + ", " + (isSeries
                ? String(localized: "écartée", bundle: .app)
                : String(localized: "écarté", bundle: .app))
        }
    }

    @ViewBuilder
    private func actions(for film: CineMatchFilm) -> some View {
        Group {
            if mode == .five, askingSeenID == film.id {
                seenQuestion(for: film)
            } else if mode == .five, let mark = viewModel.marks[film.id] {
                markedActions(for: film, mark: mark)
            } else {
                regularActions(for: film)
            }
        }
        .animation(.easeOut(duration: 0.2), value: askingSeenID)
        .animation(.easeOut(duration: 0.2), value: viewModel.marks)
    }

    private func regularActions(for film: CineMatchFilm) -> some View {
        VStack(spacing: 7) {
            if mode == .five, viewModel.markedCount > 0 {
                replaceBar
            }

            // « Je le regarde » promet d'ouvrir une plateforme : sans plateforme
            // connue, rien ne s'ouvrait. Le bouton dit alors ce qu'il fait.
            PlanButton(title: launchTitle(for: film)) {
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
                markLinks(for: film)
            case .daily:
                backLink
            }
        }
    }

    /// Les deux façons de dire non à un film, côte à côte, l'une sous l'autre
    /// quand le texte agrandi ne tient plus sur une ligne.
    private func markLinks(for film: CineMatchFilm) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                alreadySeenLink(for: film)
                refuseLink(for: film)
            }
            VStack(spacing: 0) {
                alreadySeenLink(for: film)
                refuseLink(for: film)
            }
        }
    }

    /// « Je l'ai déjà vu » : il se peut que CinéMatch propose un film qu'on a
    /// vu sans l'avoir rangé. On le dit ici, sans quitter la proposition.
    private func alreadySeenLink(for film: CineMatchFilm) -> some View {
        Button {
            askingSeenID = film.id
        } label: {
            HStack(spacing: 8) {
                FiveSeenGlyph()
                    .stroke(style: StrokeStyle(lineWidth: 1.2, lineJoin: .round))
                    .frame(width: 16, height: 11)
                Text(isSeries
                     ? String(localized: "Je l'ai déjà vue", bundle: .app)
                     : String(localized: "Je l'ai déjà vu", bundle: .app))
                    .planFont(14, weight: .medium)
                    .fixedSize()
            }
            .foregroundStyle(Ink.ink)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .frame(minHeight: Metrics.control)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableScaleStyle(scale: 0.97))
        .disabled(viewModel.isReplacing)
    }

    /// « Pas celui-là » : le film ne tente pas, sans qu'on l'ait vu. Il se
    /// marque comme un film vu, et part avec eux au remplacement.
    private func refuseLink(for film: CineMatchFilm) -> some View {
        Button {
            viewModel.markRefused(film)
            replaceIfAllMarked()
        } label: {
            HStack(spacing: 8) {
                FiveCloseGlyph()
                    .stroke(style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                    .frame(width: 14, height: 14)
                Text(isSeries
                     ? String(localized: "Pas celle-là", bundle: .app)
                     : String(localized: "Pas celui-là", bundle: .app))
                    .planFont(14, weight: .medium)
                    .fixedSize()
            }
            .foregroundStyle(Ink.ink)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .frame(minHeight: Metrics.control)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableScaleStyle(scale: 0.97))
        .disabled(viewModel.isReplacing)
    }

    /// La question posée sur place, à la place des boutons : on reste sur le
    /// film dont on parle.
    private func seenQuestion(for film: CineMatchFilm) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(isSeries
                     ? String(localized: "Tu l'as aimée ?", bundle: .app)
                     : String(localized: "Tu l'as aimé ?", bundle: .app))
                    .planTitle(18)
                    .foregroundStyle(Ink.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Text("Déjà vu", bundle: .app)
                    .planLabel()
                    .foregroundStyle(Ink.ink2)
            }

            HStack(spacing: 10) {
                PlanSecondaryButton(
                    title: String(localized: "Coup de cœur", bundle: .app),
                    height: Metrics.button
                ) {
                    markSeen(film, loved: true)
                }
                PlanSecondaryButton(
                    title: String(localized: "Vu, sans plus", bundle: .app),
                    height: Metrics.button
                ) {
                    markSeen(film, loved: false)
                }
            }

            Button {
                askingSeenID = nil
            } label: {
                Text("Annuler", bundle: .app)
                    .planFont(13.5, weight: .medium)
                    .foregroundStyle(Ink.ink2)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: Metrics.control)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableScaleStyle(scale: 0.97))
        }
        .transition(.opacity)
    }

    /// Un film marqué : il ne se lance plus, il se remplace, avec tous les
    /// autres films marqués, en un seul calcul.
    private func markedActions(for film: CineMatchFilm, mark: CineMatchViewModel.Mark) -> some View {
        VStack(spacing: 7) {
            // Côte à côte tant que ça tient, l'un sous l'autre au grand texte :
            // le compteur et l'indication se coupaient mutuellement.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    seenSummaryText
                    Spacer(minLength: 8)
                    nextHint
                }
                VStack(alignment: .leading, spacing: 4) {
                    seenSummaryText
                    nextHint
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.bottom, 4)

            PlanButton(
                title: replaceTitle,
                loadingTitle: String(localized: "On cherche…", bundle: .app),
                isLoading: viewModel.isReplacing
            ) {
                Task { await viewModel.replaceMarked() }
            }

            Button {
                unmark(film)
            } label: {
                Text(unmarkTitle(mark))
                    .planFont(13.5, weight: .medium)
                    .foregroundStyle(Ink.ink2)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: Metrics.control)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableScaleStyle(scale: 0.97))
            .disabled(viewModel.isReplacing)
        }
        .transition(.opacity)
    }

    private func unmarkTitle(_ mark: CineMatchViewModel.Mark) -> String {
        switch (mark, isSeries) {
        case (.seen, false): String(localized: "Je ne l'ai pas vu, en fait", bundle: .app)
        case (.seen, true): String(localized: "Je ne l'ai pas vue, en fait", bundle: .app)
        case (.refused, false): String(localized: "Je le garde, en fait", bundle: .app)
        case (.refused, true): String(localized: "Je la garde, en fait", bundle: .app)
        }
    }

    private var seenSummaryText: some View {
        Text(markedSummary)
            .planFont(13.5)
            .foregroundStyle(Ink.ink2)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Rien sur la dernière carte : il n'y a plus de suivante.
    @ViewBuilder
    private var nextHint: some View {
        if index < films.count - 1 {
            Text(isSeries
                 ? String(localized: "Série suivante à droite", bundle: .app)
                 : String(localized: "Film suivant à droite", bundle: .app))
                .planLabel()
                // `ink2` et non `ink3` : l'encre la plus basse ne porte pas de
                // texte sous 13 pt.
                .foregroundStyle(Ink.ink2)
                .lineLimit(1)
        }
    }

    /// Le compteur des films marqués, qui suit de carte en carte : on continue
    /// de regarder les autres, et on remplace quand on a fini.
    private var replaceBar: some View {
        HStack(spacing: 12) {
            Text(markedSummary)
                .planFont(13.5)
                .foregroundStyle(Ink.ink2)
            Spacer(minLength: 8)
            Button {
                Task { await viewModel.replaceMarked() }
            } label: {
                Text(viewModel.isReplacing
                     ? String(localized: "On cherche…", bundle: .app)
                     : String(localized: "Les remplacer", bundle: .app))
                    .planFont(13, weight: .semibold)
                    .foregroundStyle(Ink.ink)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 36)
                    .overlay(
                        RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                            .strokeBorder(Ink.ruleSet, lineWidth: 1)
                    )
                    // Le cadre dessiné reste à 36 pt ; la zone qu'on touche
                    // en fait 44.
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableScaleStyle(scale: 0.97))
            .disabled(viewModel.isReplacing)
        }
        .padding(.vertical, 2)
        .overlay(alignment: .top) { Rectangle().fill(Ink.rule).frame(height: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(Ink.rule).frame(height: 1) }
        .padding(.bottom, 6)
    }

    /// Vus ou écartés, ils ont le même sort : on les compte ensemble.
    private var markedSummary: String {
        let count = viewModel.markedCount
        if isSeries {
            return count == 1
                ? String(localized: "1 série à remplacer sur \(films.count)", bundle: .app)
                : String(localized: "\(count) séries à remplacer sur \(films.count)", bundle: .app)
        }
        return count == 1
            ? String(localized: "1 film à remplacer sur \(films.count)", bundle: .app)
            : String(localized: "\(count) films à remplacer sur \(films.count)", bundle: .app)
    }

    private var replaceTitle: String {
        let count = viewModel.markedCount
        if isSeries {
            return count <= 1
                ? String(localized: "Remplacer cette série", bundle: .app)
                : String(localized: "Remplacer ces \(count) séries", bundle: .app)
        }
        return count <= 1
            ? String(localized: "Remplacer ce film", bundle: .app)
            : String(localized: "Remplacer ces \(count) films", bundle: .app)
    }

    // MARK: - Les gestes du déjà vu

    /// Ce qui se voit dans une série, c'est sa saison 1 : c'est elle qui entre
    /// en galerie, comme depuis Découvrir.
    private func galleryItem(for film: CineMatchFilm) -> MediaItem {
        film.isSeries ? film.firstSeason : film.item
    }

    /// Le film part en galerie tout de suite : vu, il l'est, qu'on remplace ou
    /// non. Le cœur attend que la galerie le connaisse, faute de quoi le
    /// serveur n'aurait rien sur quoi le poser.
    private func markSeen(_ film: CineMatchFilm, loved: Bool) {
        askingSeenID = nil
        viewModel.markSeen(film, loved: loved)
        let item = galleryItem(for: film)
        libraryStore.addToGallery(item)
        if loved {
            Task {
                let clock = ContinuousClock()
                let deadline = clock.now + .seconds(8)
                while !libraryStore.isInGallery(item), clock.now < deadline {
                    try? await Task.sleep(for: .milliseconds(150))
                }
                // Rien n'a été annulé entre-temps.
                guard viewModel.marks[film.id] == .seen(loved: true) else { return }
                libraryStore.setLove(item, loved: true)
            }
        }
        replaceIfAllMarked()
    }

    /// Tout est marqué : il n'y a plus rien à regarder ici, le calcul part.
    private func replaceIfAllMarked() {
        guard viewModel.markedCount == films.count else { return }
        Task { await viewModel.replaceMarked() }
    }

    /// Un film vu sort de la galerie où il venait d'entrer ; un film écarté
    /// n'y était jamais allé.
    private func unmark(_ film: CineMatchFilm) {
        let wasSeen = if case .seen = viewModel.marks[film.id] { true } else { false }
        viewModel.unmark(film)
        if wasSeen {
            libraryStore.removeFromGallery(galleryItem(for: film))
        }
    }

    private var backLink: some View {
        Button {
            viewModel.backToHome()
        } label: {
            Text("Retour", bundle: .app)
                .planFont(13.5, weight: .medium)
                .foregroundStyle(Ink.ink2)
                .padding(.horizontal, 18)
                .frame(minHeight: Metrics.control)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableScaleStyle(scale: 0.97))
    }

    /// Ouvre l'app native de la plateforme si elle est installée, sinon son
    /// site. Le lancement est noté même si rien ne s'ouvre : la décision a été
    /// prise, c'est elle qui compte.
    private func start(_ film: CineMatchFilm) {
        let platformIDs = preferredPlatformIDs
        // Commencer une série, c'est mettre sa saison 1 dans la file, au
        // premier épisode : c'est la watchlist qui prendra le relais dès le
        // soir suivant. Une saison 1 déjà dans la file garde son épisode.
        if film.isSeries, libraryStore.watchlistEntry(for: film.firstSeason) == nil {
            libraryStore.addToWatchlist(film.firstSeason, nextEpisode: 1)
        }
        viewModel.start(film)
        // Un film : demain à 19 h, on demande comment c'était.
        if !film.isSeries {
            Task { await NotificationPermission.shared.filmStarted(film.item) }
        }
        // Avant d'ouvrir la plateforme : une fois l'app passée en arrière-plan,
        // iOS refuserait de démarrer l'activité.
        CineMatchLiveActivity.start(film: film, details: liveActivityDetails(for: film))
        for candidate in film.watchAppURLCandidates(preferring: platformIDs)
        where UIApplication.shared.canOpenURL(candidate) {
            UIApplication.shared.open(candidate)
            return
        }
        guard let webURL = film.watchWebURL(preferring: platformIDs) else { return }
        openURL(webURL)
    }

    private func canLaunch(_ film: CineMatchFilm) -> Bool {
        !film.watchAppURLCandidates(preferring: preferredPlatformIDs).isEmpty
            || film.watchWebURL(preferring: preferredPlatformIDs) != nil
    }

    private func launchTitle(for film: CineMatchFilm) -> String {
        switch (canLaunch(film), film.isSeries) {
        case (true, true): String(localized: "Je la commence", bundle: .app)
        case (true, false): String(localized: "Je le regarde", bundle: .app)
        case (false, true): String(localized: "Je choisis celle-là", bundle: .app)
        case (false, false): String(localized: "Je choisis celui-là", bundle: .app)
        }
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
            episodes: film.isSeries ? film.episodeCount : nil,
            runtime: film.runtimeMinutes,
            platform: platform(for: film),
            overview: film.item.overview
        )
    }

    // MARK: - Ce que la carte affiche

    private func eyebrow(for film: CineMatchFilm) -> String {
        var parts = [film.item.displayYear]
        if film.isSeries, let seasons = film.item.seasonCount, seasons > 0 {
            parts.append(seasons == 1
                ? String(localized: "1 saison", bundle: .app)
                : String(localized: "\(seasons) saisons", bundle: .app))
        }
        if let genreID = film.item.genreIds.first, let genre = catalog.name(forGenre: genreID) {
            parts.append(genre)
        }
        return parts.joined(separator: " · ")
    }

    /// La ligne sous le titre, sur l'écran verrouillé : « 2023 · Drame · 1h46
    /// · Netflix ». Une série commence toujours au premier épisode, c'est donc
    /// lui qu'on nomme à la place de l'année.
    private func liveActivityDetails(for film: CineMatchFilm) -> String {
        var parts: [String] = []
        if film.isSeries {
            parts.append(String(localized: "Saison \(1) · épisode \(1)", bundle: .app))
        } else {
            if (film.item.releaseDate?.count ?? 0) >= 4 {
                parts.append(film.item.displayYear)
            }
            if let genreID = film.item.genreIds.first, let genre = catalog.name(forGenre: genreID) {
                parts.append(genre)
            }
        }
        if let runtime = film.runtimeMinutes, runtime > 0 {
            parts.append(FiveMetaRow.format(runtime))
        }
        if let platform = platform(for: film) {
            parts.append(platform.name)
        }
        return parts.joined(separator: " · ")
    }

    private func platform(for film: CineMatchFilm) -> StreamingPlatform? {
        guard let providerID = film.providerID(preferring: preferredPlatformIDs) else { return nil }
        return catalog.platform(forProvider: providerID)
    }

    /// Où en est l'histoire : ce qu'on sait en la commençant.
    static func statusLine(_ status: CineMatchSeriesStatus) -> String {
        switch status {
        case .ended: String(localized: "Terminée : elle a une vraie fin.", bundle: .app)
        case .returning: String(localized: "Toujours en cours : d'autres saisons arrivent.", bundle: .app)
        case .canceled: String(localized: "Annulée avant la fin : l'histoire reste en suspens.", bundle: .app)
        }
    }
}

// MARK: - Le synopsis

/// Ce que la feuille montre, résolu par le carrousel : la feuille ne dépend
/// ainsi d'aucun objet d'environnement.
private struct SynopsisContent: Identifiable {
    let id: Int
    let eyebrow: String
    let title: String
    let episodes: Int?
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

                FiveMetaRow(episodes: content.episodes, runtime: content.runtime, platform: content.platform, fontSize: 12.5)
                    .padding(.top, 6)

                Text("Synopsis", bundle: .app)
                    .planLabel()
                    .foregroundStyle(Ink.ink2)
                    .padding(.top, 18)

                // Sans résumé, la feuille ouverte par « i » restait vide sous
                // le titre : on dit qu'il manque.
                if let overview = content.overview, !overview.isEmpty {
                    Text(overview)
                        .planFont(14.5)
                        .foregroundStyle(Ink.ink)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 7)
                } else {
                    Text("Pas de résumé pour l'instant.", bundle: .app)
                        .planFont(14.5)
                        .foregroundStyle(Ink.ink2)
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

/// La durée et le logo de la plateforme, séparés d'un point. Pour une série,
/// le nombre d'épisodes vient devant, et la durée est celle d'un épisode.
private struct FiveMetaRow: View {
    let episodes: Int?
    let runtime: Int?
    let platform: StreamingPlatform?
    let fontSize: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            if let episodes, episodes > 0 {
                Text(episodes == 1
                    ? String(localized: "1 épisode", bundle: .app)
                    : String(localized: "\(episodes) épisodes", bundle: .app))
                    .planFont(fontSize)
                    .monospacedDigit()
                    .foregroundStyle(Ink.ink2)
                if runtime ?? 0 > 0 || platform != nil { dot }
            }
            if let runtime, runtime > 0 {
                Text(verbatim: Self.format(runtime))
                    .planFont(fontSize)
                    .monospacedDigit()
                    .foregroundStyle(Ink.ink2)
            }
            if runtime ?? 0 > 0, platform != nil {
                dot
            }
            if let platform {
                logo(platform)
            }
        }
        .frame(minHeight: 18)
    }

    private var dot: some View {
        Text(verbatim: "·")
            .planFont(fontSize)
            .foregroundStyle(Ink.ink3)
            .padding(.horizontal, 6)
            .accessibilityHidden(true)
    }

    private func logo(_ platform: StreamingPlatform) -> some View {
        Group {
            if let url = platform.logoURL {
                PosterImageView(url: url)
            } else {
                Text(verbatim: platform.shortLabel)
                    .planFont(8, weight: .semibold)
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

/// L'œil du « déjà vu » : une amande et sa pupille, au trait.
private struct FiveSeenGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.midY), control: CGPoint(x: rect.midX, y: rect.minY - rect.height * 0.45))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.midY), control: CGPoint(x: rect.midX, y: rect.maxY + rect.height * 0.45))
        let r = rect.height * 0.22
        path.addEllipse(in: CGRect(x: rect.midX - r, y: rect.midY - r, width: r * 2, height: r * 2))
        return path
    }
}
