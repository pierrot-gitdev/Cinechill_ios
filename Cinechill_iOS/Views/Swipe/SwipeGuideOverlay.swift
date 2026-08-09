//
//  SwipeGuideOverlay.swift
//  Cinechill_iOS
//

import SwiftUI

/// L'aide aux gestes de « Découvrir » : une planche au milieu de l'écran, une
/// carte qui part, et la destination qui s'allume.
///
/// Elle remplace `SwipeIntroSequence`, qui jouait la démonstration **sur la vraie
/// carte du dessus**. C'était sa force — rien à raccorder à la fin — et sa
/// faiblesse : une carte qui part toute seule au moment où l'écran s'ouvre ne se
/// distingue pas d'un classement qu'on aurait déclenché par erreur, et il fallait
/// tout un appareillage pour la suspendre, la reprendre et ne pas la rejouer. Ici
/// c'est une planche, posée sur un voile : ce qui bouge est un schéma, pas le
/// film de quelqu'un.
///
/// Trois décisions la tiennent :
/// - **La carte est un schéma, jamais une affiche réelle.** À 92 pt de large un
///   titre ne se lirait pas, et une vraie affiche laisserait croire que ce
///   film-là vient d'être rangé.
/// - **Le tampon est celui du deck.** Point plein pour l'acquis, creux pour le
///   prévu, aux mêmes mots : c'est ce qui fait que le geste se transpose à la
///   vraie carte sans réapprentissage.
/// - **La séquence tourne en boucle.** On n'arrive pas forcément sur la planche
///   au premier temps, et le geste qu'on cherche est souvent celui qui vient de
///   passer. Chaque tour se termine par un arrêt d'une seconde, les trois lignes
///   allumées : c'est là que la planche se lit d'un coup d'œil, avant que la
///   lumière ne redescende la liste au tour suivant.
struct SwipeGuideOverlay: View {
    let onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var offset: CGSize = .zero
    @State private var intensity: Double = 0
    @State private var scale: CGFloat = 1
    @State private var cardOpacity: Double = 1
    /// Le geste en cours de démonstration.
    @State private var current: Move?
    /// Les gestes déjà montrés : leur ligne reste allumée.
    @State private var revealed: Set<Move> = []
    /// L'entrée de la planche elle-même.
    @State private var isPresented = false

    private static let cardWidth: CGFloat = 88
    /// La scène est plus haute que la carte de ce qu'il faut pour que le geste
    /// vers le haut se voie **sans que le tampon soit rogné** : c'est l'axe
    /// contraint, les deux sorties latérales ont de la place de reste.
    private static let stageHeight: CGFloat = 190

    private var cardHeight: CGFloat { Self.cardWidth * 1.62 }

