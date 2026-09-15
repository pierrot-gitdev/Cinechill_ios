//
//  CineMatchHomeView.swift
//  Cinechill_iOS
//

import SwiftUI

/// L'accueil de CinéMatch : un salon, une télé allumée, deux entrées.
///
/// On ne choisit pas un film devant un formulaire : on est chez soi, assis
/// devant l'écran. La télé porte les deux seuls chemins de l'accueil, comme le
/// menu d'une box ; la ligne en surbrillance prend le papier, l'aplat de
/// l'action principale, et l'autre reste à l'écran. Au-dessus, le scénario de
/// la soirée dit ce qui filtrera la recherche.
///
/// **La géométrie est celle du prototype** (`measure()` en mode salon et
/// `drawSalon()`), transcrite à la mesure près : la télé se dimensionne sur la
/// place laissée entre le bandeau et le bas de l'onglet, le canapé garde de
/// l'air sous lui, et ce qui reste se partage entre le mur et le sol. C'est ce
/// qui fait tenir la même pièce de l'iPhone SE au Pro Max.
struct CineMatchHomeView: View {
    let viewModel: CineMatchViewModel
    let onProfileTap: () -> Void

    @EnvironmentObject private var libraryStore: LibraryStore
    @Environment(MediaCatalog.self) private var catalog

    /// Les deux entrées de la télé. Visibles du fichier : la porte en peint
    /// l'image fixe (`SalonPainter.paintMenuStill`).
    fileprivate enum Entry: CaseIterable {
        case guided, daily

        var title: String {
            switch self {
            case .guided: String(localized: "Trouver mon film", bundle: .app)
            case .daily: String(localized: "La proposition du jour", bundle: .app)
            }
        }
    }

    /// La ligne en surbrillance. Elle suit le doigt qui se pose, comme la
    /// télécommande suit les flèches, et la première est allumée d'office.
    @State private var focusedEntry: Entry = .guided
    /// L'entrée choisie, le temps de la quitter : aucun second tap ne part.
    @State private var pendingEntry: Entry?
    @State private var showSituation = false
    /// Mesurés plutôt que supposés : la télé se cale sous eux.
    ///
    /// Le bas de l'en-tête se lit dans l'espace global, et non comme la zone
    /// sûre plus la hauteur de l'en-tête : sous `ignoresSafeArea`, le
    /// `GeometryReader` voit une zone sûre haute de zéro, et le bandeau
    /// remontait sous l'en-tête de toute la hauteur de la barre d'état.
    @State private var headerBottom: CGFloat = SalonGeometry.typicalChromeBottom
    @State private var stripHeight: CGFloat = SalonGeometry.typicalStripHeight

    var body: some View {
        GeometryReader { proxy in
            let chromeBottom = max(0, headerBottom - proxy.frame(in: .global).minY)
            let room = SalonGeometry(
                width: proxy.size.width,
                height: proxy.size.height,
                chromeBottom: chromeBottom,
                stripHeight: stripHeight
            )
            let stripWidth = max(0, proxy.size.width - 2 * Metrics.margin)

            ZStack(alignment: .topLeading) {
                SalonBackdrop(room: room)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .accessibilityHidden(true)

                scenarioStrip(width: stripWidth)
                    .frame(width: stripWidth)
                    .onGeometryChange(for: CGFloat.self) { geometry in
                        geometry.size.height
                    } action: { height in
                        stripHeight = height
                    }
                    .offset(x: Metrics.margin, y: chromeBottom + 6)

                tvScreen(room)
                    .frame(width: room.screenWidth, height: room.screenHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                    .offset(x: room.screenLeft, y: room.screenTop)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        // Le mur monte derrière la barre d'état : la pièce ne s'arrête pas au
        // bord de la zone sûre. Le bas, lui, s'arrête sur la barre d'onglets.
        .ignoresSafeArea(edges: .top)
        .overlay(alignment: .top) {
            AppHeaderView(
                title: String(localized: "CinéMatch", bundle: .app),
                onProfileTap: onProfileTap
            )
            .onGeometryChange(for: CGFloat.self) { geometry in
                geometry.frame(in: .global).maxY
            } action: { bottom in
                headerBottom = bottom
            }
        }
        .sheet(isPresented: $showSituation) {
            CineMatchSituationSheet(viewModel: viewModel, onClose: { showSituation = false })
                .environmentObject(libraryStore)
                .environment(catalog)
        }
        .task { await catalog.loadIfNeeded() }
    }

    // MARK: - Le scénario de la soirée

    /// Un seul contrôle, qui se lit comme un bouton : une ligne de titre qui
    /// porte « Modifier », puis trois colonnes nommées. Trois valeurs séparées
    /// par des points ne disaient pas à quoi chacune se rapportait.
    private func scenarioStrip(width: CGFloat) -> some View {
        let columnWidth = width / 3

        return Button {
            Haptics.selection()
            showSituation = true
        } label: {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Text("Le scénario de la soirée", bundle: .app)
                        .planLabel()
                        .foregroundStyle(Ink.ink2)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    HStack(spacing: 5) {
                        Image(systemName: "pencil")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Modifier", bundle: .app)
                            .font(.system(size: 11.5, weight: .semibold))
                    }
                    .foregroundStyle(Ink.ink)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .overlay(alignment: .bottom) { PlanEdge() }

                HStack(spacing: 0) {
                    scenarioColumn(String(localized: "Avec qui", bundle: .app), width: columnWidth, showsRule: true) {
                        scenarioValue(viewModel.situation.company.scenarioLabel)
                    }
                    scenarioColumn(String(localized: "Durée", bundle: .app), width: columnWidth, showsRule: true) {
                        scenarioValue(viewModel.situation.duration.scenarioLabel)
                    }
                    scenarioColumn(String(localized: "Plateformes", bundle: .app), width: columnWidth, showsRule: false) {
                        platformsValue
                    }
                }
            }
            .background(Ink.ground.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                    .strokeBorder(Ink.ruleSet, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableScaleStyle(scale: 0.99))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(scenarioAccessibilityLabel)
        .accessibilityAddTraits(.isButton)
    }

    private func scenarioColumn<Value: View>(
        _ label: String,
        width: CGFloat,
        showsRule: Bool,
        @ViewBuilder value: () -> Value
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10.5))
                .foregroundStyle(Ink.ink2)
                .lineLimit(1)
            value()
                .frame(height: 20, alignment: .leading)
        }
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .padding(.top, 7)
        .padding(.bottom, 8)
        .frame(width: width, alignment: .leading)
        .overlay(alignment: .trailing) {
            if showsRule {
                Rectangle()
                    .fill(Ink.rule)
                    .frame(width: 1)
            }
        }
    }

    private func scenarioValue(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Ink.ink)
            .lineLimit(1)
    }

