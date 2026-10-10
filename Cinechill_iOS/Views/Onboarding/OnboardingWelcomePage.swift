//
//  OnboardingWelcomePage.swift
//  Cinechill_iOS
//

import SwiftUI

/// L'accueil : un mur d'affiches qui défile dans le noir, et Cinechill qui en
/// allume une, « ce soir ».
///
/// C'est la promesse de l'app jouée plutôt qu'écrite : parmi tous ces films,
/// on t'en choisit un. Pas de halo ni de dégradé : l'émotion vient du noir de
/// la salle, des affiches qu'on reconnaît, et de celle qui s'allume. Le mur
/// s'arrête net sur un filet ; le texte est posé dessous, sur la nuit.
struct OnboardingWelcomePage: View {
    @State private var isShown = false

    var body: some View {
        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: 0) {
                // Le mur prend ce que le texte laisse, jusqu'à un peu plus de
                // la moitié de l'écran : sur un petit écran ou en grand texte,
                // c'est lui qui cède, jamais la phrase.
                OnboardingPosterWall(columns: OnboardingFilms.wallColumns)
                    .frame(minHeight: 160, maxHeight: proxy.size.height * 0.55)
                    .layoutPriority(1)

                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 10) {
                        CinechillMark()
                            .frame(width: 26, height: 26)
                        Text(verbatim: "Cinechill")
                            .planFont(15, weight: .semibold)
                            .foregroundStyle(Ink.ink)
                    }
                    .onboardingRise(isShown, delay: 0.35)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(verbatim: "Cinechill"))

                    Text(headline)
                        .planTitle(38)
                        .foregroundStyle(Ink.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 16)
                        .onboardingRise(isShown, delay: 0.46)
                        .accessibilityAddTraits(.isHeader)

                    Text("Ne laisse plus ton plat refroidir pendant que tu choisis un film, en 60 sec Cinechill te propose la pépite que tu cherches.", bundle: .app)
                        .planFont(15)
                        .foregroundStyle(Ink.ink2)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 14)
                        .onboardingRise(isShown, delay: 0.57)
                }
                .padding(.horizontal, 28)
                .padding(.top, 26)

                Spacer(minLength: 0)
            }
        }
        // Le mur monte sous la barre d'état : la salle ne s'arrête pas au bord
        // de la zone sûre.
        .ignoresSafeArea(edges: .top)
        .onAppear { isShown = true }
    }

    /// Le titre en deux tons : la seconde moitié prend le papier, l'encre la
    /// plus claire de l'app. C'est elle qui porte la promesse.
    private var headline: AttributedString {
        var text = AttributedString(localized: "Ton film du soir, **en une minute.**", bundle: .app)
        for run in text.runs where run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true {
            text[run.range].inlinePresentationIntent = nil
            text[run.range].swiftUI.foregroundColor = Ink.paper
        }
        return text
    }
}

// MARK: - Le mur

/// Trois colonnes d'affiches qui défilent lentement, à des vitesses et dans
/// des sens différents, et une affiche choisie toutes les trois secondes.
///
/// **La fluidité tient à trois décisions.**
///
/// - Le défilement est une animation linéaire répétée à l'infini, posée une
///   fois sur le décalage de chaque colonne : c'est le serveur de rendu qui
///   l'interpole, image par image, sans repasser par le fil principal. Rien ne
///   recalcule la vue soixante ou cent vingt fois par seconde.
/// - Les affiches sont décodées **avant** d'entrer dans le mur, hors du fil
///   principal et à leur taille d'affichage (`byPreparingThumbnail`). Décodées
///   au premier dessin, elles feraient trébucher le défilement à leur arrivée.
/// - Le mur ne s'allume qu'une fois ses affiches prêtes : la salle s'éclaire
///   d'un coup, au lieu de laisser les affiches tomber une à une.
///
/// La position d'une colonne se déduit du temps écoulé depuis le départ de son
/// animation : c'est ce qui permet de choisir une affiche bien dans le cadre,
/// et qui le restera pendant qu'elle est allumée.
struct OnboardingPosterWall: View {
    let columns: [[OnboardingFilm]]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var images: [Int: UIImage] = [:]
    @State private var isLit = false
    @State private var drift0: CGFloat = 0
    @State private var drift1: CGFloat = 0
    @State private var drift2: CGFloat = 0
    @State private var driftStart: Date?
    @State private var pick: Slot?
    @State private var wallSize: CGSize = .zero