    var body: some View {
        ZStack {
            Ink.ground.opacity(0.78)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onClose)

            panel
                .scaleEffect(isPresented ? 1 : 0.96)
                .opacity(isPresented ? 1 : 0)
        }
        .task {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) { isPresented = true }
            await play()
        }
    }

    // MARK: - La planche

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Les trois gestes", bundle: .app)
                .planTitle(21)
                .foregroundStyle(Ink.ink)

            stage
                .padding(.top, 16)

            PlanEdge(tint: Ink.rule)
                .padding(.top, 18)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Move.allCases, id: \.self) { move in
                    row(move)
                }
            }

            PlanButton(title: String(localized: "Compris", bundle: .app), height: Metrics.control) {
                onClose()
            }
            .padding(.top, 20)
        }
        .padding(22)
        .frame(maxWidth: 330)
        .background(Ink.ground)
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                .strokeBorder(Ink.ruleSet, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous))
        .padding(.horizontal, Metrics.margin)
        .accessibilityElement(children: .contain)
    }

    /// La scène. Elle est **clippée** : la carte sort du cadre par le bord vers
    /// lequel on balaie, et c'est cette sortie — pas une flèche posée à côté — qui
    /// dit où le geste emmène le film.
    private var stage: some View {
        // Le même pivot que sous le doigt, main posée en haut : le geste montré et
        // le geste réel ont le même poids.
        let pivot = SwipeMotion.pivot(for: offset, grabbedHigh: true)

        return schematicCard
            .overlay { stamp }
            .scaleEffect(scale)
            .offset(offset)
            .rotationEffect(.degrees(pivot.angle), anchor: pivot.anchor)
            .opacity(cardOpacity)
            .frame(maxWidth: .infinity)
            .frame(height: Self.stageHeight)
            .clipped()
            .accessibilityHidden(true)
    }

    /// Le schéma d'une carte du deck : l'affiche, le filet, la plaque de légende
    /// réduite à ses deux lignes. Les mêmes proportions que la vraie — 1/1,62 —
    /// pour que ce soit reconnaissable comme elle.
    private var schematicCard: some View {
        VStack(spacing: 0) {
            ZStack {
                Rectangle().fill(Ink.ground)
                CinechillHallIconView(.salle)
                    .frame(width: 20, height: 20)
                    .foregroundStyle(Ink.ink3.opacity(0.5))
            }

            PlanEdge(tint: Ink.ruleSet)

            VStack(alignment: .leading, spacing: 5) {
                Rectangle().fill(Ink.ink2).frame(width: 46, height: 2)
                Rectangle().fill(Ink.ink3).frame(width: 27, height: 1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 9)
            .padding(.vertical, 11)
        }
        .frame(width: Self.cardWidth, height: cardHeight)
        .background(Ink.ground)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                .strokeBorder(borderTint, lineWidth: 1)
        )
    }

    private var borderTint: Color {
        guard let verdict = current?.direction.verdict, intensity > 0 else { return Ink.ruleSet }
        return verdict.tint.opacity(intensity)
    }

    /// Le tampon du deck, à l'échelle de la vignette. L'interlettrage et le corps
    /// sont réduits — `planLabel` à 10 pt et 1,8 d'approche déborderait d'une
    /// carte de 92 pt — mais le dessin, les mots et le vocabulaire plein/creux
    /// sont ceux qu'on retrouvera sur la vraie carte.
    @ViewBuilder
    private var stamp: some View {
        if let verdict = current?.direction.verdict {
            HStack(spacing: 5) {
                if verdict.isFilled {
                    PlanLight(tint: verdict.tint)
                } else {
                    PlanLightOutline(tint: verdict.tint)
                }
                Text(verdict.label)
                    .font(.system(size: 8, weight: .semibold))
                    .tracking(1.1)
            }
            .foregroundStyle(verdict.tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(
                Ink.ground.opacity(0.9),
                in: RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                    .strokeBorder(verdict.tint.opacity(0.7), lineWidth: 1)
            )
            .padding(7)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: verdict.alignment)
            .opacity(intensity)
        }
    }

    // MARK: - Les trois lignes

    /// Une ligne de la légende. Elle s'allume quand la carte atteint son bord, et
    /// ne s'éteint plus.
    ///
    /// Allumée, la destination passe à l'encre pleine — y compris « Jamais vu »,
    /// dont la teinte d'ardoise dit ailleurs qu'il ne se range nulle part. Dans
    /// une légende, cette nuance ferait lire la ligne comme « pas encore
    /// montrée » : la valeur y sert à distinguer le vu du à venir, pas à qualifier
    /// la destination.
    private func row(_ move: Move) -> some View {
        let isLit = revealed.contains(move) || current == move

        return HStack(spacing: 11) {
            SwipeArrowGlyph(direction: move.direction.arrow, side: 13)
                .foregroundStyle(isLit ? Ink.ink : Ink.ink3)

            Text(move.direction.destination)
                .planLabel()
                .foregroundStyle(isLit ? Ink.ink : Ink.ink3)

            Spacer(minLength: 10)

            Text(move.outcome)
                .font(.system(size: 12))
                .foregroundStyle(isLit ? Ink.ink2 : Ink.ink3)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(height: 40)
        .opacity(isLit ? 1 : 0.5)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(move.direction.destination). \(move.outcome)")
    }

    // MARK: - La séquence

    private func play() async {
        try? await Task.sleep(for: .milliseconds(340))
        guard !Task.isCancelled else { return }

        // Mouvement réduit : la planche se réduit à sa légende, allumée d'un
        // coup. C'est déjà l'état dans lequel la séquence se termine.
        guard !reduceMotion else {
            withAnimation(SwipeMotion.reveal) { revealed = Set(Move.allCases) }
            return
        }

        // La séquence tourne tant que la planche est ouverte : on n'arrive pas
        // forcément dessus au premier temps, et le geste qu'on cherche est parfois
        // celui qui vient de passer. `task` est annulée au retrait de la vue, ce
        // qui met fin à la boucle sans qu'on ait à la surveiller.
        while !Task.isCancelled {
            for move in Move.allCases {
                await demonstrate(move)
                guard !Task.isCancelled else { return }
            }

            // Un temps d'arrêt avec les trois lignes allumées : c'est le résumé
            // du tour, et le seul moment où la planche se lit d'un coup d'œil.
            try? await Task.sleep(for: .milliseconds(1100))
            guard !Task.isCancelled else { return }

            // Les lignes s'éteignent pour que la lumière puisse redescendre la
            // liste au tour suivant : trois lignes déjà allumées ne diraient plus
            // lequel des trois gestes est en train d'être joué.
            withAnimation(SwipeMotion.reveal) { revealed = [] }
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled else { return }
        }
    }

    /// Un temps de la séquence : la carte glisse jusqu'au seuil avec son tampon,
    /// sort par son bord, sa ligne s'allume, et la carte suivante remonte.
    private func demonstrate(_ move: Move) async {
        withAnimation(SwipeMotion.reveal) { current = move }

        withAnimation(.spring(response: 0.4, dampingFraction: 0.76)) {
            offset = move.hold(width: Self.cardWidth, height: cardHeight)
            intensity = 1
        }
        // Le temps de lire le tampon. Sans cette pause, le verdict passe sous
        // l'œil et le geste n'apprend rien.
        try? await Task.sleep(for: .milliseconds(520))
        guard !Task.isCancelled else { return }

        withAnimation(SwipeMotion.flight) {
            offset = move.exit(width: Self.cardWidth, height: cardHeight)
        }
        // La ligne s'allume pendant que la carte finit de sortir : c'est cette
        // simultanéité qui fait lire le rangement comme la conséquence du geste,
        // et non comme une étape de plus.
        withAnimation(SwipeMotion.lock) { _ = revealed.insert(move) }
        withAnimation(.easeIn(duration: 0.12).delay(0.14)) { cardOpacity = 0 }
        try? await Task.sleep(for: .milliseconds(280))
        guard !Task.isCancelled else { return }

        // La remise au centre se fait hors champ, sans animation : ce qui remonte
        // est la carte suivante, pas la même qui reviendrait sur ses pas.
        current = nil
        offset = .zero
        intensity = 0
        scale = 0.96

        // Une frame de battement, sinon SwiftUI regroupe la remise à zéro et
        // l'animation qui suit dans la même passe : la carte réapparaîtrait déjà
        // à sa taille, sans remonter.
        try? await Task.sleep(for: .milliseconds(16))
        guard !Task.isCancelled else { return }

        withAnimation(.easeOut(duration: 0.24)) {
            cardOpacity = 1
            scale = 1
        }
        try? await Task.sleep(for: .milliseconds(150))
    }
}