    /// Les plateformes retenues, dans l'ordre du répertoire. Celles que le
    /// répertoire ne connaît pas encore (il se charge) suivent, sans logo.
    private var chosenPlatforms: [(id: String, platform: StreamingPlatform?)] {
        let ids = libraryStore.preferredPlatformIDs
        let known = catalog.platforms.filter { ids.contains($0.id) }
        let knownIDs = Set(known.map(\.id))
        let unknown = ids.subtracting(knownIDs).sorted()
        return known.map { (id: $0.id, platform: Optional($0)) }
            + unknown.map { (id: $0, platform: nil) }
    }

    /// Jusqu'à trois logos ; au-delà, deux logos et « +N », pour ne jamais
    /// rogner la colonne.
    @ViewBuilder
    private var platformsValue: some View {
        let chosen = chosenPlatforms
        if chosen.isEmpty {
            scenarioValue(String(localized: "Aucune", bundle: .app))
        } else {
            let shown = chosen.count > 3 ? Array(chosen.prefix(2)) : chosen
            HStack(spacing: 3) {
                ForEach(shown, id: \.id) { entry in
                    ScenarioPlatformLogo(platform: entry.platform)
                }
                if chosen.count > shown.count {
                    Text(verbatim: "+\(chosen.count - shown.count)")
                        .font(.system(size: 10.5, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Ink.ink2)
                        .padding(.leading, 3)
                        .fixedSize()
                }
            }
        }
    }

    private var scenarioAccessibilityLabel: String {
        let names = chosenPlatforms.compactMap { $0.platform?.name }
        let platforms = names.isEmpty
            ? String(localized: "Aucune", bundle: .app)
            : names.joined(separator: ", ")
        let company = viewModel.situation.company.scenarioLabel
        let duration = viewModel.situation.duration.scenarioLabel
        return String(
            localized: "Modifier le scénario de la soirée. Avec qui : \(company). Durée : \(duration). Plateformes : \(platforms).",
            bundle: .app
        )
    }

    // MARK: - La télé

    /// L'écran de la télé : le sur-titre, puis les deux lignes, proportionnées
    /// sur l'écran et non sur le téléphone.
    private func tvScreen(_ room: SalonGeometry) -> some View {
        let menu = room.menu

        return VStack(spacing: menu.headGap) {
            Text("Ta soirée Cinechill", bundle: .app)
                .font(.system(size: menu.eyebrowSize, weight: .semibold))
                .tracking(menu.eyebrowSize * 0.16)
                .textCase(.uppercase)
                .foregroundStyle(CinechillPalette.wallHigh.opacity(0.55))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: menu.rowGap) {
                ForEach(Entry.allCases, id: \.self) { entry in
                    entryRow(entry, menu: menu)
                }
            }
            .frame(width: menu.width)
        }
        .padding(.vertical, menu.paddingV)
        .padding(.horizontal, menu.paddingH)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(Metrics.shift, value: focusedEntry)
    }

