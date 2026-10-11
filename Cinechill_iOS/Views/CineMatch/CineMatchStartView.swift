//
//  CineMatchStartView.swift
//  Cinechill_iOS
//

import SwiftUI

/// Le départ de CinéMatch : un style, un de ses films comme point de départ,
/// un second film pour préciser la direction, puis « Comme Heat, mais… ? ».
/// Quatre touchers au plus, rien à écrire ; les deux derniers se passent
/// d'un toucher (« Pile comme Heat », « Pareil »).
///
/// Il remplace les deux questions et les quatre comparaisons (lot 1,
/// octobre 2026). L'écran des styles ne montre que ceux de la galerie, illustrés
/// par trois de ses affiches : on reconnaît ses propres films d'un coup d'œil,
/// sans lire un mot de plus. L'écran des films de départ montre six films de la
/// galerie dans ce style, variés, les coups de cœur d'abord.
///
/// C'est une page plate, comme les écrans de réglage, et elle porte aussi
/// l'attente des cinq et ses échecs : on ne change de décor qu'une fois les
/// cinq arrivés.
struct CineMatchStartView: View {
    let viewModel: CineMatchViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    /// « Un autre style » a été touché : les styles restants s'affichent sous
    /// les six.
    @State private var showsOtherStyles = false
    /// Le film touché (de départ ou second). Il s'allume avant qu'on parte,
    /// pour qu'il soit vu comme pris : sans ce temps, la page change sous le
    /// doigt.
    @State private var pressedFilmID: Int?
    /// La retouche touchée, `nil` dans la clé pour « Pareil ».
    @State private var pressedTweak: String?
    /// La hauteur du titre sous l'affiche suit la taille du texte : à 30 pt
    /// fixes, deux lignes agrandies étaient coupées à mi-hauteur.
    @ScaledMetric(relativeTo: .caption) private var captionHeight: CGFloat = 30

