//
//  CineMatchRoomView.swift
//  Cinechill_iOS
//

import SwiftUI
import UIKit
import WebKit

/// Ce que joue la salle des propositions.
///
/// `entrance` : on s'approche de l'écran au fond de la salle, il s'allume
/// d'un éclat, et sa lumière court sur les fauteuils, rang après rang.
/// `swap` : l'écran s'éteint, le film change, l'écran se rallume et la
/// lumière refait le tour, plus vite. `still` : tout est en place (mouvement
/// réduit, ou séquence passée d'un toucher).
///
/// Une séquence est un instant de départ et des courbes : la salle se
/// redessine image par image depuis l'heure, sans état à tenir à jour.
nonisolated struct CineMatchRoomSequence: Equatable {
    enum Kind: Equatable { case entrance, swap, still }

    var kind: Kind
    var start: Date

    static let still = CineMatchRoomSequence(kind: .still, start: .distantPast)

    /// La durée au-delà de laquelle plus rien ne bouge.
    var duration: TimeInterval {
        switch kind {
        case .entrance: 2.0
        case .swap: 0.95
        case .still: 0
        }
    }

    /// Le moment, dans un changement de film, où l'écran est noir : c'est
    /// là que l'affiche change.
    static let swapDarkAt: TimeInterval = 0.18

    /// L'état de la salle à l'instant `date`.
    func state(at date: Date) -> CineMatchRoomState {
        let t = max(0, date.timeIntervalSince(start))
        switch kind {
        case .still:
            return .settled
        case .entrance:
            let approach = Self.easeInOut(min(1, t / 1.1))
            return CineMatchRoomState(
                approach: approach,
                screen: Self.screenCurve(t, offAt: 0.95, flashAt: 1.1, settleAt: 1.45, off: 0.25, flash: 1.5),
                front: t < 1.0 ? -1 : (t - 1.0) / 0.8
            )
        case .swap:
            let screen: Double = if t < Self.swapDarkAt {
                1 - 0.85 * (t / Self.swapDarkAt)
            } else {
                Self.screenCurve(t, offAt: 0.24, flashAt: 0.42, settleAt: 0.65, off: 0.15, flash: 1.4)
            }
            return CineMatchRoomState(approach: 1, screen: screen, front: t < 0.24 ? -1 : (t - 0.24) / 0.55)
        }
    }

    /// Éteint jusqu'à `offAt`, l'éclat à `flashAt`, la lumière normale à
    /// `settleAt`.
    private static func screenCurve(
        _ t: TimeInterval, offAt: Double, flashAt: Double, settleAt: Double, off: Double, flash: Double
    ) -> Double {
        if t < offAt { return off }
        if t < flashAt { return off + (flash - off) * ((t - offAt) / (flashAt - offAt)) }
        if t < settleAt { return flash + (1 - flash) * ((t - flashAt) / (settleAt - flashAt)) }
        return 1
    }

    private static func easeInOut(_ k: Double) -> Double {
        k < 0.5 ? 4 * k * k * k : 1 - pow(-2 * k + 2, 3) / 2
    }
}

/// La salle à un instant donné.
nonisolated struct CineMatchRoomState: Equatable {
    /// De 0 (l'écran au fond, petit) à 1 (en place).
    var approach: Double
    /// La lumière de l'écran : 1 normale, en dessous éteint, au-dessus
    /// l'éclat de l'allumage.
    var screen: Double
    /// Le front de lumière sur les fauteuils, de 0 (il part de l'écran) à 1
    /// (il a passé le dernier rang). Négatif : pas encore parti.
    var front: Double

    static let settled = CineMatchRoomState(approach: 1, screen: 1, front: 2)
}

/// La salle, en unités du monde : l'écran, large de 1,6, au fond en z = 0 ;
/// la caméra arrive en z = 10, partie de z = 24.
private enum RoomMetrics {
    static let screenWorldWidth = 1.6
    static let cameraEnd = 10.0
    static let cameraStart = 24.0
    /// Rayon (distance à l'écran) et demi-ouverture (radians) de chaque rang,
    /// du premier au huitième, comme les rangées du logo.
    static var rows: [(radius: Double, half: Double)] {
        [
            (1.0, 38.0), (1.45, 36.0), (1.9, 34.0), (2.35, 32.0),
            (2.8, 30.0), (3.25, 28.0), (3.7, 26.0), (4.15, 24.0),
        ].map { ($0.0, $0.1 * .pi / 180) }
    }
    /// L'espacement des fauteuils le long d'un rang.
    static let seatSpacing = 0.16
    /// L'épaisseur du front de lumière.
    static let frontWidth = 0.6
    static let posterRatio: CGFloat = 1.5
}