    /// Une ligne du menu. Sélectionnée ou non, **elle garde sa largeur** : ni
    /// agrandissement ni anneau, seul le fond passe au papier et le chevron
    /// apparaît. Un toucher choisit tout de suite.
    private func entryRow(_ entry: Entry, menu: SalonMenuMetrics) -> some View {
        let isOn = focusedEntry == entry
        let isLoading = pendingEntry == entry && entry == .daily

        return Button {
            choose(entry)
        } label: {
            HStack(spacing: 10) {
                Text(entry.title)
                    .font(.system(size: menu.fontSize, weight: isOn ? .semibold : .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Spacer(minLength: 0)

                EntryChevron()
                    .stroke(style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                    .frame(width: menu.chevronSize, height: menu.chevronSize)
                    .opacity(isOn ? 1 : 0)
                    .offset(x: isOn ? 0 : -4)
            }
            .foregroundStyle(isOn ? Ink.ground : Self.screenInk.opacity(0.8))
            .padding(.horizontal, menu.rowPaddingH)
            .frame(maxWidth: .infinity, minHeight: menu.rowHeight)
            .background(
                RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                    .fill(isOn ? Ink.paper : Self.screenInk.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                    .strokeBorder(isOn ? Ink.paper : Self.screenInk.opacity(0.18), lineWidth: 1)
            )
            .overlay(alignment: .bottomLeading) {
                if isLoading { EntryLoadingRule() }
            }
            .clipShape(RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous))
            .opacity(pendingEntry == entry ? 0.92 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(EntryPressStyle(onPress: { focusedEntry = entry }))
        .accessibilityLabel(entry.title)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityAddTraits(isLoading ? .updatesFrequently : [])
    }

    /// Le blanc bleuté de ce qui est affiché par l'écran, et non posé sur la
    /// page. Calculé : une couleur n'a rien à craindre d'un `static let`, mais
    /// la règle se tient mieux sans exception.
    fileprivate static var screenInk: Color { Color(hex: 0xF2F7FB) }

    private func choose(_ entry: Entry) {
        guard pendingEntry == nil else { return }
        focusedEntry = entry
        pendingEntry = entry
        Haptics.selection()
        Task {
            // La ligne s'allume et marque la pression avant qu'on parte : sans
            // ce temps, le toucher ne se voit pas.
            try? await Task.sleep(for: .milliseconds(160))
            switch entry {
            case .guided:
                viewModel.startGuided()
            case .daily:
                await viewModel.openDaily()
            }
            pendingEntry = nil
        }
    }
}

// MARK: - Le menu de la télé

/// Allume la ligne dès que le doigt se pose, avant même qu'il se lève : c'est
/// la surbrillance qui suit, comme sur une télé.
private struct EntryPressStyle: ButtonStyle {
    let onPress: () -> Void

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { onPress() }
            }
    }
}

/// Le chevron du prototype : grille de 24, « M9 6 l6 6 -6 6 ».
private struct EntryChevron: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 9 * scale, y: rect.minY + 6 * scale))
        path.addLine(to: CGPoint(x: rect.minX + 15 * scale, y: rect.minY + 12 * scale))
        path.addLine(to: CGPoint(x: rect.minX + 9 * scale, y: rect.minY + 18 * scale))
        return path
    }
}

/// L'attente de la proposition du jour, jouée dans la ligne comme dans
/// `PlanButton` : un filet de 2 pt parcourt son bord bas.
private struct EntryLoadingRule: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var travel: CGFloat = -0.45

    var body: some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(Ink.ground.opacity(0.4))
                .frame(width: geometry.size.width * 0.45, height: 2)
                .offset(x: travel * geometry.size.width)
                .onAppear {
                    guard !reduceMotion else { travel = 0.275; return }
                    withAnimation(.easeInOut(duration: 1.05).repeatForever(autoreverses: false)) {
                        travel = 1
                    }
                }
        }
        .frame(height: 2)
    }
}

/// Un logo de plateforme à la taille du bandeau, et ses deux lettres quand le
/// logo manque, comme `PlatformGrid`.
private struct ScenarioPlatformLogo: View {
    let platform: StreamingPlatform?

    var body: some View {
        Group {
            if let url = platform?.logoURL {
                PosterImageView(url: url)
            } else {
                Text(verbatim: platform?.shortLabel ?? "")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Ink.ink2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Ink.ground3)
            }
        }
        .frame(width: 20, height: 20)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous))
    }
}

// MARK: - La géométrie du salon