    private var isSeries: Bool { viewModel.format == .series }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            page
                .id(pageKey)
                .transition(.opacity)
        }
        .padding(.horizontal, Metrics.margin)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Ink.ground)
        .animation(.easeOut(duration: 0.2), value: pageKey)
        .onChange(of: viewModel.step) { _, _ in
            pressedFilmID = nil
            pressedTweak = nil
        }
        .onChange(of: viewModel.format) { _, _ in
            showsOtherStyles = false
        }
    }

    /// Ce qui fait changer de page : chaque écran, et l'arrivée des styles.
    private var pageKey: String {
        let failed = viewModel.errorMessage != nil
        switch viewModel.step {
        case .style: return "style-\(viewModel.styleTiles.isEmpty)-\(failed)"
        case .anchor: return "anchor-\(failed)"
        case .refine: return "refine-\(failed)"
        case .tweak: return "tweak-\(failed)"
        default: return "\(viewModel.step)-\(failed)"
        }
    }

    // MARK: - L'en-tête

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                viewModel.goBack()
            } label: {
                Text(backTitle)
                    .planFont(13, weight: .medium)
                    .foregroundStyle(Ink.ink2)
                    .padding(.trailing, 12)
                    .frame(minHeight: Metrics.control)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableScaleStyle(scale: 0.96))

            Spacer(minLength: 0)
        }
        .frame(minHeight: 34)
    }

    /// Des styles, on ressort ; plus loin, on revient d'un pas.
    private var backTitle: String {
        viewModel.step == .style
            ? String(localized: "Annuler", bundle: .app)
            : String(localized: "Retour", bundle: .app)
    }

    // MARK: - Les pages

    @ViewBuilder
    private var page: some View {
        if let message = viewModel.errorMessage {
            failure(message)
        } else {
            switch viewModel.step {
            case .style where viewModel.styleTiles.isEmpty && viewModel.isLoadingStyles:
                CinechillSpinner(size: 26)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel(String(localized: "Chargement…", bundle: .app))
            case .style where viewModel.styleTiles.isEmpty:
                // Le serveur rend toujours ses dix styles ; une réponse vide
                // ne laisse pas l'écran sans issue pour autant.
                PlanEmptyState(
                    title: String(localized: "Aucun style à proposer", bundle: .app),
                    message: isSeries
                        ? String(localized: "On peut quand même te proposer cinq séries.", bundle: .app)
                        : String(localized: "On peut quand même te proposer cinq films.", bundle: .app),
                    actionTitle: String(localized: "Peu importe, propose-moi", bundle: .app),
                    action: { Task { await viewModel.chooseAnyStyle() } }
                )
                .frame(maxHeight: .infinity)
            case .style:
                stylesPage
            case .anchor:
                anchorPage
            case .refine:
                refinePage
            case .tweak:
                tweakPage
            case .loadingFive:
                waiting
            default:
                Color.clear
            }
        }
    }

    private func questionTitle(_ text: String) -> some View {
        Text(text)
            .planFont(24, weight: .regular, design: .serif)
            .kerning(0.1)
            .lineSpacing(2)
            .foregroundStyle(Ink.ink)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 14)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: Les styles

    /// Deux colonnes de tuiles ; une seule quand le texte est agrandi au point
    /// que « Science-fiction et fantastique » ne tiendrait plus en deux lignes.
    private var styleColumns: Int { typeSize.isAccessibilitySize ? 1 : 2 }

    private var stylesPage: some View {
        let others = viewModel.otherStyles

        return ScrollViewReader { reader in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    questionTitle(String(localized: "Tu as envie de quoi ce soir ?", bundle: .app))

                    styleGrid(viewModel.mainStyles)
                        .padding(.top, 18)

                    if showsOtherStyles, !others.isEmpty {
                        styleGrid(others)
                            .padding(.top, Metrics.gutter)
                            .id("others")
                            .transition(.opacity)
                    }
                }
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    textLink(String(localized: "Peu importe, propose-moi", bundle: .app), tint: Ink.ink) {
                        Task { await viewModel.chooseAnyStyle() }
                    }
                    .disabled(viewModel.pendingStyle != nil)

                    if !showsOtherStyles, !others.isEmpty {
                        textLink(String(localized: "Un autre style", bundle: .app), tint: Ink.ink2) {
                            withAnimation(.easeOut(duration: 0.2)) { showsOtherStyles = true }
                            // Les styles ajoutés tombent sous les six : sans ce
                            // défilement, rien ne disait qu'ils étaient arrivés.
                            Task {
                                try? await Task.sleep(for: .milliseconds(60))
                                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
                                    reader.scrollTo("others", anchor: .top)
                                }
                            }
                        }
                        .disabled(viewModel.pendingStyle != nil)
                    }
                }
                .padding(.top, 6)
                .background(Ink.ground)
            }
        }
        .onAppear { prefetchTilePosters() }
        .onChange(of: viewModel.styleTiles) { _, _ in prefetchTilePosters() }
    }

    private func prefetchTilePosters() {
        PosterImageCache.shared.prefetch(viewModel.styleTiles.flatMap(\.films).map(\.posterURL))
    }

    /// Une grille et non une pile de rangées : chaque rangée prend la hauteur
    /// de sa tuile la plus haute, et ses voisines s'étirent jusqu'à elle.
    private func styleGrid(_ tiles: [CineMatchStyleTile]) -> some View {
        let columns = styleColumns
        let rows = stride(from: 0, to: tiles.count, by: columns).map {
            Array(tiles[$0 ..< min($0 + columns, tiles.count)])
        }

        return Grid(horizontalSpacing: Metrics.gutter, verticalSpacing: Metrics.gutter) {
            ForEach(rows, id: \.first?.style) { row in
                GridRow {
                    ForEach(row) { tile in
                        styleTile(tile)
                    }
                    // Une tuile seule sur la dernière rangée garde sa largeur
                    // d'une colonne.
                    ForEach(0 ..< (columns - row.count), id: \.self) { _ in
                        Color.clear.gridCellUnsizedAxes(.vertical)
                    }
                }
            }
        }
    }

    private func styleTile(_ tile: CineMatchStyleTile) -> some View {
        let isPending = viewModel.pendingStyle == tile.style
        let shape = RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)

        return Button {
            Task { await viewModel.chooseStyle(tile.style) }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                Text(tile.style.title)
                    .planFont(14, weight: .semibold)
                    .foregroundStyle(Ink.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 0)

                // Les films du style arrivent : la tuile prise le dit au lieu
                // de rester figée sous le doigt. Le projecteur se pose sur les
                // affiches et non à côté du nom, qu'il aurait fait passer à la
                // ligne au moment du toucher.
                Group {
                    if tile.films.isEmpty {
                        Text(isSeries
                             ? String(localized: "Aucune série de ta galerie", bundle: .app)
                             : String(localized: "Aucun film de ta galerie", bundle: .app))
                            .planFont(11.5)
                            .foregroundStyle(Ink.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        StyleTilePosters(films: tile.films)
                    }
                }
                .opacity(isPending ? 0.3 : 1)
                .overlay {
                    if isPending {
                        CinechillSpinner(size: 16)
                            .frame(width: 16, height: 16)
                            .transition(.opacity)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Ink.ground2, in: shape)
            .overlay(shape.strokeBorder(isPending ? Ink.ink : Ink.ruleSet, lineWidth: 1))
            .contentShape(shape)
            .animation(.easeOut(duration: 0.12), value: isPending)
        }
        .buttonStyle(PressableScaleStyle(scale: 0.97))
        .disabled(viewModel.pendingStyle != nil && !isPending)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tile.style.title)
        .accessibilityValue(
            isPending
                ? String(localized: "Chargement…", bundle: .app)
                : tile.films.map(\.title).joined(separator: ", ")
        )
        .accessibilityAddTraits(.isButton)
    }

    private func textLink(_ title: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .planFont(14, weight: .medium)
                .foregroundStyle(tint)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .frame(minHeight: Metrics.control)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableScaleStyle(scale: 0.97))
    }

    // MARK: Les films de départ

    /// Trois colonnes d'affiches ; deux quand le texte est agrandi, pour que
    /// les titres restent lisibles sous elles.
    private var anchorColumns: Int { typeSize.isAccessibilitySize ? 2 : 3 }

    @ViewBuilder
    private var anchorPage: some View {
        if let starters = viewModel.starterPage, !starters.films.isEmpty {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    questionTitle(isSeries
                        ? String(localized: "Une série proche de… ?", bundle: .app)
                        : String(localized: "Un film proche de… ?", bundle: .app))

                    Text(starters.style.title)
                        .planLabel()
                        .foregroundStyle(Ink.ink2)
                        .padding(.top, 6)

                    posterGrid(starters.films, from: .anchor) { film in
                        await viewModel.chooseAnchor(film)
                    }
                        .id(starters.page)
                        .transition(.opacity)
                        .padding(.top, 16)
                        .opacity(viewModel.isLoadingStarters ? 0.4 : 1)
                }
                .padding(.bottom, 12)
                .animation(.easeOut(duration: 0.2), value: starters.page)
                .animation(.easeOut(duration: 0.15), value: viewModel.isLoadingStarters)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                // Un style qui tient sur une page n'a pas d'autres films : le
                // lien ramènerait les mêmes.
                if starters.hasMore {
                    Button {
                        Task { await viewModel.moreStarters() }
                    } label: {
                        Group {
                            if viewModel.isLoadingStarters {
                                CinechillSpinner(size: 16)
                                    .frame(width: 16, height: 16)
                            } else {
                                Text("Pas ceux-là", bundle: .app)
                                    .planFont(14, weight: .medium)
                                    .foregroundStyle(Ink.ink)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: Metrics.control)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableScaleStyle(scale: 0.97))
                    .disabled(viewModel.isLoadingStarters || pressedFilmID != nil)
                    .accessibilityLabel(
                        viewModel.isLoadingStarters
                            ? String(localized: "Chargement…", bundle: .app)
                            : String(localized: "Pas ceux-là", bundle: .app)
                    )
                    .padding(.top, 6)
                    .background(Ink.ground)
                }
            }
            .onAppear { prefetchStarterPosters() }
            .onChange(of: starters.page) { _, _ in prefetchStarterPosters() }
        } else {
            PlanEmptyState(
                title: isSeries
                    ? String(localized: "Aucune série dans ce style", bundle: .app)
                    : String(localized: "Aucun film dans ce style", bundle: .app),
                message: String(localized: "Choisis un autre style, ou touche « Peu importe, propose-moi ».", bundle: .app),
                actionTitle: String(localized: "Choisir un autre style", bundle: .app),
                action: { viewModel.goBack() }
            )
            .frame(maxHeight: .infinity)
        }
    }

    private func prefetchStarterPosters() {
        PosterImageCache.shared.prefetch((viewModel.starterPage?.films ?? []).map(\.posterURL))
    }

    /// La grille d'affiches des films de départ et des seconds films. `step`
    /// est l'écran qu'elle sert : si le modèle n'en part pas, le geste a été
    /// refusé et l'affiche touchée ne reste pas prise.
    private func posterGrid(
        _ films: [CineMatchGalleryFilm],
        from step: CineMatchViewModel.Step,
        choose: @escaping (CineMatchGalleryFilm) async -> Void
    ) -> some View {
        let columns = Array(
            repeating: GridItem(.flexible(), spacing: Metrics.gutter, alignment: .top),
            count: anchorColumns
        )
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
            ForEach(films) { film in
                posterTile(film, from: step, choose: choose)
            }
        }
    }

    private func posterTile(
        _ film: CineMatchGalleryFilm,
        from step: CineMatchViewModel.Step,
        choose: @escaping (CineMatchGalleryFilm) async -> Void
    ) -> some View {
        let isPressed = pressedFilmID == film.id
        // Les voisins du film de départ arrivent : l'affiche prise le dit.
        let isWaiting = isPressed && viewModel.isLoadingNear
        let shape = RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)

        return Button {
            guard pressedFilmID == nil, !viewModel.isLoadingStarters else { return }
            pressedFilmID = film.id
            Task {
                // Le temps de voir l'affiche prise, puis on part.
                try? await Task.sleep(for: .milliseconds(150))
                await choose(film)
                // Le modèle a refusé le geste : l'affiche ne reste pas prise.
                if viewModel.step == step { pressedFilmID = nil }
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                PosterImageView(url: film.posterURL, contentMode: .fill)
                    .aspectRatio(2 / 3, contentMode: .fit)
                    .clipShape(shape)
                    .overlay(shape.strokeBorder(Ink.ink.opacity(0.18), lineWidth: 1))
                    // Le cadre de l'affiche prise, décollé d'elle comme sur la
                    // maquette, et le point « acquis ».
                    .overlay {
                        if isPressed {
                            shape
                                .strokeBorder(Ink.ink, lineWidth: 1.5)
                                .padding(-4)
                                .transition(.opacity)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if isPressed {
                            PlanLight()
                                .padding(6)
                        }
                    }
                    .overlay {
                        if isWaiting {
                            CinechillSpinner(size: 18)
                                .frame(width: 34, height: 34)
                                .background(Ink.ground.opacity(0.8), in: Circle())
                                .transition(.opacity)
                        }
                    }

                Text(film.title)
                    .planFont(12)
                    .foregroundStyle(Ink.ink2)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, minHeight: captionHeight, alignment: .topLeading)
            }
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.12), value: isPressed)
            .animation(.easeOut(duration: 0.15), value: isWaiting)
        }
        .buttonStyle(PressableScaleStyle(scale: 0.97))
        .disabled(pressedFilmID != nil && !isPressed)
        .accessibilityLabel(film.title)
        .accessibilityValue(isWaiting ? String(localized: "Chargement…", bundle: .app) : "")
        .accessibilityAddTraits(isPressed ? [.isSelected] : [])
    }

    // MARK: Le second film

    /// « Plutôt du côté de… ? » : six films de la galerie proches du film de
    /// départ, qui tirent chacun dans une direction. « Pile comme Heat » passe
    /// l'écran.
    @ViewBuilder
    private var refinePage: some View {
        if let anchor = viewModel.anchor, let near = viewModel.nearPage {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    questionTitle(String(localized: "Plutôt du côté de… ?", bundle: .app))

                    Text(String(localized: "Proche de \(anchor.title)", bundle: .app))
                        .planFont(12.5)
                        .foregroundStyle(Ink.ink2)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)

                    posterGrid(near.films, from: .refine) { film in
                        await viewModel.chooseSecond(film)
                    }
                    .padding(.top, 16)
                }
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                textLink(String(localized: "Pile comme \(anchor.title)", bundle: .app), tint: Ink.ink) {
                    Task { await viewModel.skipSecond() }
                }
                .disabled(pressedFilmID != nil)
                .padding(.top, 6)
                .background(Ink.ground)
            }
            .onAppear { PosterImageCache.shared.prefetch(near.films.map(\.posterURL)) }
        }
    }

    // MARK: La retouche

    /// « Comme Heat, mais… ? » : ce qu'on change au film de départ. Chaque
    /// réponse dit ce qu'elle fait, et seules celles qui ont un sens pour ce
    /// film sont là. « Pareil » passe l'écran.
    @ViewBuilder
    private var tweakPage: some View {
        if let anchor = viewModel.anchor, let near = viewModel.nearPage {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    questionTitle(String(localized: "Comme \(anchor.title), mais… ?", bundle: .app))

                    if let second = viewModel.secondFilm {
                        Text(String(localized: "Proche de \(anchor.title) et \(second.title)", bundle: .app))
                            .planFont(12.5)
                            .foregroundStyle(Ink.ink2)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 6)
                    }

                    VStack(spacing: 7) {
                        tweakRow(nil, anchor: anchor)
                        ForEach(near.tweaks, id: \.self) { tweak in
                            tweakRow(tweak, anchor: anchor)
                        }
                    }
                    .padding(.top, 18)
                }
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private func tweakRow(_ tweak: CineMatchTweak?, anchor: CineMatchGalleryFilm) -> some View {
        let key = tweak?.rawValue ?? "same"
        let isOn = pressedTweak == key
        let title = tweak?.title(series: isSeries) ?? String(localized: "Pareil", bundle: .app)
        let consequence = tweakConsequence(tweak, anchor: anchor)
        let shape = RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)

        return Button {
            guard pressedTweak == nil else { return }
            pressedTweak = key
            Task {
                // La ligne s'allume, puis on part : la réponse est vue prise.
                try? await Task.sleep(for: .milliseconds(150))
                await viewModel.chooseTweak(tweak)
                if viewModel.step == .tweak { pressedTweak = nil }
            }
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .planFont(15, weight: .medium)
                    .foregroundStyle(isOn ? Ink.ground : Ink.ink)
                Text(consequence)
                    .planFont(12)
                    .foregroundStyle(isOn ? Ink.ground.opacity(0.62) : Ink.ink2)
            }
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: 56)
            .background(isOn ? Ink.ink : Ink.ground2, in: shape)
            .overlay(shape.strokeBorder(isOn ? Ink.ink : Ink.ruleSet, lineWidth: 1))
            .contentShape(shape)
            .animation(.easeOut(duration: 0.12), value: isOn)
        }
        .buttonStyle(PressableScaleStyle(scale: 0.985))
        .disabled(pressedTweak != nil && !isOn)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }

    /// Ce que fait la réponse, dit avec le film de départ : « Sortis à partir
    /// de 2000 » plutôt que « plus récents ».
    private func tweakConsequence(_ tweak: CineMatchTweak?, anchor: CineMatchGalleryFilm) -> String {
        switch tweak {
        case nil:
            return String(localized: "Au plus près de \(anchor.title)", bundle: .app)
        case .recent:
            guard let year = anchor.releaseDate.flatMap({ Int($0.prefix(4)) }) else {
                return isSeries
                    ? String(localized: "Des séries plus récentes", bundle: .app)
                    : String(localized: "Des films plus récents", bundle: .app)
            }
            // La décennie suivante : c'est ce que le serveur exige. En texte,
            // pour qu'une année ne prenne pas d'espace de milliers.
            let from = String(year / 10 * 10 + 10)
            return isSeries
                ? String(localized: "Sorties à partir de \(from)", bundle: .app)
                : String(localized: "Sortis à partir de \(from)", bundle: .app)
        case .lesser:
            return isSeries
                ? String(localized: "Des séries moins vues que \(anchor.title)", bundle: .app)
                : String(localized: "Des films moins vus que \(anchor.title)", bundle: .app)
        case .lighter:
            return String(localized: "Avec plus d'humour ou de douceur", bundle: .app)
        case .darker:
            return String(localized: "Avec plus de tension ou de noirceur", bundle: .app)
        }
    }

    // MARK: L'attente et l'échec

    /// L'attente des cinq : le projecteur tourne, et une phrase dit ce qui se
    /// passe, en nommant le film de départ. Rien qui prétende une durée.
    private var waiting: some View {
        VStack(spacing: 14) {
            CinechillSpinner(size: 28)
            Text(waitingText)
                .planFont(13.5)
                .foregroundStyle(Ink.ink2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var waitingText: String {
        switch (viewModel.anchor, isSeries) {
        case (let anchor?, false):
            String(localized: "On cherche des films proches de \(anchor.title)…", bundle: .app)
        case (let anchor?, true):
            String(localized: "On cherche des séries proches de \(anchor.title)…", bundle: .app)
        case (nil, false):
            String(localized: "On cherche tes cinq films…", bundle: .app)
        case (nil, true):
            String(localized: "On cherche tes cinq séries…", bundle: .app)
        }
    }

    /// Aucun film pour cette soirée : rien n'a échoué, et « Réessayer » ne
    /// changerait rien. On le dit, et la seule issue utile est l'accueil, où
    /// se règle la soirée.
    @ViewBuilder
    private func failure(_ message: String) -> some View {
        if viewModel.failureIsNoCandidates {
            PlanEmptyState(
                title: isSeries
                    ? String(localized: "Aucune série pour ce soir", bundle: .app)
                    : String(localized: "Aucun film pour ce soir", bundle: .app),
                message: message,
                actionTitle: String(localized: "Retour à l'accueil", bundle: .app),
                action: { viewModel.backToHome() }
            )
            .frame(maxHeight: .infinity)
        } else {
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
        }
    }
}

// MARK: - Les affiches d'une tuile

/// Trois affiches de la galerie, côte à côte, sans titre : on reconnaît ses
/// propres films sans les lire. Une case reste vide, au trait, quand le style
/// en compte moins de trois : la rangée garde sa hauteur.
private struct StyleTilePosters: View {
    let films: [CineMatchGalleryFilm]

    private static let slots = 3

    /// Sur une colonne, au texte agrandi, la tuile prend toute la largeur :
    /// les affiches ne la suivent pas au-delà de cette mesure.
    private static let maxWidth: CGFloat = 180

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0 ..< Self.slots, id: \.self) { slot in
                let shape = RoundedRectangle(cornerRadius: 2, style: .continuous)
                Group {
                    if slot < films.count {
                        PosterImageView(url: films[slot].posterURL, contentMode: .fill)
                            .clipShape(shape)
                            .overlay(shape.strokeBorder(Ink.ink.opacity(0.18), lineWidth: 1))
                    } else {
                        shape.strokeBorder(Ink.rule, lineWidth: 1)
                    }
                }
                .aspectRatio(2 / 3, contentMode: .fit)
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: Self.maxWidth, alignment: .leading)
        .accessibilityHidden(true)
    }
}

