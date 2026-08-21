//
//  SwipeCardView.swift
//  Cinechill_iOS
//

import SwiftUI

/// Le verdict en cours de composition pendant un drag.
enum SwipeVerdict {
    case seen
    case notSeen
    case watchlist

    var label: String {
        switch self {
        case .seen: String(localized: "VU", bundle: .app)
        case .notSeen: String(localized: "PAS VU", bundle: .app)
        case .watchlist: String(localized: "À VOIR", bundle: .app)
        }
    }

    /// Le verdict parle la langue de la fiche film et des grilles : **plein =
    /// vu, creux = à voir, éteint = écarté**. L'écran employait un vert, un bleu
    /// et un gris pour ces trois mêmes états, soit un troisième vocabulaire de
    /// couleur pour la même information.
    var tint: Color {
        switch self {
        case .seen: Ink.light
        case .notSeen: Ink.ink3
        case .watchlist: Ink.light
        }
    }

    var isFilled: Bool {
        switch self {
        case .seen: true
        case .notSeen, .watchlist: false
        }
    }

    /// Le tampon apparaît du côté d'où vient la carte, comme dans tous les decks
    /// de swipe : c'est le repère que les gens ont déjà.
    var alignment: Alignment {
        switch self {
        case .seen: .topLeading
        case .notSeen: .topTrailing
        // La watchlist sort par le haut, et la plaque occupe le bas de la carte :
        // son tampon se pose entre les deux coins hauts, jamais sur le titre.
        case .watchlist: .top
        }
    }


}