/// Les mesures de la pièce, en points, transcrites de `measure()` (mode
/// salon) du prototype.
///
/// Du haut vers le bas : la télé, son pied, le meuble, puis le canapé posé
/// juste devant le meuble. Le canapé garde de l'air au-dessus de la barre du
/// bas (20 pt au moins) ; ce qui reste va sous lui, et un peu au mur au-dessus
/// de la télé. L'écran garde 146 pt de haut au moins pour ses deux lignes.
///
/// L'origine est le haut de l'écran physique, barre d'état comprise ; le bas
/// est le haut de la barre d'onglets, qui dans l'app est une sœur du contenu et
/// ne le recouvre pas.
nonisolated struct SalonGeometry: Equatable {
    let width: CGFloat
    let height: CGFloat
    /// L'unité de dessin : 1 au gabarit du prototype.
    let scale: CGFloat
    /// Le haut du cadre de la télé.
    let top: CGFloat
    let tvLeft: CGFloat
    let tvWidth: CGFloat
    let tvHeight: CGFloat
    let screenWidth: CGFloat
    let screenHeight: CGFloat
    let bezel: CGFloat
    let chin: CGFloat
    let couchWidth: CGFloat
    let couchTop: CGFloat

    /// - Parameters:
    ///   - chromeBottom: le bas de l'en-tête, barre d'état comprise.
    ///   - stripHeight: la hauteur du bandeau du scénario.
    init(width: CGFloat, height: CGFloat, chromeBottom: CGFloat, stripHeight: CGFloat) {
        let cw = max(1, width)
        let ch = max(1, height)
        let tabsTop = ch
        let t0 = (chromeBottom + 6 + stripHeight + 14).rounded()
        let availH = tabsTop - t0
        let padMin = max(20, ch * 0.035).rounded()
        // La hauteur du canapé à l'image vaut 42 % de sa largeur (voir le dessin).
        let wMax = min(cw * 0.94, 520)
        let ratio: CGFloat = 0.42
        let gapW = min(18, max(8, availH * 0.02)).rounded()
        let couchNeed = (wMax * ratio).rounded()
        let couchMin = min(couchNeed, max(60, availH * 0.26)).rounded()
        let sc = max(0.7, min(cw * 0.86 / 310, (availH - couchMin - gapW - padMin) / 222))
        func pxs(_ v: CGFloat) -> CGFloat { max(1, (v * sc).rounded()) }

        let iw = (300 * sc).rounded()
        let ih = max(146, iw * 9 / 16).rounded()
        let bez = max(4, (5 * sc).rounded())
        let chinH = max(7, (9 * sc).rounded())
        let tw = iw + 2 * bez
        let th = bez + ih + chinH
        // Les mêmes mesures que le dessin : cadre, cou, socle, meuble, pieds.
        let stackToFloor = th + pxs(7) + max(2, pxs(3)) + pxs(22) + pxs(5)
        // Le surplus se partage : jusqu'à 45 % au mur au-dessus de la télé
        // (72 pt au plus), le reste en air sous le canapé.
        let extra = max(0, availH - stackToFloor - gapW - couchNeed - padMin)
        let tvTop = t0 + min(extra * 0.45, 72).rounded()
        let floorY = tvTop + stackToFloor

        var couchW = wMax
        var couchY = floorY + gapW
        let fit = tabsTop - padMin - couchY
        if couchW * ratio > fit {
            // Pas assez de hauteur : le canapé rétrécit jusqu'à 72 % de l'écran,
            // puis remonte devant le bas du meuble.
            couchW = max(cw * 0.72, fit / ratio)
            if couchW * ratio > fit {
                couchY = max(
                    floorY - ((pxs(22) + pxs(5)) * 0.9).rounded(),
                    tabsTop - padMin - (couchW * ratio).rounded()
                )
            }
        }

        self.width = cw
        self.height = ch
        self.scale = sc
        self.top = tvTop
        self.tvLeft = ((cw - tw) / 2).rounded()
        self.tvWidth = tw
        self.tvHeight = th
        self.screenWidth = iw
        self.screenHeight = ih
        self.bezel = bez
        self.chin = chinH
        self.couchWidth = couchW
        self.couchTop = couchY.rounded()
    }

    var screenLeft: CGFloat { tvLeft + bezel }
    var screenTop: CGFloat { top + bezel }

    var menu: SalonMenuMetrics { SalonMenuMetrics(room: self) }

    /// Le bas de l'en-tête avant toute mesure, barre d'état comprise : celui
    /// d'un iPhone à encoche (47 + 49). La mesure le remplace au premier
    /// passage de mise en page.
    static var typicalChromeBottom: CGFloat { 96 }
    /// La hauteur du bandeau du scénario avant mesure. Ses corps de texte sont
    /// fixes : elle ne suit pas la taille du texte du système.
    static var typicalStripHeight: CGFloat { 82 }
}

/// Les proportions du menu, prises sur l'écran de la télé (les unités de
/// conteneur du prototype) : 80 % de la largeur utile, jamais moins de 200 pt
/// ni plus de 300, une hauteur et un corps pris sur la hauteur utile.
nonisolated struct SalonMenuMetrics: Equatable {
    let paddingV: CGFloat
    let paddingH: CGFloat
    let width: CGFloat
    let headGap: CGFloat
    let rowGap: CGFloat
    let rowHeight: CGFloat
    let rowPaddingH: CGFloat
    let fontSize: CGFloat
    let chevronSize: CGFloat
    let eyebrowSize: CGFloat

    init(room: SalonGeometry) {
        func clamp(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
            max(low, min(value, high))
        }
        let k = room.screenWidth / 234
        paddingV = clamp(11 * k, 12, 20)
        paddingH = clamp(13 * k, 14, 24)
        let innerW = max(0, room.screenWidth - 2 * paddingH)
        let innerH = max(0, room.screenHeight - 2 * paddingV)
        width = min(innerW, max(200, innerW * 0.8), 300)
        headGap = clamp(room.height * 0.09, 10, 18)
        rowGap = clamp(innerH * 0.05, 6, 10)
        rowHeight = clamp(innerH * 0.25, 34, 46)
        rowPaddingH = clamp(innerW * 0.05, 12, 16)
        fontSize = clamp(innerH * 0.10, 13, 16)
        chevronSize = clamp(innerH * 0.09, 13, 16)
        eyebrowSize = clamp(7.5 * k, 8, 11)
    }
}