/// La salle : l'affiche est l'écran, au fond ; devant elle, les rangées du
/// logo, vues de l'intérieur, un tiret par fauteuil.
///
/// **Une vraie perspective** (13 octobre 2026 : la première version, aux
/// rangs également espacés et aplatis, faisait une salle « écrasée »). La
/// salle est calculée comme une caméra posée dedans : l'écran, large de 1,6,
/// au fond en z = 0 ; huit rangées en arc autour de lui, du premier rang
/// (rayon 1) au dernier (rayon 4,15), comme dans le logo ; la caméra en
/// z = 10. Les rangs proches sont donc plus bas, plus espacés, plus larges,
/// et débordent de l'écran du téléphone, comme quand on est assis dans la
/// salle ; ceux du fond se resserrent sous l'écran. L'entrée est un vrai
/// travelling : la caméra part de z = 24.
///
/// **L'écran joue** : la bande-annonce l'élargit au format cinéma (16:9),
/// la salle baisse. « Je le regarde » l'élargit aussi, le pose au milieu de
/// la salle, et éteint les rangs du fond vers l'écran, l'inverse de l'entrée.
///
/// La lumière qui court sur les fauteuils prend la couleur dominante de
/// l'affiche : bleu nuit pour Heat, jaune pour Breaking Bad.
struct CineMatchRoomView<Screen: View>: View, Animatable {
    let film: CineMatchFilm
    /// Un film marqué (« déjà vu », écarté) : l'écran baisse.
    let isMarked: Bool
    /// « Déjà vu », « Écarté », « Nouveau ».
    let tag: String?
    /// « ▶ Bande-annonce » sur l'écran.
    let showsTrailerCue: Bool
    let sequence: CineMatchRoomSequence
    /// Le déplacement sous le doigt : l'écran suit un peu, la salle non.
    let dragOffset: CGFloat
    /// De 0 (l'affiche) à 1 (l'écran au format cinéma).
    var widen: Double
    /// De 0 (salle allumée) à 1 (film lancé : salle éteinte, écran au milieu).
    var launch: Double
    /// Ce que l'écran montre une fois élargi : la bande-annonce.
    @ViewBuilder let screenContent: () -> Screen

