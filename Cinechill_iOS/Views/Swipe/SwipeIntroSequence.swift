//
//  SwipeIntroSequence.swift
//  Cinechill_iOS
//

import SwiftUI

/// La démonstration des trois gestes de « Découvrir », jouée une fois, à la
/// première entrée dans l'onglet.
///
/// Elle remplace l'onboarding, et n'en reprend rien : pas d'écran d'accueil, pas
/// de « Suivant », pas de notice. **C'est la vraie carte du dessus** — celle que
/// l'utilisateur va trancher dans quatre secondes — qui part elle-même à droite,
/// à gauche puis vers le haut, avec le tampon exact que le geste produit et, à
/// l'aplomb de chaque bord, la destination où le film se range.
///
/// Trois décisions tiennent la séquence :
/// - **Le repère s'allume, il n'apparaît pas.** Les trois destinations sont
///   posées dès le départ, éteintes ; chaque geste allume la sienne, et elle
///   reste allumée. À la dernière image, les trois sont lues : la séquence se
///   résume elle-même sans qu'on ait à l'écrire.
/// - **Aucune couleur ajoutée.** C'est la valeur — allumé, éteint — qui porte le
///   sens, et le tampon de la carte garde le vocabulaire plein/creux du reste de
///   l'application.
/// - **La sortie est un fondu, pas une transition.** La carte finit exactement où
///   le deck l'attend, dans la même taille, donc le raccord ne se voit pas : la
///   démonstration devient l'écran, et il n'y a rien à valider pour commencer.
///
/// Un contact — n'importe où, tapé ou glissé — l'interrompt sur-le-champ.
struct SwipeIntroSequence: View {
    /// La carte du dessus du deck, reprise telle quelle : la démonstration ne
    /// porte pas sur un film factice.
    let card: SwipeCard
    /// Son genre principal, résolu par le deck — la carte de la démonstration est
    /// la carte du deck, jusque dans sa légende.
    let genre: String?
    /// La taille calculée par le deck, pour que le raccord de sortie tombe juste.
    let cardSize: CGSize
    let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var offset: CGSize = .zero
    @State private var intensity: Double = 0
    @State private var scale: CGFloat = 1
    @State private var opacity: Double = 1
    /// Le geste en cours de démonstration.
    @State private var current: Move?
    /// Ceux déjà montrés : leur repère reste allumé.
    @State private var taught: Set<Move> = []
    /// Les repères ne sont pas là d'emblée : la carte se lit d'abord seule, puis
    /// les destinations se posent autour d'elle.
    @State private var markersIn = false

    var body: some View {
        ZStack {
            // Toute l'aire du deck coupe la séquence, pas seulement la carte :
            // qui a compris avant la fin n'a pas à viser.
            Color.clear.contentShape(Rectangle())

            ZStack {
                demoCard
                markers
            }
            .frame(width: cardSize.width, height: cardSize.height)
        }
        .onTapGesture { onFinished() }
        .gesture(DragGesture(minimumDistance: 12).onChanged { _ in onFinished() })
        .task { await play() }
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(
            String(localized: "Démonstration des gestes. Balayez vers la droite pour ranger le film dans votre galerie, vers la gauche si vous ne l'avez jamais vu, vers le haut pour l'ajouter à votre watchlist.", bundle: .app)
        )
        .accessibilityHint(String(localized: "Touchez pour commencer", bundle: .app))
        .accessibilityAction { onFinished() }
    }

    // MARK: - La carte

    private var demoCard: some View {
        // Le même pivot que sous le doigt, main posée en haut : c'est ce qui fait
        // que le geste démontré et le geste réel ont le même poids.
        let pivot = SwipeMotion.pivot(for: offset, grabbedHigh: true)

        return SwipeCardView(
            card: card,
            genre: genre,
            verdict: current?.verdict,
            verdictIntensity: intensity,
            isArmed: intensity >= 1,
            parallax: SwipeMotion.parallax(for: offset)
        )
        .frame(width: cardSize.width, height: cardSize.height)
        .scaleEffect(scale)
        .offset(offset)
        .rotationEffect(.degrees(pivot.angle), anchor: pivot.anchor)
        .opacity(opacity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - Les destinations

    private var markers: some View {
        ZStack {
            // Toute la bande haute de la carte appartient au tampon du verdict,
            // qui voyage avec elle : le repère de la watchlist descend sous cette
            // bande plutôt que de croiser un tampon en route.
            marker(.up)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, cardSize.height * 0.30)

            marker(.left)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(.leading, 12)

            marker(.right)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .padding(.trailing, 12)
        }
        .opacity(markersIn ? 1 : 0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func marker(_ move: Move) -> some View {
        let isLit = current == move || taught.contains(move)

        return HStack(spacing: 8) {
            if move.arrowLeading { SwipeArrowGlyph(direction: move.direction.arrow) }
            Text(move.destination).planLabel()
            if !move.arrowLeading { SwipeArrowGlyph(direction: move.direction.arrow) }
        }
        // Le refus est le seul repère qui reste en ardoise même allumé : ce qui
        // n'est pas vu ne se range nulle part, et la valeur le dit avant le mot.
        .foregroundStyle(isLit ? move.direction.destinationTint : Ink.ink3)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Ink.ground.opacity(isLit ? 0.88 : 0.6),
            in: RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                .strokeBorder(isLit ? Ink.ruleSet : Ink.rule, lineWidth: 1)
        )
        .opacity(isLit ? 1 : 0.45)
    }

    // MARK: - La séquence

    private func play() async {
        // Un temps d'arrêt d'abord : la carte doit être lue comme une carte avant
        // de bouger, sinon le mouvement passe pour une transition d'écran. Les
        // trois destinations se posent pendant ce temps mort.
        try? await Task.sleep(for: .milliseconds(180))
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.4)) { markersIn = true }
        try? await Task.sleep(for: .milliseconds(480))
        guard !Task.isCancelled else { return }

        // Mouvement réduit : la séquence se réduit à ce qu'elle enseigne — les
        // trois destinations posées autour de la carte, sans un déplacement.
        guard !reduceMotion else {
            withAnimation(.easeOut(duration: 0.35)) { taught = Set(Move.allCases) }
            try? await Task.sleep(for: .milliseconds(2800))
            guard !Task.isCancelled else { return }
            onFinished()
            return
        }

        for move in Move.allCases {
            await demonstrate(move)
            guard !Task.isCancelled else { return }
        }

        try? await Task.sleep(for: .milliseconds(240))
        guard !Task.isCancelled else { return }
        onFinished()
    }

