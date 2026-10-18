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

/// Les cinq films, un par écran, et la proposition du jour, dans le même
/// langage visuel : une seule façon de dire « voici ton film ».
///
/// **La salle s'allume** (12 octobre 2026, à la demande de Pierre, qui
/// trouvait le carrousel trop sage) : l'affiche est l'écran au fond d'une
/// salle dont les rangées sont celles du logo. À l'arrivée, on s'approche,
/// l'écran s'allume et sa lumière court sur les fauteuils ; à chaque film
/// suivant, l'écran s'éteint et se rallume. Voir `CineMatchRoomView`.
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

    /// Le déplacement sous le doigt : l'écran suit un peu.
    @State private var dragOffset: CGFloat = 0
    /// Un film change : aucun geste n'est pris tant que l'écran n'est pas
    /// rallumé.
    @State private var isTurning = false
    /// Ce que joue la salle : l'entrée, un changement de film, ou rien.
    @State private var sequence: CineMatchRoomSequence = .still
    /// La salle est éteinte : le fond passe au noir.
    @State private var isDark = false
    /// Le titre, l'heure de fin et les boutons sont arrivés.
    @State private var isRevealed = false
    @State private var synopsis: SynopsisContent?
    /// Le film dont on demande « Tu l'as aimé ? », sur place, sous l'écran.
    @State private var askingSeenID: Int?
    /// La bande-annonce passe sur l'écran de la salle.
    @State private var isTrailerOpen = false
    /// De l'affiche à l'écran au format cinéma (bande-annonce).
    @State private var widen: Double = 0
    /// De la salle allumée à la salle éteinte, film lancé.
    @State private var launch: Double = 0
    /// L'heure du lancement : celle qui fixe « fin vers ».
    @State private var launchedAt: Date?

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
        if isLaunched { return viewModel.concludedFilm }
        return films.isEmpty ? nil : films[index]
    }

    /// « Je le regarde » a été touché : la même vue montre le film lancé, la
    /// salle éteinte, sans changer de décor.
    private var isLaunched: Bool { viewModel.step == .conclusion }

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
                room(current)
                    .padding(.top, 10)
                    .padding(.horizontal, -Metrics.margin)

                if isLaunched {
                    launched(current)
                        .padding(.top, 12)
                        .transition(.opacity)
                } else {
                    details(current)
                        .padding(.top, 10)
                        .opacity(isRevealed ? 1 : 0)
                        .offset(y: isRevealed || reduceMotion ? 0 : 14)

                    actions(for: current)
                        .padding(.top, 14)
                        .opacity(isRevealed ? 1 : 0)
                        .allowsHitTesting(isRevealed)
                }
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
        .background(isDark ? Self.night : Ink.ground)
        .sheet(item: $synopsis) { content in
            CineMatchSynopsisSheet(content: content, onClose: { synopsis = nil })
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .onAppear {
            PosterImageCache.shared.prefetch(films.map(\.item.posterURL))
            // Revenu sur un film déjà lancé (changement d'onglet) : la salle
            // est éteinte, sans rejouer l'entrée.
            guard !isLaunched else {
                isDark = true
                isRevealed = true
                launch = 1
                return
            }
            showCurrentCard()
            playEntrance()
        }
        .onChange(of: films.map(\.id)) { _, ids in
            guard !isLaunched else { return }
            // Plus aucun film (la proposition du jour se remplace) : la
            // suivante fera son entrée, comme à l'ouverture.
            guard !ids.isEmpty else {
                isRevealed = false
                return
            }
            PosterImageCache.shared.prefetch(films.map(\.item.posterURL))
            showCurrentCard()
            // Les films arrivent (proposition du jour), ou l'un d'eux est
            // remplacé : l'entrée la première fois, un changement ensuite.
            if isRevealed { playSwap() } else { playEntrance() }
        }
        // En quittant les résultats, l'exposition accumulée part d'un bloc.
        .onDisappear {
            Task { await viewModel.flushExposure() }
        }
    }

    private var waitingText: String {
        if mode == .daily, viewModel.dailyReplacedSeen {
            return isSeries
                ? String(localized: "On cherche une autre série…", bundle: .app)
                : String(localized: "On cherche un autre film…", bundle: .app)
        }
        return switch (mode, isSeries) {
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
                case .five where !isLaunched:
                    // Un pas en arrière : les six films de départ, ou les
                    // styles après « Peu importe ». Choisir un autre film de
                    // départ vaut mieux que de tout reprendre à l'accueil.
                    Button {
                        viewModel.goBack()
                    } label: {
                        FiveArrowGlyph(pointsRight: false)
                            .stroke(style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                            .foregroundStyle(Ink.ink2)
                            .frame(width: 16, height: 16)
                            .frame(width: 44, height: Metrics.control, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableScaleStyle(scale: 0.92))
                    // Le bouton garde sa cible de 44 pt sans pousser la salle.
                    .padding(.vertical, -14)
                    .disabled(viewModel.isReplacing)
                    .accessibilityLabel(String(localized: "Retour", bundle: .app))

                    Spacer(minLength: 0)

                    // Les points suffisent : « 1 sur 5 » disait deux fois la
                    // même chose (épuré le 13 octobre).
                    if films.count > 1 { dots }
                case .five:
                    Spacer(minLength: 0)
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
            if mode == .five, !isLaunched, let line = requestLine {
                Text(line)
                    .planFont(13)
                    .foregroundStyle(Ink.ink2)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
            }

            if mode == .five, !isLaunched, let outcome = viewModel.replaceOutcome {
                replaceLine(outcome)
            }

            // Le film d'avant n'a pas disparu : il est rangé.
            if mode == .daily, !isLaunched, viewModel.dailyReplacedSeen, current != nil {
                Text(isSeries
                     ? String(localized: "Celle que tu as vue est dans ta galerie.", bundle: .app)
                     : String(localized: "Celui que tu as vu est dans ta galerie.", bundle: .app))
                    .planFont(13)
                    .foregroundStyle(Ink.ink2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .transition(.opacity)
            }

            if mode == .five, !isLaunched, let widening = viewModel.widening {
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

    // MARK: - La salle

    /// Le noir de la salle éteinte, plus profond que celui de l'app. Calculé :
    /// une couleur ne craint rien d'un `static let`, mais la règle se tient
    /// mieux sans exception.
    private static var night: Color { Color(hex: 0x080706) }

    private func room(_ film: CineMatchFilm) -> some View {
        let mark = mode == .five && !isLaunched ? viewModel.marks[film.id] : nil
        let canPlayTrailer = film.trailerKey?.isEmpty == false
        let showsCue = isRevealed && !isLaunched && !isTrailerOpen && mark == nil && canPlayTrailer

        return CineMatchRoomView(
            film: film,
            isMarked: mark != nil,
            tag: isLaunched ? nil : tagText(for: film, mark: mark),
            showsTrailerCue: showsCue,
            sequence: sequence,
            dragOffset: dragOffset,
            widen: widen,
            launch: launch
        ) {
            if isTrailerOpen, let key = film.trailerKey {
                CineMatchTrailerPlayer(key: key)
                    .overlay(alignment: .topTrailing) {
                        Button {
                            closeTrailer()
                        } label: {
                            FiveCloseGlyph()
                                .stroke(style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                                .foregroundStyle(.white)
                                .frame(width: 16, height: 16)
                                .frame(width: 44, height: 44)
                                .background(Color.black.opacity(0.55), in: Circle().inset(by: 8))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PressableScaleStyle(scale: 0.92))
                        .accessibilityLabel(String(localized: "Fermer la bande-annonce", bundle: .app))
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { tapRoom(film) }
        .gesture(mode == .five && !isLaunched && !isTrailerOpen ? dragGesture : nil)
        .accessibilityElement(children: isTrailerOpen ? .contain : .ignore)
        .accessibilityLabel(film.item.title)
        .accessibilityValue(isLaunched ? "" : cardAccessibilityValue(film))
        .accessibilityAction(named: String(localized: "Bande-annonce", bundle: .app)) { openTrailer(film) }
        .accessibilityAction(named: nextLabel) { turn(1) }
        .accessibilityAction(named: previousLabel) { turn(-1) }
        .accessibilityAction(named: String(localized: "Synopsis", bundle: .app)) { openSynopsis(film) }
    }

    /// Un toucher sur la salle : pendant l'entrée, il la passe ; ensuite,
    /// sur l'écran, il lance la bande-annonce, puisque c'est là qu'elle passe.
    private func tapRoom(_ film: CineMatchFilm) {
        if sequence.kind == .entrance {
            skipEntrance()
            return
        }
        guard !isLaunched, !isTrailerOpen, isRevealed, viewModel.marks[film.id] == nil else { return }
        openTrailer(film)
    }

    /// « Déjà vu » ou « Écarté » sur un film marqué, « Nouveau » sur un
    /// remplaçant.
    private func tagText(for film: CineMatchFilm, mark: CineMatchViewModel.Mark?) -> String? {
        if let mark {
            return switch mark {
            case .seen(loved: true): String(localized: "Déjà vu · coup de cœur", bundle: .app)
            case .seen(loved: false): String(localized: "Déjà vu", bundle: .app)
            case .refused where isSeries: String(localized: "Écartée", bundle: .app)
            case .refused: String(localized: "Écarté", bundle: .app)
            }
        }
        if mode == .five, viewModel.freshFilmIDs.contains(film.id) {
            return String(localized: "Nouveau", bundle: .app)
        }
        return nil
    }

    /// Ce que l'on sait du film, sous l'écran, et rien de plus (épuré le 13
    /// octobre) : le titre, qui ouvre le synopsis, puis une ligne, la durée,
    /// l'heure à laquelle il finirait si on le lançait maintenant, la
    /// plateforme. L'heure part de l'heure qu'il est et défile jusqu'à la fin
    /// à l'arrivée du film.
    private func details(_ film: CineMatchFilm) -> some View {
        VStack(spacing: 6) {
            Button {
                openSynopsis(film)
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(film.item.title)
                        .planTitle(28)
                        .foregroundStyle(Ink.ink)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                        .fixedSize(horizontal: false, vertical: true)
                    Image(systemName: "chevron.right")
                        .planFont(15, weight: .regular)
                        .foregroundStyle(Ink.ink3)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableScaleStyle(scale: 0.97))
            .accessibilityLabel(String(localized: "Synopsis de \(film.item.title)", bundle: .app))

            TimelineView(.everyMinute) { context in
                FiveMetaRow(
                    episodes: nil,
                    runtime: film.runtimeMinutes,
                    platform: platform(for: film),
                    fontSize: 13,
                    end: endDate(for: film, now: context.date)
                )
            }
        }
        .frame(maxWidth: .infinity)
        .id(film.id)
        .transition(.opacity)
    }

    /// La fin si on lançait maintenant ; avant l'arrivée du film, l'heure
    /// qu'il est, pour que les chiffres défilent jusqu'à la fin.
    private func endDate(for film: CineMatchFilm, now: Date) -> Date? {
        guard let minutes = film.runtimeMinutes, minutes > 0 else { return nil }
        return isRevealed ? now.addingTimeInterval(Double(minutes) * 60) : now
    }

    /// Après « Je le regarde » : la salle s'est éteinte, l'écran joue. On dit
    /// bon film, on rappelle l'heure de fin, et on peut rouvrir la
    /// plateforme. Plus de bouton galerie : la notification du lendemain
    /// demande comment c'était.
    private func launched(_ film: CineMatchFilm) -> some View {
        let end = (launchedAt ?? Date()).addingTimeInterval(Double(film.runtimeMinutes ?? 0) * 60)

        return VStack(spacing: 8) {
            Group {
                if film.isSeries {
                    Text("Bonne série !", bundle: .app)
                } else {
                    Text("Bon film !", bundle: .app)
                }
            }
            .planTitle(36)
            .foregroundStyle(Ink.ink)
            .multilineTextAlignment(.center)
            .accessibilityAddTraits(.isHeader)

            FiveMetaRow(
                episodes: nil,
                runtime: film.runtimeMinutes,
                platform: platform(for: film),
                fontSize: 13,
                title: film.item.title,
                end: (film.runtimeMinutes ?? 0) > 0 ? end : nil
            )

            VStack(spacing: 4) {
                if canLaunch(film) {
                    PlanButton(title: relaunchTitle(for: film)) {
                        openPlatform(for: film)
                    }
                }
                Button {
                    viewModel.backToHome()
                } label: {
                    Text("Retour à l'accueil", bundle: .app)
                        .planFont(13.5, weight: .medium)
                        .foregroundStyle(Ink.ink2)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: Metrics.control)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableScaleStyle(scale: 0.97))
            }
            .padding(.top, 14)
        }
        .frame(maxWidth: .infinity)
    }

    /// « Lancer sur Netflix » ; sans nom de plateforme, « Lancer le film ».
    private func relaunchTitle(for film: CineMatchFilm) -> String {
        if let platform = platform(for: film) {
            return String(localized: "Lancer sur \(platform.name)", bundle: .app)
        }
        return film.isSeries
            ? String(localized: "Lancer la série", bundle: .app)
            : String(localized: "Lancer le film", bundle: .app)
    }

    // MARK: - Les séquences

    /// L'entrée, une fois, à l'arrivée des films. Un toucher sur la salle la
    /// passe (`skipEntrance`).
    private func playEntrance() {
        guard current != nil else { return }
        guard !reduceMotion else {
            sequence = .still
            isDark = true
            isRevealed = true
            return
        }
        let start = Date()
        sequence = CineMatchRoomSequence(kind: .entrance, start: start)
        isRevealed = false
        isDark = false
        withAnimation(.easeInOut(duration: 0.7).delay(0.6)) { isDark = true }
        Task {
            // L'écran s'allume.
            try? await Task.sleep(for: .milliseconds(1100))
            guard sequence.start == start else { return }
            Haptics.impact(.medium, intensity: 0.7)
            // La lumière court sur les premiers rangs : le film se présente.
            try? await Task.sleep(for: .milliseconds(250))
            guard sequence.start == start else { return }
            withAnimation(.easeOut(duration: 0.45)) { isRevealed = true }
            try? await Task.sleep(for: .milliseconds(Int(sequence.duration * 1000) - 1250))
            guard sequence.start == start else { return }
            sequence = .still
        }
    }

    private func skipEntrance() {
        guard sequence.kind == .entrance else { return }
        sequence = .still
        withAnimation(.easeOut(duration: 0.2)) {
            isDark = true
            isRevealed = true
        }
    }

    /// Le changement de film : l'écran s'éteint, le film change dans le noir,
    /// l'écran se rallume. `change` est fait au moment où l'écran est noir.
    private func playSwap(change: (() -> Void)? = nil) {
        guard !reduceMotion else {
            change?()
            return
        }
        closeTrailer(animated: false)
        let start = Date()
        sequence = CineMatchRoomSequence(kind: .swap, start: start)
        isTurning = true
        Task {
            try? await Task.sleep(for: .milliseconds(Int(CineMatchRoomSequence.swapDarkAt * 1000)))
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) {
                change?()
                dragOffset = 0
            }
            try? await Task.sleep(for: .milliseconds(420))
            isTurning = false
            try? await Task.sleep(for: .milliseconds(400))
            guard sequence.start == start else { return }
            sequence = .still
        }
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

    /// L'écran suit le doigt, en résistant ; assez loin, ou assez vite, le
    /// film change. Balayer vers la droite amène le film suivant.
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard !isTurning, isRevealed else { return }
                let raw = value.translation.width
                let atEnd = (raw < 0 && index == 0) || (raw > 0 && index >= films.count - 1)
                dragOffset = atEnd ? raw * 0.3 : Self.resisted(raw, threshold: 90)
            }
            .onEnded { value in
                guard !isTurning, isRevealed else { return }
                let offset = dragOffset
                let direction = offset > 0 ? 1 : -1
                let velocity = value.velocity.width
                let target = index + direction
                let commits = films.indices.contains(target)
                    && (abs(offset) > 70 || (abs(velocity) > 550 && abs(offset) > 24))
                if commits {
                    turn(direction)
                } else {
                    withAnimation(Self.recenter) { dragOffset = 0 }
                }
            }
    }

    /// Le rappel au centre : l'écran est tenu par un ressort, pas posé.
    private static let recenter = Animation.spring(response: 0.36, dampingFraction: 0.62)

    /// Au-delà du seuil le doigt continue mais l'écran résiste, en s'approchant
    /// d'une limite sans jamais l'atteindre (même loi que `SwipeMotion`).
    private static func resisted(_ value: CGFloat, threshold: CGFloat) -> CGFloat {
        let magnitude = abs(value)
        guard magnitude > threshold else { return value }
        let slack = 84.0
        let compressed = CGFloat(slack * (1 - exp(-Double(magnitude - threshold) / slack)))
        return (value < 0 ? -1 : 1) * (threshold + compressed)
    }

    /// Passer au film d'à côté. Hors des bornes, l'écran bute et revient.
    private func turn(_ direction: Int) {
        guard mode == .five, !isTurning else { return }
        let target = index + direction
        guard films.indices.contains(target) else {
            bump(direction)
            return
        }
        Haptics.impact(.light, intensity: 0.6)
        move(to: target)
    }

    /// L'écran s'éteint et se rallume sur le film `target`.
    private func move(to target: Int) {
        guard films.indices.contains(target), target != index, !isTurning else { return }
        playSwap { viewModel.showCard(at: target) }
    }

    private func bump(_ direction: Int) {
        guard !reduceMotion else { return }
        withAnimation(.easeOut(duration: 0.12)) { dragOffset = CGFloat(direction) * 16 }
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
            if askingSeenID == film.id {
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
                markLinks(for: film)
            case .daily:
                // Un film du jour déjà vu : on le range, et un autre arrive.
                VStack(spacing: 0) {
                    alreadySeenLink(for: film)
                    backLink
                }
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
    /// marque comme un film vu, la carte suivante arrive, et il part avec les
    /// autres au remplacement.
    private func refuseLink(for film: CineMatchFilm) -> some View {
        Button {
            viewModel.markRefused(film)
            advanceAfterMark()
        } label: {
            HStack(spacing: 8) {
                Text(isSeries
                     ? String(localized: "Pas celle-là", bundle: .app)
                     : String(localized: "Pas celui-là", bundle: .app))
                    .planFont(14, weight: .medium)
                    .fixedSize()
                // La flèche dit ce qui suit : on passe au film suivant.
                FiveArrowGlyph(pointsRight: true)
                    .stroke(style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                    .frame(width: 14, height: 14)
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
    /// non. Parmi les cinq, il se marque et sera remplacé avec les autres ;
    /// proposé comme film du jour, un autre film du jour le remplace aussitôt.
    private func markSeen(_ film: CineMatchFilm, loved: Bool) {
        askingSeenID = nil
        let item = galleryItem(for: film)
        switch mode {
        case .five:
            viewModel.markSeen(film, loved: loved)
            libraryStore.addToGallery(item)
            if loved {
                // Rien n'a été annulé entre-temps : il est toujours marqué.
                loveOnceInGallery(item) { viewModel.marks[film.id] == .seen(loved: true) }
            }
            advanceAfterMark()
        case .daily:
            libraryStore.addToGallery(item)
            if loved {
                loveOnceInGallery(item) { true }
            }
            Task { await viewModel.replaceSeenDaily(film) }
        }
    }

    /// Le cœur attend que la galerie connaisse le film, faute de quoi le
    /// serveur n'aurait rien sur quoi le poser.
    private func loveOnceInGallery(_ item: MediaItem, stillWanted: @escaping () -> Bool) {
        Task {
            let clock = ContinuousClock()
            let deadline = clock.now + .seconds(8)
            while !libraryStore.isInGallery(item), clock.now < deadline {
                try? await Task.sleep(for: .milliseconds(150))
            }
            guard stillWanted() else { return }
            libraryStore.setLove(item, loved: true)
        }
    }

    /// Après « Pas celui-là » ou « Je l'ai déjà vu » : la carte se montre
    /// marquée un instant, puis la suivante encore à voir arrive, en faisant
    /// le tour. Tout est marqué : le calcul part, pour les cinq. On ne
    /// demandait plus de toucher « Les remplacer » ni de balayer soi-même :
    /// dire non à un film, c'est vouloir voir le suivant.
    private func advanceAfterMark() {
        guard viewModel.markedCount < films.count else {
            Task { await viewModel.replaceMarked() }
            return
        }
        let marked = films.map(\.id)
        let from = index
        Task {
            // Le temps de voir la carte prendre sa marque.
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 150 : 320))
            // Rien n'a bougé entre-temps : même carte, mêmes films.
            guard films.map(\.id) == marked, index == from, !isTurning else { return }
            let next = (1 ..< films.count)
                .map { (from + $0) % films.count }
                .first { viewModel.marks[films[$0].id] == nil }
            guard let next else { return }
            move(to: next)
        }
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
        closeTrailer(animated: false)
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
        // Le film commence : la salle s'éteint rang par rang, l'écran
        // s'élargit et se pose au milieu ; la plateforme s'ouvre une fois la
        // salle noire.
        launchedAt = Date()
        withAnimation(reduceMotion ? .easeOut(duration: 0.25) : .easeInOut(duration: 0.9)) {
            launch = 1
            isDark = true
        }
        Task {
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 250 : 950))
            openPlatform(for: film)
        }
    }

    /// Ouvre l'app native de la plateforme si elle est installée, sinon son
    /// site.
    private func openPlatform(for film: CineMatchFilm) {
        let platformIDs = preferredPlatformIDs
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

    /// La bande-annonce passe sur l'écran de la salle, élargi au format
    /// cinéma, la salle baissée. Sans clé YouTube, rien à jouer ici : on
    /// ouvre YouTube, comme avant.
    private func openTrailer(_ film: CineMatchFilm) {
        guard !isLaunched else { return }
        guard film.trailerKey?.isEmpty == false else {
            openTrailerOutside(film)
            return
        }
        isTrailerOpen = true
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.45, dampingFraction: 0.9)) {
            widen = 1
        }
    }

    private func closeTrailer(animated: Bool = true) {
        guard isTrailerOpen || widen > 0 else { return }
        isTrailerOpen = false
        if animated, !reduceMotion {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.95)) { widen = 0 }
        } else {
            widen = 0
        }
    }

    private func openTrailerOutside(_ film: CineMatchFilm) {
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
            status: film.status.map { Self.statusLine($0) },
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
    /// Séries : où en est l'histoire. Commencer une série annulée, c'est
    /// savoir qu'elle n'aura pas de fin.
    let status: String?
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

                if let status = content.status {
                    Text(status)
                        .planFont(12.5)
                        .foregroundStyle(Ink.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }

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
    /// Le titre en tête, après le lancement : « Drive · 1h40 · … ».
    var title: String? = nil
    /// L'heure de fin : « fin vers 23:47 ». Ses chiffres défilent quand elle
    /// change.
    var end: Date? = nil

    var body: some View {
        HStack(spacing: 0) {
            if let title {
                Text(title)
                    .planFont(fontSize, weight: .medium)
                    .foregroundStyle(Ink.ink)
                    .lineLimit(1)
                if hasEpisodes || hasRuntime || end != nil || platform != nil { dot }
            }
            if let episodes, hasEpisodes {
                Text(episodes == 1
                    ? String(localized: "1 épisode", bundle: .app)
                    : String(localized: "\(episodes) épisodes", bundle: .app))
                    .planFont(fontSize)
                    .monospacedDigit()
                    .foregroundStyle(Ink.ink2)
                if hasRuntime || end != nil || platform != nil { dot }
            }
            if let runtime, hasRuntime {
                Text(verbatim: Self.format(runtime))
                    .planFont(fontSize)
                    .monospacedDigit()
                    .foregroundStyle(Ink.ink2)
                if end != nil || platform != nil { dot }
            }
            if let end {
                HStack(spacing: 4) {
                    Text("fin vers", bundle: .app)
                        .planFont(fontSize)
                        .foregroundStyle(Ink.ink2)
                    Text(end, format: .dateTime.hour().minute())
                        .planFont(fontSize, weight: .medium)
                        .monospacedDigit()
                        .foregroundStyle(Ink.ink)
                        .contentTransition(.numericText(value: end.timeIntervalSince1970))
                        .animation(.snappy(duration: 0.6), value: end)
                }
                if platform != nil { dot }
            }
            if let platform {
                logo(platform)
            }
        }
        .frame(minHeight: 18)
    }

    private var hasEpisodes: Bool { (episodes ?? 0) > 0 }
    private var hasRuntime: Bool { (runtime ?? 0) > 0 }

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