/// La carte du deck — « la planche ».
///
/// La refonte porte sur une seule décision : **la légende n'est plus posée sur
/// l'affiche, elle est posée à côté**. L'écran empilait un dégradé de 190 pt sur
/// l'image et écrivait par-dessus ; le titre passait donc du blanc franc au gris
/// laiteux selon le film, et une affiche claire le perdait. La plaque est un
/// aplat de nuit, fermée par un filet : la typographie y est toujours à la même
/// valeur, quelle que soit l'affiche.
///
/// Ce que la plaque a permis de gagner ensuite :
/// - **Une hiérarchie éditoriale.** L'année et le genre passent au-dessus du
///   titre, en niveau de service : on lit d'abord de quoi il s'agit, puis quoi.
/// - **La note comme mesure.** Un chiffre seul ne se compare pas ; le filet sous
///   le chiffre place le film sur l'échelle d'un coup d'œil, avec le composant de
///   mesure du reste de l'application.
/// - **Un dépliage au lieu d'un panneau.** Le synopsis fait grandir la plaque
///   vers le haut plutôt que de recouvrir la carte d'un second calque qui
///   redonnait le titre : rien ne se dédouble, et le mouvement dit d'où vient le
///   texte.
struct SwipeCardView: View {
    let card: SwipeCard
    /// Le genre principal, résolu par l'appelant : la carte ne connaît pas le
    /// répertoire des genres.
    var genre: String?
    /// Verdict en cours et son intensité (0 au repos, 1 au seuil de validation).
    var verdict: SwipeVerdict?
    var verdictIntensity: Double = 0
    /// Le seuil est franchi : le verdict est acquis si le doigt se lève.
    var isArmed = false
    /// Le synopsis est ouvert — géré par le deck pour se refermer au swipe.
    var isSynopsisOpen = false
    /// Décalage de l'affiche dans son cadre pendant le geste.
    var parallax: CGSize = .zero
    /// Le doigt est posé sur la carte : on nomme les trois issues.
    var showsCompass = false
    var onTap: () -> Void = {}

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
    }


    var body: some View {
        ZStack(alignment: .bottom) {
            poster
            plate
            compass
            shape.strokeBorder(Ink.rule, lineWidth: 1)
            verdictBorder
        }
        .background(Ink.ground)
        .clipShape(shape)
        // Le dépliage s'anime ici, au plus près de ce qui bouge : le déplacement
        // de la carte sous le doigt est appliqué par le deck, au-dessus de cette
        // portée, et reste donc au contact — refermer le synopsis d'un
        // glissement ne fait pas traîner la carte.
        .animation(SwipeMotion.unfold, value: isSynopsisOpen)
        .contentShape(shape)
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "\(card.title), \(card.displayYear), note \(card.voteAverageText) sur 10", bundle: .app))
        .accessibilityHint(String(localized: "Balaie à droite si tu l'as vu, continue plus loin si tu l'as adoré, à gauche sinon, vers le haut pour l'ajouter à la watchlist", bundle: .app))
    }

    // MARK: - L'affiche

    private var poster: some View {
        PosterImageView(url: card.posterURL)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Le débord donne au décalage de quoi puiser : sans lui, l'affiche
            // découvrirait un bord du cadre au premier point de parallaxe.
            .scaleEffect(1.06)
            .offset(parallax)
            // Le synopsis ouvert, l'affiche recule d'un cran : le texte a la
            // valeur haute, l'image devient le fond dont elle parle.
            .overlay(Ink.ground.opacity(isSynopsisOpen ? 0.45 : 0))
    }

    // MARK: - La plaque

    private var plate: some View {
        VStack(spacing: 0) {
            // Le voile éteint l'affiche avant le filet : c'est lui, et non un
            // bord franc au milieu de l'image, qui amène la plaque. Il reste
            // hors de l'aplat, sinon il n'éteindrait rien.
            LinearGradient(
                colors: [Ink.ground.opacity(0), Ink.ground.opacity(0.72)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 46)

            VStack(spacing: 0) {
                PlanEdge(tint: Ink.ruleSet)

                VStack(alignment: .leading, spacing: 0) {
                    eyebrow
                    titleRow
                        .padding(.top, 9)

                    if isSynopsisOpen, let overview = card.overview, !overview.isEmpty {
                        Text(overview)
                            .font(.system(size: 13.5))
                            .foregroundStyle(Ink.ink2)
                            .lineSpacing(3.5)
                            .lineLimit(7)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 15)
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 15)
                .padding(.bottom, hasOverview ? 15 : 18)
                .frame(maxWidth: .infinity, alignment: .leading)

                if hasOverview {
                    PlanEdge(tint: Ink.rule)
                    synopsisHandle
                }
            }
            .background(Ink.ground)
        }
    }

    private var hasOverview: Bool {
        card.overview?.isEmpty == false
    }

    /// L'année et le genre, au-dessus du titre : on lit de quoi il s'agit avant
    /// de lire quoi.
    private var eyebrow: some View {
        Text(eyebrowText)
            .planLabel()
            .foregroundStyle(Ink.ink2)
            .lineLimit(1)
    }

    private var eyebrowText: String {
        var parts = [card.displayYear]
        if let genre, !genre.isEmpty { parts.append(genre) }
        return parts.joined(separator: " · ")
    }

    private var titleRow: some View {
        HStack(alignment: .bottom, spacing: 14) {
            Text(card.title)
                .planTitle(25)
                .foregroundStyle(Ink.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            if card.voteAverage != nil { rating }
        }
    }

    /// La note, et la mesure qui la situe. Un 8,4 seul ne se compare à rien ; le
    /// filet dit tout de suite où le film tombe sur l'échelle.
    private var rating: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Text(card.voteAverageText)
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Ink.ink)

            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Ink.rule)
                    .frame(width: 30, height: 1)
                Rectangle()
                    .fill(Ink.ink2)
                    .frame(width: 30 * ratingFraction, height: 1)
            }
        }
        .padding(.bottom, 3)
        .accessibilityHidden(true)
    }

    private var ratingFraction: CGFloat {
        guard let voteAverage = card.voteAverage else { return 0 }
        return min(1, max(0, CGFloat(voteAverage) / 10))
    }

    /// La poignée du synopsis. Elle n'est pas un bouton : c'est toute la carte
    /// qui ouvre et referme — la poignée dit seulement que c'est possible, et
    /// dans quel sens ça va bouger.
    private var synopsisHandle: some View {
        HStack {
            Text(isSynopsisOpen ? String(localized: "Fermer", bundle: .app) : String(localized: "Résumé", bundle: .app))
                .planLabel()
                .contentTransition(.identity)
            Spacer(minLength: 0)
            SwipeArrowGlyph(direction: isSynopsisOpen ? .down : .up, side: 11)
        }
        .foregroundStyle(Ink.ink2)
        .padding(.horizontal, 18)
        .frame(height: 34)
    }

    // MARK: - Verdict

    /// Le liseré prend la teinte du verdict et s'épaissit d'un demi-point au
    /// seuil : le bord de la carte est le premier endroit où l'œil se poserait
    /// de toute façon.
    @ViewBuilder
    private var verdictBorder: some View {
        if let verdict {
            shape
                .strokeBorder(verdict.tint, lineWidth: isArmed ? 1.5 : 1)
                .opacity(verdictIntensity)
        }
    }


    /// Elle cède la place dès qu'une direction est engagée : à un tiers du
    /// parcours le tampon du verdict a pris le relais, et laisser les deux se
    /// superposer ferait lire deux réponses à la même question.
    private var compass: some View {
        SwipeCompass(engaged: verdict, intensity: verdictIntensity, isArmed: isArmed)
            // Elle reste tant qu'un verdict est en cours, même si le doigt a
            // quitté la zone qui l'avait fait apparaître : c'est elle qui porte
            // le retour du geste, il ne peut pas s'éteindre en cours de route.
            .opacity(showsCompass || verdict != nil ? 1 : 0)
            .animation(SwipeMotion.unfold, value: showsCompass)
    }

}

#Preview("La planche") {
    ZStack {
        Ink.ground.ignoresSafeArea()
        VStack(spacing: 24) {
            SwipeCardView(
                card: .preview,
                genre: "Science-fiction",
                verdict: .seen,
                verdictIntensity: 1,
                isArmed: true
            )
            .frame(width: 290, height: 470)
        }
    }
}

extension SwipeCard {
    /// La carte des aperçus et de la démonstration hors ligne.
    static var preview: SwipeCard {
        SwipeCard(
            tmdbId: 157336,
            title: "Interstellar",
            posterPath: nil,
            overview: "Dans un futur proche, la Terre se meurt : les récoltes brûlent et les tempêtes de poussière avalent les villes. Un ancien pilote de la NASA est recruté pour franchir un trou de ver et chercher, de l'autre côté, un monde où l'humanité pourrait recommencer.",
            voteAverage: 8.4,
            voteCount: 34000,
            genreIds: [12, 18, 878],
            releaseDate: "2014-11-05",
            source: "pillars"
        )
    }
}