    /// Un temps de la séquence : la glisse jusqu'au seuil, le verdict lu, le
    /// lâcher, et la carte qui remonte de la pile.
    private func demonstrate(_ move: Move) async {
        withAnimation(.easeOut(duration: 0.2)) { current = move }

        withAnimation(.spring(response: 0.46, dampingFraction: 0.74)) {
            offset = move.hold(in: cardSize)
            intensity = 1
        }
        try? await Task.sleep(for: .milliseconds(560))
        guard !Task.isCancelled else { return }

        // Le temps de lire le tampon. Sans cette pause, le verdict passe sous
        // l'œil et le geste n'apprend rien.
        try? await Task.sleep(for: .milliseconds(240))
        guard !Task.isCancelled else { return }

        // Le même retour qu'à la validation d'un vrai swipe, et le seul de la
        // séquence : c'est le geste complet qui est montré, jusqu'à sa sanction.
        // Une vibration au départ de la glisse, elle, n'aurait aucune cause —
        // aucun doigt n'est posé sur l'écran.
        Haptics.impact(.medium)
        // Le même vol que celui d'une vraie carte tranchée, et le même retard à
        // l'extinction : la carte sort par un bord au lieu de fondre en route.
        withAnimation(SwipeMotion.flight) {
            offset = move.exit(in: cardSize)
        }
        withAnimation(.easeIn(duration: 0.14).delay(0.16)) { opacity = 0 }
        // `insert` renvoie un couple, dont une fermeture à expression unique
        // ferait la valeur de retour de `withAnimation` : on l'écarte.
        withAnimation(.easeOut(duration: 0.26)) {
            _ = taught.insert(move)
        }
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }

        // Le film est rangé, la carte revient. La remise au centre se fait hors
        // champ, sans animation : ce qui remonte est la carte suivante, pas la
        // même qui reviendrait sur ses pas.
        current = nil
        offset = .zero
        intensity = 0
        scale = 0.96

        // Une frame de battement, sinon SwiftUI regroupe la remise à zéro et
        // l'animation qui suit dans la même passe : la carte réapparaîtrait déjà
        // à sa taille, sans remonter.
        try? await Task.sleep(for: .milliseconds(16))
        guard !Task.isCancelled else { return }

        withAnimation(.easeOut(duration: 0.26)) {
            opacity = 1
            scale = 1
        }
        try? await Task.sleep(for: .milliseconds(200))
    }
}

// MARK: - Les trois gestes

/// Les trois gestes, dans l'ordre où on les enseigne : le plus fréquent d'abord,
/// et la watchlist en dernier — c'est celui dont on se souvient le mieux, parce
/// qu'il est le seul à sortir par le haut.
///
/// Le geste enseigné n'est pas une notion propre à la démonstration : c'est une
/// `SwipeDirection`, avec son verdict, sa destination et sa flèche. `Move`
/// n'ajoute que la géométrie de la séquence — où la carte s'arrête, et par où
/// elle sort.
private enum Move: CaseIterable {
    case right, left, up

    var direction: SwipeDirection {
        switch self {
        case .right: .right
        case .left: .left
        case .up: .up
        }
    }

    var verdict: SwipeVerdict { direction.verdict }
    var destination: String { direction.destination }

    /// La flèche est toujours du côté du bord vers lequel on balaie : elle sort
    /// du mot, elle ne le précède pas par convention de lecture.
    var arrowLeading: Bool {
        switch self {
        case .right: false
        case .left, .up: true
        }
    }

    /// Le point d'arrêt du geste : assez loin pour que le verdict soit acquis,
    /// assez près pour que la carte reste entièrement à l'écran.
    func hold(in size: CGSize) -> CGSize {
        switch self {
        case .right: CGSize(width: size.width * 0.34, height: 10)
        case .left: CGSize(width: -size.width * 0.34, height: 10)
        case .up: CGSize(width: 0, height: -size.height * 0.26)
        }
    }

    /// La sortie, calée sur celle du deck : la carte quitte franchement le cadre
    /// plutôt que de s'évanouir sur place.
    func exit(in size: CGSize) -> CGSize {
        switch self {
        case .right: CGSize(width: size.width + 360, height: 90)
        case .left: CGSize(width: -(size.width + 360), height: 90)
        case .up: CGSize(width: 0, height: -(size.height + 420))
        }
    }
}

#Preview("La démonstration") {
    ZStack {
        Ink.ground.ignoresSafeArea()
        SwipeIntroSequence(
            card: .preview,
            genre: "Science-fiction",
            cardSize: CGSize(width: 300, height: 486),
            onFinished: {}
        )
    }
}