// MARK: - Le décor

/// Le salon peint : mur, plinthe, lueur de la télé, meuble bas à trois portes,
/// télé 16:9 sur son pied avec son voyant, canapé vu de dos.
private struct SalonBackdrop: View {
    let room: SalonGeometry

    var body: some View {
        Canvas(opaque: true) { context, _ in
            SalonPainter(context: context, room: room).paint()
        }
    }
}

/// `drawSalon()` du prototype, trait pour trait. On peint du plus loin au plus
/// proche : l'ordre fait les occlusions.
///
/// Partagé avec la porte de CinéMatch, qui peint ce même salon en réduction
/// derrière ses battants : l'ouverture découvre l'accueil, pas un décor.
struct SalonPainter {
    let context: GraphicsContext
    let room: SalonGeometry
    /// Ce que le mur et le sol débordent de la pièce, de chaque côté. Nul à
    /// l'accueil ; dans la porte, l'embrasure peut être plus large que le
    /// salon réduit, et le décor la remplit sans raccord.
    var bleed: CGFloat = 0

    private func px(_ v: CGFloat) -> CGFloat { max(1, (v * room.scale).rounded()) }

    private func vertical(_ y0: CGFloat, _ y1: CGFloat, _ hexes: [UInt]) -> GraphicsContext.Shading {
        .linearGradient(
            Gradient(colors: hexes.map { Color(hex: $0) }),
            startPoint: CGPoint(x: 0, y: y0),
            endPoint: CGPoint(x: 0, y: y1)
        )
    }

    private func tint(_ hex: UInt, _ alpha: Double) -> Color { Color(hex: hex).opacity(alpha) }