// MARK: - Les trois gestes

/// Les trois gestes, dans l'ordre où on les enseigne : le plus fréquent d'abord,
/// et la watchlist en dernier — c'est celui dont on se souvient le mieux, parce
/// qu'il est le seul à sortir par le haut. Les lignes de la légende suivent le
/// même ordre, si bien que la lumière descend la liste au lieu d'y sauter.
///
/// Le geste enseigné n'est pas une notion propre à l'aide : c'est une
/// `SwipeDirection`, avec son verdict, sa destination et sa flèche. `Move`
/// n'ajoute que ce qui appartient à la planche — la conséquence en clair, et la
/// géométrie de la scène.
private enum Move: CaseIterable, Hashable {
    case right, left, up

    var direction: SwipeDirection {
        switch self {
        case .right: .right
        case .left: .left
        case .up: .up
        }
    }

    /// Ce qui arrive au film. La destination dit *où*, ceci dit *pourquoi* — et
    /// pour le refus, ce n'est pas une destination du tout : c'est un délai.
    var outcome: String {
        switch self {
        case .right: String(localized: "Vous l'avez vu", bundle: .app)
        case .left: String(localized: "Il reviendra plus tard", bundle: .app)
        case .up: String(localized: "Envie de le voir", bundle: .app)
        }
    }

    /// Le point d'arrêt du geste : assez loin pour que le verdict soit acquis,
    /// assez près pour que la carte reste **entière** dans la scène — c'est là
    /// qu'on lit le tampon, il ne peut pas être coupé.
    ///
    /// La montée est donnée en points et non en fraction de la carte : la marge
    /// au-dessus d'elle est ce que la scène a de plus rare, et une proportion la
    /// dépasserait dès que la vignette grandirait.
    func hold(width: CGFloat, height: CGFloat) -> CGSize {
        switch self {
        case .right: CGSize(width: width * 0.62, height: 6)
        case .left: CGSize(width: -width * 0.62, height: 6)
        case .up: CGSize(width: 0, height: -21)
        }
    }

    /// La sortie : franchement hors de la scène, qui la coupe.
    func exit(width: CGFloat, height: CGFloat) -> CGSize {
        switch self {
        case .right: CGSize(width: width + 240, height: 34)
        case .left: CGSize(width: -(width + 240), height: 34)
        case .up: CGSize(width: 0, height: -(height + 130))
        }
    }
}

#Preview("L'aide aux gestes") {
    ZStack {
        Ink.ground.ignoresSafeArea()
        SwipeGuideOverlay(onClose: {})
    }
}