    @State private var tint: RoomTint = .fallback

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(widen, launch) }
        set {
            widen = newValue.first
            launch = newValue.second
        }
    }


    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: isSettled)) { context in
            let state = sequence.state(at: context.date)
            GeometryReader { proxy in
                let layout = Layout(size: proxy.size)
                ZStack(alignment: .topLeading) {
                    if layout.showsRows {
                        seats(state: state, layout: layout)
                    }
                    screen(state: state, layout: layout)
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            }
        }
        .task(id: film.id) { await loadTint() }
    }

    /// Plus rien ne bouge : la frise s'arrête, la batterie aussi. Les
    /// élargissements passent par `animatableData`, que SwiftUI anime seul.
    private var isSettled: Bool {
        sequence.kind == .still || Date().timeIntervalSince(sequence.start) > sequence.duration + 0.1
    }

    // MARK: - La géométrie

    private struct Layout {
        let size: CGSize
        let posterWidth: CGFloat
        let posterHeight: CGFloat
        /// La place des rangs, sous l'écran.
        let room: CGFloat
        let showsRows: Bool

        init(size: CGSize) {
            self.size = size
            let widest = size.width * 0.5 * RoomMetrics.posterRatio
            // La moitié de la hauteur pour l'écran : aux deux tiers, la salle
            // était écrasée sous lui.
            var height = min(size.height * 0.5, widest)
            var room = size.height - height - 6
            // Moins de soixante points de salle (texte agrandi sur un petit
            // écran) : l'écran seul, et toute la hauteur pour lui.
            showsRows = room >= 60
            if !showsRows {
                height = min(size.height, size.width * 0.6 * RoomMetrics.posterRatio)
                room = 0
            }
            posterHeight = max(0, height)
            posterWidth = posterHeight / RoomMetrics.posterRatio
            self.room = room
        }
    }

    private func camera(_ state: CineMatchRoomState) -> Double {
        RoomMetrics.cameraStart + (RoomMetrics.cameraEnd - RoomMetrics.cameraStart) * state.approach
    }

    // MARK: - L'écran

    private func screen(state: CineMatchRoomState, layout: Layout) -> some View {
        let size = layout.size
        let wideWidth = size.width - 16
        let wideHeight = wideWidth * 9 / 16
        // Lancé, l'écran s'élargit lui aussi.
        let opened = max(widen, min(1, launch * 1.3))
        let width = layout.posterWidth + (wideWidth - layout.posterWidth) * opened
        let height = layout.posterHeight + (wideHeight - layout.posterHeight) * opened
        // Son pied reste au pied de l'écran ; lancé, il se pose au milieu.
        let restingTop = layout.posterHeight - height
        let centeredTop = (size.height - height) / 2 - 10
        let top = restingTop + (centeredTop - restingTop) * min(1, launch * 1.3)
        let scale = RoomMetrics.cameraEnd / camera(state)
        let shape = RoundedRectangle(cornerRadius: 2, style: .continuous)

        return ZStack {
            PosterImageView(url: film.item.posterURL, contentMode: .fill)
                .frame(width: width, height: height)
                .clipShape(shape)
            screenContent()
                .frame(width: width, height: height)
                .clipShape(shape)
                .opacity(widen > 0.85 ? 1 : 0)
        }
        .overlay(shape.strokeBorder(Ink.rule, lineWidth: 1))
        // Éteint : un voile noir ; l'éclat : un surcroît de lumière.
        .overlay(Color.black.opacity(max(0, 1 - state.screen) * 0.9).clipShape(shape).allowsHitTesting(false))
        .brightness(max(0, state.screen - 1) * 0.35)
        .opacity(isMarked ? 0.3 : 1)
        .overlay(alignment: .topLeading) { tagView }
        .overlay(alignment: .bottom) { cue }
        .scaleEffect(scale, anchor: .bottom)
        .offset(x: (size.width - width) / 2 + dragOffset * 0.35, y: top)
    }

    @ViewBuilder
    private var tagView: some View {
        if let tag {
            Text(tag)
                .planLabel()
                .foregroundStyle(Ink.ink)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Ink.ground3, in: RoundedRectangle(cornerRadius: 2, style: .continuous))
                .padding(10)
                .transition(.opacity)
                .accessibilityHidden(true)
        }
    }

    /// « ▶ Bande-annonce », sur l'écran : c'est là qu'elle passera.
    @ViewBuilder
    private var cue: some View {
        if showsTrailerCue {
            HStack(spacing: 7) {
                Image(systemName: "play.fill")
                    .planFont(10, weight: .semibold)
                Text("Bande-annonce", bundle: .app)
                    .planFont(12, weight: .semibold)
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .padding(.leading, 9)
            .padding(.trailing, 11)
            .padding(.vertical, 7)
            .background(Color.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
            .padding(.bottom, 10)
            .transition(.opacity)
            .accessibilityHidden(true)
        }
    }

    // MARK: - Les fauteuils

    private func seats(state: CineMatchRoomState, layout: Layout) -> some View {
        let tint = tint
        let zc = camera(state)
        let launch = launch
        let house = 1 - 0.5 * widen
        let lastRadius = RoomMetrics.rows.last?.radius ?? 4.15
        let reach = lastRadius + RoomMetrics.frontWidth * 2
        return Canvas { context, size in
            let centerX = size.width / 2
            let base = layout.posterHeight
            // Fx fait coïncider l'écran dessiné et l'écran du monde ; Fy
            // descend le dernier rang au bas de la salle.
            let fx = layout.posterWidth * RoomMetrics.cameraEnd / RoomMetrics.screenWorldWidth
            let fy = (layout.room - 10) / (1 / (RoomMetrics.cameraEnd - lastRadius) - 1 / RoomMetrics.cameraEnd)
            let front = state.front < 0 ? -1 : state.front * reach
            for (index, row) in RoomMetrics.rows.enumerated() {
                var lit = 0.0
                var flash = 0.0
                if front >= 0 {
                    let p = (front - row.radius) / RoomMetrics.frontWidth
                    lit = p <= 0 ? 0 : p < 1 ? p : max(0.5, 1 - (p - 1) * 0.3)
                    flash = max(0, 1 - abs(p - 0.6) * 1.8)
                }
                // Lancé, les rangs s'éteignent du fond (près de la caméra)
                // vers l'écran, en gardant un reflet de lui.
                let fromBack = Double(RoomMetrics.rows.count - 1 - index) / Double(RoomMetrics.rows.count - 1)
                let off = min(1, max(0, launch * 1.6 - fromBack * 0.6))
                let dim = house * (1 - 0.8 * off)
                let color = tint.seat(lit: lit, flash: flash, approach: state.approach).opacity(dim)
                let count = max(4, Int((row.radius * 2 * row.half / RoomMetrics.seatSpacing).rounded()))
                let halfSeat = 0.035 / row.radius
                for k in 0 ..< count {
                    let angle = -row.half + 2 * row.half * (Double(k) + 0.5) / Double(count)
                    guard let a = project(angle - halfSeat, row.radius, zc, fx, fy, centerX, base),
                          let b = project(angle + halfSeat, row.radius, zc, fx, fy, centerX, base)
                    else { continue }
                    var path = Path()
                    path.move(to: a.point)
                    path.addLine(to: b.point)
                    let width = min(4.5, max(1.6, 0.012 * fx / a.depth)) + flash * 1.2
                    context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
                }
            }
        }
        .accessibilityHidden(true)
    }

    /// Un point d'un rang, vu par la caméra. `nil` derrière elle.
    private func project(
        _ angle: Double, _ radius: Double, _ zc: Double, _ fx: Double, _ fy: Double,
        _ centerX: CGFloat, _ base: CGFloat
    ) -> (point: CGPoint, depth: Double)? {
        let x = radius * sin(angle)
        let z = radius * cos(angle)
        let depth = zc - z
        guard depth > 0.3 else { return nil }
        return (CGPoint(x: centerX + x * fx / depth, y: base + fy * (1 / depth - 1 / zc)), depth)
    }

    // MARK: - La couleur du film

    private func loadTint() async {
        guard let url = film.item.posterURL else {
            tint = .fallback
            return
        }
        let image: UIImage? = if let cached = PosterImageCache.shared.cached(url) {
            cached
        } else {
            await PosterImageCache.shared.image(for: url)
        }
        guard !Task.isCancelled, let image else { return }
        tint = RoomTint(dominantOf: image)
    }
}

/// La couleur de la lumière d'un film : la moyenne de ses pixels colorés
/// (ni noirs, ni gris), saturée et éclaircie, puisque c'est de la lumière
/// et non un pigment.
nonisolated struct RoomTint: Equatable {
    var red: Double
    var green: Double
    var blue: Double

    /// Le bleu de la lumière de l'app, quand l'affiche manque.
    static let fallback = RoomTint(red: 127 / 255, green: 227 / 255, blue: 1)

    /// Le gris des fauteuils dans l'ombre (Ink.ink3).
    private static let dim = (red: 138.0 / 255, green: 134.0 / 255, blue: 120.0 / 255)

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    init(dominantOf image: UIImage) {
        let width = 24, height = 36
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress,
                  let context = CGContext(
                    data: base, width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ),
                  let cgImage = image.cgImage
            else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else {
            self = .fallback
            return
        }
        var red = 0.0, green = 0.0, blue = 0.0, count = 0.0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let r = Double(pixels[i]), g = Double(pixels[i + 1]), b = Double(pixels[i + 2])
            let high = max(r, g, b), low = min(r, g, b)
            // Ni le noir, ni le gris : la couleur du film.
            guard high >= 50, high - low >= 18 else { continue }
            red += r
            green += g
            blue += b
            count += 1
        }
        guard count > 0 else {
            self = .fallback
            return
        }
        red /= count
        green /= count
        blue /= count
        let high = max(red, green, blue)
        func light(_ value: Double) -> Double { min(1, (60 + value / high * 195) / 255) }
        self.init(red: light(red), green: light(green), blue: light(blue))
    }

    /// La couleur d'un fauteuil : gris dans l'ombre, la couleur du film une
    /// fois éclairé, presque blanc au passage du front.
    func seat(lit: Double, flash: Double, approach: Double) -> Color {
        let lightRed = red + (1 - red) * flash
        let lightGreen = green + (1 - green) * flash
        let lightBlue = blue + (1 - blue) * flash
        let mix = min(1, lit)
        let opacity = min(1, 0.3 * approach + lit * 0.95)
        return Color(
            red: Self.dim.red + (lightRed - Self.dim.red) * mix,
            green: Self.dim.green + (lightGreen - Self.dim.green) * mix,
            blue: Self.dim.blue + (lightBlue - Self.dim.blue) * mix,
            opacity: opacity
        )
    }
}


// MARK: - La bande-annonce

/// La bande-annonce, jouée dans l'écran de la salle : le lecteur YouTube
/// intégré, dans une page qui donne à la vidéo une origine (sans elle,
/// YouTube refuse de jouer une vidéo intégrée).
struct CineMatchTrailerPlayer: UIViewRepresentable {
    let key: String

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false
        view.backgroundColor = .black
        view.scrollView.isScrollEnabled = false
        load(into: view)
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {}

    static func dismantleUIView(_ view: WKWebView, coordinator: ()) {
        // Arrêter le son : la vue disparaît, la vidéo ne doit pas continuer.
        view.loadHTMLString("", baseURL: nil)
    }

    private func load(into view: WKWebView) {
        let safeKey = key.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        let html = """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>html,body{margin:0;height:100%;background:#000}iframe{position:absolute;inset:0;width:100%;height:100%;border:0}</style>
        </head><body><iframe src="https://www.youtube-nocookie.com/embed/\(safeKey)?playsinline=1&autoplay=1&rel=0&modestbranding=1"
        allow="autoplay; encrypted-media; picture-in-picture" allowfullscreen></iframe></body></html>
        """
        view.loadHTMLString(html, baseURL: URL(string: "https://cinechill.app"))
    }
}
