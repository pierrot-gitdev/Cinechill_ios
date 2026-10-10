//
//  OnboardingGesturesPage.swift
//  Cinechill_iOS
//

import SwiftUI

/// Les quatre gestes de Découvrir, joués tout seuls sur une carte : on
/// regarde, on ne fait rien. Une légende de quatre lignes s'allume au même
/// rythme et dit, pour chaque geste, où va le film.
///
/// La carte est la vraie (`SwipeCardView`), avec ses vrais tampons : celle
/// qu'on trouvera en arrivant sur Découvrir, une seconde plus tard.
struct OnboardingGesturesPage: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Gesture: CaseIterable {
        case seen, watchlist, notSeen, love
    }

    @State private var index = 0
    @State private var active: Gesture?
    @State private var drag: CGSize = .zero
    @State private var isArmed = false
    @State private var isLoved = false
    @State private var press: CGFloat = 1
    @State private var cardOpacity: Double = 1
    /// La carte du dessous vient de passer devant : elle part de sa pose de
    /// carte du dessous et s'avance.
    @State private var isPromoting = false

    private var deck: [OnboardingFilm] { OnboardingFilms.gestureDeck }

    var body: some View {
        GeometryReader { proxy in
            // La carte prend ce que le titre et la légende laissent, dans la
            // proportion de Découvrir.
            let cardHeight = max(110, min(270, proxy.size.height - 440))
            let cardSize = CGSize(width: cardHeight / 1.62, height: cardHeight)

            VStack(alignment: .leading, spacing: 0) {
                OnboardingHeading(
                    eyebrow: String(localized: "Découvrir", bundle: .app),
                    title: String(localized: "Swipe pour remplir ta galerie.", bundle: .app),
                    text: String(localized: "On te montre des films un par un. Tu nous dis lesquels tu as vus.", bundle: .app)
                )

                stack(size: cardSize)
                    .frame(maxWidth: .infinity)
                    .frame(height: cardSize.height + 10)
                    .padding(.top, 26)
                    .accessibilityHidden(true)

                legend
                    .padding(.top, 20)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, Metrics.margin)
            .padding(.top, 16)
        }
        .task { await play() }
    }

    // MARK: - La carte

    private func stack(size: CGSize) -> some View {
        let front = deck[index % deck.count]
        let back = deck[(index + 1) % deck.count]

        return ZStack {
            card(back)
                .frame(width: size.width, height: size.height)
                .scaleEffect(0.95)
                .offset(y: 8)
                .opacity(0.5)

            card(front, verdict: verdict)
                .frame(width: size.width, height: size.height)
                .overlay { SwipeLoveBurst(isOn: isLoved, side: size.width * 0.42) }
                .scaleEffect(isPromoting ? 0.95 : press)
                .offset(x: drag.width, y: drag.height + (isPromoting ? 8 : 0))
                .rotationEffect(.degrees(Double(drag.width / 22)), anchor: .bottom)
                .opacity(isPromoting ? 0.5 : cardOpacity)
                .id(front.id)
        }
        .allowsHitTesting(false)
    }

    private func card(_ film: OnboardingFilm, verdict: (SwipeVerdict, Double)? = nil) -> some View {
        SwipeCardView(
            card: film.swipeCard,
            genre: film.genre,
            verdict: verdict?.0,
            verdictIntensity: verdict?.1 ?? 0,
            isArmed: isArmed
        )
    }

    /// Le tampon, tiré du déplacement comme sur Découvrir.
    private var verdict: (SwipeVerdict, Double)? {
        if -drag.height > abs(drag.width), -drag.height > 12 {
            return (.watchlist, min(1, Double(-drag.height / 60)))
        }
        guard abs(drag.width) > 8 else { return nil }
        return (drag.width > 0 ? .seen : .notSeen, min(1, Double(abs(drag.width) / 56)))
    }

    // MARK: - La légende

    private var legend: some View {
        VStack(spacing: 0) {
            row(.seen, glyph: AnyView(SwipeArrowGlyph(direction: .right, side: 14)),
                what: String(localized: "Tu l'as vu", bundle: .app),
                how: String(localized: "Glisse à droite", bundle: .app),
                destination: String(localized: "Galerie", bundle: .app))
            row(.watchlist, glyph: AnyView(SwipeArrowGlyph(direction: .up, side: 14)),
                what: String(localized: "Tu veux le voir", bundle: .app),
                how: String(localized: "Glisse vers le haut", bundle: .app),
                destination: String(localized: "Watchlist", bundle: .app))
            row(.notSeen, glyph: AnyView(SwipeArrowGlyph(direction: .left, side: 14)),
                what: String(localized: "Tu ne l'as pas vu", bundle: .app),
                how: String(localized: "Glisse à gauche", bundle: .app),
                destination: String(localized: "Plus tard", bundle: .app))
            row(.love, glyph: AnyView(SwipeDoubleTapGlyph(side: 14)),
                what: String(localized: "Tu l'as adoré", bundle: .app),
                how: String(localized: "Touche deux fois l'affiche", bundle: .app),
                destination: String(localized: "Coup de cœur", bundle: .app))
        }
        .overlay(alignment: .top) { Rectangle().fill(Ink.rule).frame(height: 1) }
    }

    private func row(_ gesture: Gesture, glyph: AnyView, what: String, how: String, destination: String) -> some View {
        let isOn = active == gesture
        let accent = gesture == .love ? Color(hex: DoorArtifactKey.coeur.hue) : Ink.light

        return HStack(spacing: 0) {
            glyph
                .frame(width: 28, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(what)
                    .planFont(14.5)
                    .foregroundStyle(isOn ? Ink.ink : Ink.ink2)
                Text(how)
                    .planFont(12)
                    .foregroundStyle(Ink.ink3)
            }
            Spacer(minLength: 8)
            Text(destination)
                .planLabel()
                .foregroundStyle(isOn ? accent : Ink.ink3)
        }
        .foregroundStyle(isOn ? Ink.ink : Ink.ink3)
        .frame(minHeight: 46)
        .overlay(alignment: .bottom) { Rectangle().fill(Ink.rule).frame(height: 1) }
        .animation(.easeOut(duration: 0.2), value: isOn)
        .accessibilityElement(children: .combine)
    }

    // MARK: - La démonstration

    private func play() async {
        try? await Task.sleep(for: .milliseconds(600))
        while !Task.isCancelled {
            for gesture in Gesture.allCases {
                guard !Task.isCancelled else { return }
                active = gesture
                await perform(gesture)
                guard !Task.isCancelled else { return }
                await nextCard()
                try? await Task.sleep(for: .milliseconds(650))
            }
        }
    }

    private func perform(_ gesture: Gesture) async {
        if gesture == .love {
            // Deux battements, puis le cœur se pose : le double tap.
            for _ in 0 ..< 2 {
                withAnimation(.easeOut(duration: 0.08)) { press = 0.96 }
                try? await Task.sleep(for: .milliseconds(90))
                withAnimation(.spring(response: 0.22, dampingFraction: 0.6)) { press = 1 }
                try? await Task.sleep(for: .milliseconds(110))
            }
            withAnimation(SwipeLoveBurst.pop) { isLoved = true }
            try? await Task.sleep(for: .milliseconds(800))
            await flyOut(to: CGSize(width: 420, height: 20))
            return
        }

        let target: CGSize = switch gesture {
        case .seen: CGSize(width: 58, height: 4)
        case .notSeen: CGSize(width: -58, height: 4)
        default: CGSize(width: 0, height: -62)
        }

        if reduceMotion {
            // Le tampon se pose sans que la carte bouge.
            drag = target
            try? await Task.sleep(for: .milliseconds(900))
        } else {
            withAnimation(.timingCurve(0.45, 0, 0.2, 1, duration: 0.62)) { drag = target }
            try? await Task.sleep(for: .milliseconds(620))
            withAnimation(SwipeMotion.lock) { isArmed = true }
            try? await Task.sleep(for: .milliseconds(240))
        }

        let away: CGSize = switch gesture {
        case .seen: CGSize(width: 420, height: 20)
        case .notSeen: CGSize(width: -420, height: 20)
        default: CGSize(width: 0, height: -640)
        }
        await flyOut(to: away)
    }

    /// La carte part du côté du geste, et s'efface en partant.
    private func flyOut(to away: CGSize) async {
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.18)) { cardOpacity = 0 }
            try? await Task.sleep(for: .milliseconds(180))
            return
        }
        withAnimation(.timingCurve(0.2, 0.7, 0.3, 1, duration: 0.28)) {
            drag = away
            cardOpacity = 0
        }
        try? await Task.sleep(for: .milliseconds(280))
    }

    /// La carte du dessous passe devant, et une nouvelle se glisse derrière.
    private func nextCard() async {
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) {
            index += 1
            drag = .zero
            isArmed = false
            isLoved = false
            press = 1
            cardOpacity = 1
            isPromoting = true
        }
        // Une image pour que la nouvelle carte soit posée avant d'avancer.
        try? await Task.sleep(for: .milliseconds(16))
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .timingCurve(0.23, 1, 0.32, 1, duration: 0.3)) {
            isPromoting = false
        }
    }
}