// MARK: - Les retouches

extension CineMatchTweak {
    /// Le nom de la réponse, accordé au film ou à la série.
    func title(series: Bool) -> String {
        switch (self, series) {
        case (.recent, false): String(localized: "Plus récent", bundle: .app)
        case (.recent, true): String(localized: "Plus récente", bundle: .app)
        case (.lesser, false): String(localized: "Moins connu", bundle: .app)
        case (.lesser, true): String(localized: "Moins connue", bundle: .app)
        case (.lighter, false): String(localized: "Plus léger", bundle: .app)
        case (.lighter, true): String(localized: "Plus légère", bundle: .app)
        case (.darker, _): String(localized: "Plus sombre", bundle: .app)
        }
    }

    /// La même, en fin de la ligne des cinq : « Un film proche de Heat,
    /// plus récent ».
    func suffix(series: Bool) -> String {
        switch (self, series) {
        case (.recent, false): String(localized: "plus récent", bundle: .app)
        case (.recent, true): String(localized: "plus récente", bundle: .app)
        case (.lesser, false): String(localized: "moins connu", bundle: .app)
        case (.lesser, true): String(localized: "moins connue", bundle: .app)
        case (.lighter, false): String(localized: "plus léger", bundle: .app)
        case (.lighter, true): String(localized: "plus légère", bundle: .app)
        case (.darker, _): String(localized: "plus sombre", bundle: .app)
        }
    }
}

// MARK: - Les noms des styles

// Une propriété calculée et non une table statique : la langue peut changer
// en cours de route, et une chaîne résolue une fois ne suivrait pas.

extension CineMatchStyle {
    var title: String {
        switch self {
        case .thriller: String(localized: "Thriller", bundle: .app)
        case .action: String(localized: "Action et aventure", bundle: .app)
        case .scifi: String(localized: "Science-fiction et fantastique", bundle: .app)
        case .comedy: String(localized: "Comédies", bundle: .app)
        case .drama: String(localized: "Drames", bundle: .app)
        case .romance: String(localized: "Romances", bundle: .app)
        case .horror: String(localized: "Horreur", bundle: .app)
        case .animation: String(localized: "Animation et famille", bundle: .app)
        case .history: String(localized: "Guerre et histoire", bundle: .app)
        case .documentary: String(localized: "Documentaires", bundle: .app)
        }
    }
}