    /// Une affiche du mur : sa colonne, et son rang dans la colonne doublée.
    private struct Slot: Equatable {
        let column: Int
        let index: Int
    }

    /// Points par seconde. Lent : on doit pouvoir lire une affiche.
    private static let speeds: [CGFloat] = [11, 14, 10]
    /// La colonne du milieu descend, les deux autres montent.
    private static let risesUp = [true, false, true]
    /// Le départ décalé des colonnes : les affiches ne s'alignent pas.
    private static let leads: [CGFloat] = [0, -90, -40]
    private static let gap: CGFloat = 8
    /// Le mur déborde de l'écran de chaque côté : des affiches coupées par le
    /// bord disent qu'il y en a d'autres.
    private static let bleed: CGFloat = 14
    /// Combien de temps une affiche reste choisie.
    private static let hold: TimeInterval = 2.6

    var body: some View {
        GeometryReader { proxy in
            let metrics = WallMetrics(width: proxy.size.width)

            HStack(alignment: .top, spacing: Self.gap) {
                ForEach(0 ..< columns.count, id: \.self) { column in
                    columnView(column, metrics: metrics)
                }
            }
            .frame(width: proxy.size.width + Self.bleed * 2, alignment: .topLeading)
            .offset(x: -Self.bleed)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .clipped()
            .onAppear { wallSize = proxy.size }
            .onChange(of: proxy.size) { _, size in wallSize = size }
        }
        .background(CinechillPalette.nightDeep)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Ink.ruleSet).frame(height: 1)
        }
        .opacity(isLit ? 1 : 0)
        .animation(.easeOut(duration: 0.9), value: isLit)
        .task { await run() }
        .accessibilityHidden(true)
    }

    /// Les mesures du mur, tirées de sa largeur seule.
    private struct WallMetrics {
        let posterWidth: CGFloat
        let posterHeight: CGFloat

        init(width: CGFloat) {
            posterWidth = max(1, (width + OnboardingPosterWall.bleed * 2 - OnboardingPosterWall.gap * 2) / 3)
            posterHeight = posterWidth * 1.5
        }

        var pitch: CGFloat { posterHeight + OnboardingPosterWall.gap }
    }

    private func drift(_ column: Int) -> CGFloat {
        switch column {
        case 0: drift0
        case 1: drift1
        default: drift2
        }
    }

    private func columnView(_ column: Int, metrics: WallMetrics) -> some View {
        let films = columns[column]
        let loop = CGFloat(films.count) * metrics.pitch
        let progress = drift(column)
        let y = Self.risesUp[column] ? -loop * progress : -loop + loop * progress

        return VStack(spacing: Self.gap) {
            // Doublée : la colonne défile d'une longueur exacte et boucle sans
            // couture.
            ForEach(Array((films + films).enumerated()), id: \.offset) { index, film in
                poster(film, isPicked: pick == Slot(column: column, index: index), metrics: metrics)
            }
        }
        .frame(width: metrics.posterWidth)
        .offset(y: Self.leads[column] + y)
    }

    private func poster(_ film: OnboardingFilm, isPicked: Bool, metrics: WallMetrics) -> some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
        // Dans le noir, toutes les affiches sont éteintes ; quand une est
        // choisie, les autres s'éteignent un peu plus.
        let dim = pick == nil ? 0.4 : 0.26

        return ZStack(alignment: .bottomLeading) {
            if let image = images[film.id] {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: metrics.posterWidth, height: metrics.posterHeight)
                    .clipped()
            } else {
                Ink.ground3
            }

            if isPicked {
                HStack(spacing: 6) {
                    PlanLight()
                    Text("Ce soir", bundle: .app)
                        .planLabel()
                        .foregroundStyle(Ink.ink)
                }
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(Ink.ground, in: RoundedRectangle(cornerRadius: 2, style: .continuous))
                .padding(10)
                .transition(.opacity.combined(with: .offset(y: 4)))
            }
        }
        .frame(width: metrics.posterWidth, height: metrics.posterHeight)
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(Ink.paper, lineWidth: 1.5).opacity(isPicked ? 1 : 0)
        }
        .opacity(isPicked ? 1 : dim)
    }

    // MARK: - La séance

    private func run() async {
        // La taille du mur arrive avec sa première mise en page : sans elle, ni
        // le décodage ni le défilement ne savent à quelle échelle travailler.
        var waited = 0
        while wallSize.width == 0, waited < 60, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(16))
            waited += 1
        }
        await loadPosters()
        guard !Task.isCancelled else { return }
        isLit = true
        startDrift()

        // La première affiche s'allume quand la salle a fini de s'éclairer.
        try? await Task.sleep(for: .milliseconds(1100))
        while !Task.isCancelled {
            choosePoster()
            try? await Task.sleep(for: .seconds(Self.hold))
        }
    }

    /// Les affiches, décodées à leur taille d'affichage et hors du fil
    /// principal. On n'attend pas plus de deux secondes et demie : une affiche
    /// en retard reste une case sombre plutôt que de retenir toute la salle.
    private func loadPosters() async {
        let films = Array(Set(columns.flatMap { $0 }))
        let side = WallMetrics(width: max(wallSize.width, 320)).posterWidth * 3

        await withTaskGroup(of: (Int, UIImage?).self) { group in
            for film in films {
                group.addTask { await Self.prepared(film, pixelWidth: side) }
            }
            group.addTask {
                try? await Task.sleep(for: .milliseconds(2500))
                return (-1, nil)
            }
            for await (id, image) in group {
                if id == -1 { group.cancelAll(); break }
                if let image { images[id] = image }
                if images.count == films.count { group.cancelAll(); break }
            }
        }
    }

    private nonisolated static func prepared(_ film: OnboardingFilm, pixelWidth: CGFloat) async -> (Int, UIImage?) {
        guard let url = film.posterURL,
              let raw = await PosterImageCache.shared.image(for: url) else { return (film.id, nil) }
        let size = CGSize(width: pixelWidth, height: pixelWidth * 1.5)
        return (film.id, await raw.byPreparingThumbnail(ofSize: size) ?? raw)
    }

    private func startDrift() {
        guard !reduceMotion, wallSize.width > 0 else { return }
        let metrics = WallMetrics(width: wallSize.width)
        driftStart = .now
        for column in 0 ..< columns.count {
            let loop = CGFloat(columns[column].count) * metrics.pitch
            let duration = Double(loop / Self.speeds[column])
            withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
                switch column {
                case 0: drift0 = 1
                case 1: drift1 = 1
                default: drift2 = 1
                }
            }
        }
    }

    /// La position du haut d'une affiche dans le mur, au temps donné.
    private func top(of slot: Slot, at date: Date, metrics: WallMetrics) -> CGFloat {
        let loop = CGFloat(columns[slot.column].count) * metrics.pitch
        var progress: CGFloat = 0
        if let driftStart, !reduceMotion {
            let duration = Double(loop / Self.speeds[slot.column])
            let elapsed = date.timeIntervalSince(driftStart)
            progress = CGFloat(elapsed.truncatingRemainder(dividingBy: duration) / duration)
        }
        let y = Self.risesUp[slot.column] ? -loop * progress : -loop + loop * progress
        return Self.leads[slot.column] + y + CGFloat(slot.index) * metrics.pitch
    }

    /// Une affiche entière dans le cadre, et qui le restera pendant qu'elle
    /// est allumée ; jamais la même deux fois de suite.
    private func choosePoster() {
        guard wallSize.height > 0 else { return }
        let metrics = WallMetrics(width: wallSize.width)
        let now = Date.now
        let later = now.addingTimeInterval(Self.hold)
        // Le haut du mur passe sous la barre d'état : on n'y choisit rien.
        let ceiling: CGFloat = 70
        let floor = wallSize.height - 16

        var candidates: [Slot] = []
        for column in 0 ..< columns.count {
            for index in 0 ..< columns[column].count * 2 {
                let slot = Slot(column: column, index: index)
                guard slot != pick else { continue }
                let fits = [now, later].allSatisfy { date in
                    let top = top(of: slot, at: date, metrics: metrics)
                    return top >= ceiling && top + metrics.posterHeight <= floor
                }
                if fits { candidates.append(slot) }
            }
        }
        guard let next = candidates.randomElement() else { return }
        withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.5)) { pick = next }
    }
}