    private func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat, _ shading: GraphicsContext.Shading) {
        let rect = CGRect(x: x, y: y, width: w, height: h)
        let radius = min(r, min(abs(w), abs(h)) / 2)
        context.fill(Path(roundedRect: rect, cornerRadius: radius, style: .circular), with: shading)
    }

    private func ellipse(_ x: CGFloat, _ y: CGFloat, _ rx: CGFloat, _ ry: CGFloat, _ color: Color) {
        context.fill(Path(ellipseIn: CGRect(x: x - rx, y: y - ry, width: 2 * rx, height: 2 * ry)), with: .color(color))
    }

    /// Une lueur : un dégradé radial dans un cercle unité étiré en ellipse.
    private func glow(_ x: CGFloat, _ y: CGFloat, _ rx: CGFloat, _ ry: CGFloat, _ hex: UInt, _ alpha: Double) {
        guard rx > 0, ry > 0 else { return }
        var local = context
        local.translateBy(x: x, y: y)
        local.scaleBy(x: rx, y: ry)
        local.fill(
            Path(ellipseIn: CGRect(x: -1, y: -1, width: 2, height: 2)),
            with: .radialGradient(
                Gradient(colors: [tint(hex, alpha), tint(hex, 0)]),
                center: .zero, startRadius: 0, endRadius: 1
            )
        )
    }

    private func line(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat, _ color: Color, width: CGFloat = 1) {
        segment(CGPoint(x: x0, y: y0), CGPoint(x: x1, y: y1), color, width: width)
    }

    private func segment(_ a: CGPoint, _ b: CGPoint, _ color: Color, width: CGFloat = 1) {
        var path = Path()
        path.move(to: a)
        path.addLine(to: b)
        context.stroke(path, with: .color(color), lineWidth: width)
    }

    /// Un polygone aux coins arrondis un par un (`arcTo` du canvas). Ouvert, il
    /// ne trace que l'arête, du premier au dernier point.
    private func roundedPolygon(_ points: [CGPoint], _ radii: [CGFloat], open: Bool = false) -> Path {
        var path = Path()
        let n = points.count
        guard n > 2, radii.count == n else { return path }
        if open {
            path.move(to: points[0])
            for i in 1 ..< (n - 1) {
                path.addArc(tangent1End: points[i], tangent2End: points[i + 1], radius: radii[i])
            }
            path.addLine(to: points[n - 1])
            return path
        }
        path.move(to: CGPoint(x: (points[n - 1].x + points[0].x) / 2, y: (points[n - 1].y + points[0].y) / 2))
        for i in 0 ..< n {
            path.addArc(tangent1End: points[i], tangent2End: points[(i + 1) % n], radius: radii[i])
        }
        path.closeSubpath()
        return path
    }

    private func topRounded(_ rect: CGRect, top: CGFloat, bottom: CGFloat) -> Path {
        UnevenRoundedRectangle(
            topLeadingRadius: top,
            bottomLeadingRadius: bottom,
            bottomTrailingRadius: bottom,
            topTrailingRadius: top,
            style: .circular
        )
        .path(in: rect)
    }

    func paint() {
        let cw = room.width
        let ch = room.height
        let s = room.scale
        let tl = room.tvLeft, tt = room.top, tw = room.tvWidth, th = room.tvHeight
        let tr = tl + tw, tb = tt + th
        let sx = room.screenLeft, sy0 = room.screenTop
        let iw = room.screenWidth, ih = room.screenHeight

        // La pièce : le mur, la plinthe, le sol.
        let neckH = px(7)
        let baseH = max(2, px(3))
        let conTop = tb + neckH + baseH
        let conH = px(22)
        let legH = px(5)
        let floorY = conTop + conH + legH
        let wide = cw + 2 * bleed
        context.fill(Path(CGRect(x: -bleed, y: -bleed, width: wide, height: floorY + bleed)), with: vertical(0, floorY, [0x1C1A15, 0x24211A]))
        context.fill(Path(CGRect(x: -bleed, y: floorY, width: wide, height: max(0, ch - floorY) + bleed)), with: vertical(floorY, ch, [0x16140F, 0x0C0B08]))
        let plH = px(7)
        context.fill(Path(CGRect(x: -bleed, y: floorY - plH, width: wide, height: plH)), with: .color(Color(hex: 0x1A1813)))
        line(-bleed, floorY - plH + 0.5, cw + bleed, floorY - plH + 0.5, tint(0xDCD8CD, 0.10))
        // La lumière de l'écran, sur le mur et sur le sol.
        glow(cw / 2, tt + th / 2, tw * 0.95, th * 1.05, 0x8FB4D8, 0.16)
        glow(cw / 2, floorY + px(10), tw * 0.9, px(40), 0x8FB4D8, 0.06)

        // Le meuble bas : trois portes, trois poignées, des pieds.
        let conW = min(cw - 32, tw * 1.28).rounded()
        let cx0 = ((cw - conW) / 2).rounded()
        ellipse(cw / 2, floorY + 1, conW * 0.52, px(5), tint(0x000000, 0.35))
        for lx in [cx0 + px(8), cx0 + conW - px(8) - px(3)] {
            box(lx, conTop + conH - 1, px(3), legH + 1, 1, .color(Color(hex: 0x12110D)))
        }
        box(cx0, conTop, conW, conH, px(2), vertical(conTop, conTop + conH, [0x2E2A20, 0x25211A]))
        line(cx0 + 2, conTop + 0.5, cx0 + conW - 2, conTop + 0.5, tint(0xDCD8CD, 0.18))
        for i in 1 ..< 3 {
            let x = (cx0 + conW * CGFloat(i) / 3).rounded() + 0.5
            line(x, conTop + px(4), x, conTop + conH - px(3), tint(0x000000, 0.45))
            line(x + 1, conTop + px(4), x + 1, conTop + conH - px(3), tint(0xDCD8CD, 0.05))
        }
        for i in 0 ..< 3 {
            let hx = cx0 + conW * (CGFloat(i) + 0.5) / 3
            box(hx - px(7), conTop + px(7), px(14), max(1.5, 1.5 * s), 1, .color(tint(0xDCD8CD, 0.30)))
        }

        // La télévision : pied central, cadre fin, menton, voyant.
        let footHalf = (tw * 0.14).rounded()
        box(cw / 2 - footHalf, tb + neckH, (tw * 0.28).rounded(), baseH, baseH / 2, .color(Color(hex: 0x131210)))
        line(cw / 2 - footHalf + 2, tb + neckH + 0.5, cw / 2 + footHalf - 2, tb + neckH + 0.5, tint(0xDCD8CD, 0.12))
        box(cw / 2 - (tw * 0.025).rounded(), tb - 2, (tw * 0.05).rounded(), neckH + 3, 1, .color(Color(hex: 0x0E0D0B)))
        box(tl, tt, tw, th, px(6), .color(Color(hex: 0x0B0A08)))
        context.stroke(
            Path(roundedRect: CGRect(x: tl + 0.5, y: tt + 0.5, width: tw - 1, height: th - 1), cornerRadius: px(6), style: .circular),
            with: .color(tint(0xDCD8CD, 0.14)),
            lineWidth: 1
        )
        box(sx, sy0, iw, ih, 2, vertical(sy0, sy0 + ih, [0x141B24, 0x0C1117]))
        glow(sx + iw / 2, sy0 + ih * 0.45, iw * 0.62, ih * 0.72, 0xBFD9F0, 0.14)
        line(sx, sy0 + 0.5, sx + iw, sy0 + 0.5, tint(0xDCD8CD, 0.06))
        let led = max(2, (2 * s).rounded())
        box(tr - room.bezel - px(12), tb - (room.chin / 2).rounded() - led / 2, led, led, led / 2, .color(tint(0xF3F0E8, 0.55)))

        paintCouch()
    }

    /// Le menu de la télé à l'arrêt, peint et non posé en vues : l'image que la
    /// porte découvre en s'ouvrant. Mêmes mesures que `tvScreen`, première ligne
    /// en surbrillance comme à l'arrivée sur l'accueil, pour que le fondu vers
    /// les vraies lignes ne déplace rien.
    func paintMenuStill() {
        let menu = room.menu
        let ink = CineMatchHomeView.screenInk
        let eyebrowLine = (menu.eyebrowSize * 1.2).rounded()
        let block = eyebrowLine + menu.headGap + 2 * menu.rowHeight + menu.rowGap
        let midX = room.screenLeft + room.screenWidth / 2
        var y = room.screenTop + (room.screenHeight - block) / 2

        let eyebrow = String(localized: "Ta soirée Cinechill", bundle: .app).uppercased()
        context.draw(
            Text(verbatim: eyebrow)
                .font(.system(size: menu.eyebrowSize, weight: .semibold))
                .tracking(menu.eyebrowSize * 0.16)
                .foregroundStyle(CinechillPalette.wallHigh.opacity(0.55)),
            at: CGPoint(x: midX, y: y + eyebrowLine / 2),
            anchor: .center
        )
        y += eyebrowLine + menu.headGap

        for (index, entry) in CineMatchHomeView.Entry.allCases.enumerated() {
            let isOn = index == 0
            let row = CGRect(x: midX - menu.width / 2, y: y, width: menu.width, height: menu.rowHeight)
            context.fill(
                Path(roundedRect: row, cornerRadius: Metrics.radius, style: .continuous),
                with: .color(isOn ? Ink.paper : ink.opacity(0.05))
            )
            if !isOn {
                context.stroke(
                    Path(roundedRect: row.insetBy(dx: 0.5, dy: 0.5), cornerRadius: Metrics.radius, style: .continuous),
                    with: .color(ink.opacity(0.18)),
                    lineWidth: 1
                )
            }
            context.draw(
                Text(verbatim: entry.title)
                    .font(.system(size: menu.fontSize, weight: isOn ? .semibold : .medium))
                    .foregroundStyle(isOn ? Ink.ground : ink.opacity(0.8)),
                at: CGPoint(x: row.minX + menu.rowPaddingH, y: row.midY),
                anchor: .leading
            )
            if isOn {
                let side = menu.chevronSize
                let box = CGRect(x: row.maxX - menu.rowPaddingH - side, y: row.midY - side / 2, width: side, height: side)
                context.stroke(
                    EntryChevron().path(in: box),
                    with: .color(Ink.ground),
                    style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)
                )
            }
            y += menu.rowHeight + menu.rowGap
        }
    }

    /// Le canapé, vu de dos, en vraie perspective.
    ///
    /// Un canapé trois places moderne, décrit en mètres et projeté depuis un
    /// œil placé derrière lui : x = cx + F·X/Z, y = hy + F·(E − h)/Z. L'œil est
    /// à 1,20 m, à 4 m du dos : de loin, les coussins ne rétrécissent presque
    /// pas avec la profondeur, la perspective reste un indice et non un effet.
    /// F fixe la largeur ; le point le plus haut se cale sur la place donnée
    /// par la géométrie.
    private func paintCouch() {
        let W: CGFloat = 2.2, a: CGFloat = 0.2, D: CGFloat = 0.95
        let hA: CGFloat = 0.60, hB: CGFloat = 0.72, tB: CGFloat = 0.16
        let hC: CGFloat = 0.90, dC: CGFloat = 0.24, leg: CGFloat = 0.08
        let zr: CGFloat = 4.0, eye: CGFloat = 1.2
        let zf = zr + D
        let cx = room.width / 2
        let f = room.couchWidth * zr / W
        let topU = min((eye - hA) / zf, (eye - hC) / (zr + tB + 0.012))
        let hy = room.couchTop - f * topU
        func p3(_ x: CGFloat, _ h: CGFloat, _ z: CGFloat) -> CGPoint {
            CGPoint(x: cx + f * x / z, y: hy + f * (eye - h) / z)
        }
        let hw = W / 2, xi = hw - a, zc0 = zr + tB, zc1 = zc0 + dC

        // L'ombre au sol : trois ellipses superposées sous le dos, pour un bord doux.
        let shadowY = p3(0, 0, zr).y
        let shadowW = f * hw / zr
        let shadows: [(CGFloat, CGFloat, Double)] = [(1.10, px(14), 0.10), (1.02, px(9), 0.16), (0.94, px(5), 0.24)]
        for (k, ry, alpha) in shadows {
            ellipse(cx, shadowY, shadowW * k, ry, tint(0x000000, alpha))
        }

        // Les trois coussins de dossier, qui dépassent franchement du dos : le
        // haut, tourné vers la télé, prend la lumière ; le bas retombe dans
        // l'ombre du dos.
        for i in 0 ..< 3 {
            let x0 = -xi + CGFloat(i) * (2 * xi / 3) + 0.018
            let x1 = x0 + 2 * xi / 3 - 0.036
            let zc = zc0 + 0.012
            let pa = p3(x0, hC - 0.05, zc1)
            let pb = p3(x1, 0.5, zc)
            let w = pb.x - pa.x, h = pb.y - pa.y
            guard w > 1, h > 1 else { continue }
            let rt = min(h * 0.5, w * 0.22)
            let lit = p3(0, hC, zc).y
            context.fill(
                topRounded(CGRect(x: pa.x, y: pa.y, width: w, height: h), top: rt, bottom: px(2)),
                with: vertical(pa.y, pa.y + h, [0x554E41, 0x433C31, 0x2C2720])
            )
            context.stroke(
                topRounded(CGRect(x: pa.x + 0.5, y: pa.y + 0.5, width: w - 1, height: min(h, rt * 2)), top: rt, bottom: 0),
                with: .color(tint(0xBFD9F0, 0.16)),
                lineWidth: 1
            )
            // Le pli qui marque le rembourrage.
            segment(
                CGPoint(x: pa.x + w * 0.18, y: lit + h * 0.42),
                CGPoint(x: pa.x + w * 0.82, y: lit + h * 0.42),
                tint(0x000000, 0.14)
            )
        }

        // Le dessus des accoudoirs, courts : on garde la profondeur en hauteur
        // (85 cm) mais seulement 12 % du glissement latéral, pour qu'il reste
        // posé sur l'accoudoir au lieu de filer derrière le dossier.
        for sg: CGFloat in [-1, 1] {
            let zA = zr + 0.85
            let lateral: CGFloat = 0.12
            let ro = p3(sg * hw, hA, zr), ri = p3(sg * xi, hA, zr), fo = p3(sg * hw, hA, zA)
            let dy = fo.y - ro.y
            let dx = (fo.x - ro.x) * lateral
            // Arrière intérieur, arrière extérieur, avant extérieur, avant intérieur.
            let t = [ri, ro, CGPoint(x: ro.x + dx, y: ro.y + dy), CGPoint(x: ri.x + dx, y: ri.y + dy)]
            let rad = [px(1), px(8), px(7), px(1)]
            let points = sg < 0 ? [t[1], t[0], t[3], t[2]] : t
            let radii = sg < 0 ? [rad[1], rad[0], rad[3], rad[2]] : rad
            context.fill(roundedPolygon(points, radii), with: vertical(ro.y, ro.y + dy, [0x3A342A, 0x4D473A]))
            segment(
                CGPoint(x: t[3].x, y: t[3].y + 0.5),
                CGPoint(x: t[2].x - sg * px(7), y: t[2].y + 0.5),
                tint(0xBFD9F0, 0.18)
            )
        }

        // Le dos : une seule silhouette, le dossier plus haut que les accoudoirs.
        let corners: [(CGFloat, CGFloat)] = [
            (-hw, leg), (-hw, hA), (-xi, hA), (-xi, hB), (xi, hB), (xi, hA), (hw, hA), (hw, leg),
        ]
        let back = corners.map { p3($0.0, $0.1, zr) }
        let armH = back[0].y - back[1].y
        let rOut = min(px(8), armH * 0.3), rIn = px(4), rBack = px(9)
        let backRadii = [px(2), rOut, rIn, rBack, rBack, rIn, rOut, px(2)]
        context.fill(roundedPolygon(back, backRadii), with: vertical(back[3].y, back[0].y, [0x2D281F, 0x1D1A15]))
        // La lumière de la télé accroche l'arête haute du dos.
        context.stroke(
            roundedPolygon(back, backRadii, open: true).offsetBy(dx: 0, dy: 0.5),
            with: .color(tint(0xBFD9F0, 0.18)),
            lineWidth: 1
        )

        for sg: CGFloat in [-1, 1] {
            // Le passepoil, à trois centimètres sous l'arête.
            let pa = p3(sg * (hw - 0.08), hA - 0.03, zr), pb = p3(sg * (xi + 0.03), hA - 0.03, zr)
            segment(pa, pb, tint(0x000000, 0.30))
            segment(CGPoint(x: pa.x, y: pa.y + 1), CGPoint(x: pb.x, y: pb.y + 1), tint(0xDCD8CD, 0.05))
            // La couture entre le dossier et l'accoudoir.
            segment(p3(sg * xi, leg + 0.04, zr), p3(sg * xi, hA - 0.01, zr), tint(0x000000, 0.38))
            segment(p3(sg * (xi + 0.006), leg + 0.04, zr), p3(sg * (xi + 0.006), hA - 0.01, zr), tint(0xDCD8CD, 0.045))
        }
        do {
            let pa = p3(-xi + 0.05, hB - 0.03, zr), pb = p3(xi - 0.05, hB - 0.03, zr)
            segment(pa, pb, tint(0x000000, 0.30))
            segment(CGPoint(x: pa.x, y: pa.y + 1), CGPoint(x: pb.x, y: pb.y + 1), tint(0xDCD8CD, 0.05))
        }

        // Le socle, un cran plus sombre, et les pieds arrière.
        let base = [p3(-hw, leg, zr), p3(hw, leg, zr), p3(hw, leg + 0.04, zr), p3(-hw, leg + 0.04, zr)]
        var basePath = Path()
        basePath.addLines(base)
        basePath.closeSubpath()
        context.fill(basePath, with: .color(tint(0x000000, 0.24)))
        for x in [-hw + 0.07, hw - 0.07] {
            let pa = p3(x - 0.022, leg, zr + 0.03), pb = p3(x + 0.022, 0, zr + 0.03)
            box(pa.x, pa.y, pb.x - pa.x, pb.y - pa.y, 1, .color(Color(hex: 0x0E0D0A)))
        }
    }
}
