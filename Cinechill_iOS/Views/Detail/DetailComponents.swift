//
//  DetailComponents.swift
//  Cinechill_iOS
//

import SwiftUI

/// Les pièces que partagent les trois fiches — film, série, saison.
///
/// Une saison est un film : sa fiche a le même héros, le même plafond, les
/// mêmes plateformes, le même plancher. Ces pièces vivaient dans la fiche film
/// en privé ; elles en sortent telles quelles pour que la série et la saison
/// ne soient pas des copies qui divergeront.

// MARK: - Le héros

/// Le backdrop, son voile, l'affiche et le titre. Hauteur fixe : c'est elle que
/// le plafond mesure pour se poser.
struct DetailHero: View {
    static let height: CGFloat = 260
    /// La taille réelle du titre, qui suit Dynamic Type. Le héros grandit du
    /// surplus de ses trois lignes : à hauteur fixe, un titre agrandi montait
    /// jusque sous les boutons du haut.
    @ScaledMetric(relativeTo: .title2) private var heroTitleSize: CGFloat = 24
    private var heroFrameHeight: CGFloat { Self.height + max(0, heroTitleSize - 24) * 3 }

    let backdropURL: URL?
    let posterPath: String?
    let title: String
    /// La ligne de service au-dessus du titre : le nom de la série sur la fiche
    /// d'une saison.
    var eyebrow: String?
    /// La ligne sous le titre : l'accroche.
    var tagline: String?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: heroFrameHeight)
                .overlay { backdrop }
                .clipped()
                .overlay(scrim)

            HStack(alignment: .bottom, spacing: 14) {
                PosterTile(posterPath: posterPath, title: title, width: 64)

                VStack(alignment: .leading, spacing: 7) {
                    if let eyebrow, !eyebrow.isEmpty {
                        Text(eyebrow)
                            .planLabel()
                            .foregroundStyle(Ink.ink2)
                            .lineLimit(1)
                    }

                    Text(title)
                        .planTitle(24)
                        .foregroundStyle(Ink.ink)
                        .lineLimit(3)
                        .minimumScaleFactor(0.75)

                    if let tagline, !tagline.isEmpty {
                        Text(tagline)
                            .planFont(12)
                            .foregroundStyle(Ink.ink2)
                            .lineLimit(2)
                    }
                }
                .padding(.bottom, 2)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, Metrics.margin)
            .padding(.bottom, 14)
        }
        .frame(height: heroFrameHeight)
    }

    @ViewBuilder
    private var backdrop: some View {
        if let backdropURL {
            PosterImageView(url: backdropURL)
        } else {
            Ink.ground
        }
    }

    private var scrim: some View {
        LinearGradient(
            stops: [
                .init(color: Ink.ground.opacity(0.55), location: 0),
                .init(color: Ink.ground.opacity(0.10), location: 0.30),
                .init(color: Ink.ground.opacity(0.80), location: 0.78),
                .init(color: Ink.ground, location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .allowsHitTesting(false)
    }
}

// MARK: - Le plafond

/// Nu sur le backdrop, posé une fois le héros passé — le même que celui de la
/// fiche film, aux mêmes valeurs.
struct DetailCeiling: View {
    let title: String
    /// De 0 (backdrop nu) à 1 (plafond posé).
    let progress: Double
    let onBack: () -> Void
    var onTrailer: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                glyphButton(.back, label: String(localized: "Retour", bundle: .app), action: onBack)

                Text(title)
                    .planFont(17, weight: .semibold)
                    .foregroundStyle(Ink.ink)
                    .lineLimit(1)
                    .opacity(progress)
                    // Invisible, le titre se lisait quand même à VoiceOver, juste
                    // avant celui du héros : deux fois le même nom d'affilée.
                    .accessibilityHidden(progress < 0.5)

                Spacer(minLength: 8)

                if let onTrailer {
                    glyphButton(.play, label: String(localized: "Voir la bande-annonce", bundle: .app), action: onTrailer)
                }
            }
            // 11 et non 16 : la cible passe de 34 à 44 pt, le tracé reste où il était.
            .padding(.horizontal, 11)
            .padding(.top, 4)
            .padding(.bottom, 10)

            PlanRail().opacity(progress)
        }
        .background {
            PlanScrim()
                .opacity(progress)
                .ignoresSafeArea(edges: .top)
        }
        .animation(.easeOut(duration: 0.15), value: progress < 0.5)
    }

    /// La bascule se joue sur les 90 derniers points du héros, comme sur la
    /// fiche film.
    static func progress(forOffset offset: CGFloat) -> Double {
        let start = DetailHero.height - 130
        let travel: CGFloat = 90
        return Double(min(1, max(0, (-offset - start) / travel)))
    }

    private func glyphButton(
        _ glyph: DetailGlyph.Kind, label: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            DetailGlyph(kind: glyph)
                .stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                .foregroundStyle(Ink.ink)
                .frame(width: 22, height: 22)
                .shadow(color: .black.opacity(1 - progress), radius: 5)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableScaleStyle(scale: 0.9))
        .accessibilityLabel(label)
    }
}

// MARK: - Les sections

/// Le filet, le libellé de section et, à droite, une note de service.
struct DetailSectionHeader: View {
    let title: String
    var trailing: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PlanEdge()

            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .planLabel()
                    .foregroundStyle(Ink.ink2)
                Spacer(minLength: 8)
                if let trailing {
                    Text(trailing)
                        .planLabel()
                        .monospacedDigit()
                        .foregroundStyle(Ink.ink3)
                }
            }
            .padding(.top, 20)
            .padding(.bottom, 12)
        }
        .padding(.horizontal, Metrics.margin)
    }
}

/// Où le voir : tes plateformes d'abord, les autres en retrait, rien de caché.
/// Le même dessin que la fiche film.
struct DetailProvidersRow: View {
    let providers: [TMDBDetailWatchProviderItem]
    let preferredIDs: Set<String>
    /// Le titre à chercher dans l'app de la plateforme.
    let title: String

    @Environment(\.openURL) private var openURL

    var body: some View {
        let mine = providers.filter { preferredIDs.contains(String($0.providerID)) }
        let others = providers.filter { !preferredIDs.contains(String($0.providerID)) }

        VStack(alignment: .leading, spacing: 0) {
            DetailSectionHeader(title: String(localized: "Où le voir", bundle: .app))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Metrics.gutter) {
                    ForEach(mine, id: \.providerID) { provider in
                        button(provider, isMine: true)
                    }

                    if !mine.isEmpty, !others.isEmpty {
                        Rectangle()
                            .fill(Ink.ruleSet)
                            .frame(width: 1, height: 22)
                            .padding(.horizontal, 3)
                    }

                    ForEach(others, id: \.providerID) { provider in
                        button(provider, isMine: false)
                    }
                }
                .padding(.horizontal, Metrics.margin)
            }
            .scrollClipDisabled()
        }
        .padding(.top, 24)
    }

    private func button(_ provider: TMDBDetailWatchProviderItem, isMine: Bool) -> some View {
        Button {
            open(provider)
        } label: {
            Group {
                if let url = provider.logoURL {
                    PosterImageView(url: url)
                } else {
                    Text(provider.providerName.prefix(3).uppercased())
                        .planFont(9, weight: .semibold)
                        .foregroundStyle(Ink.ink2)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Ink.ground3)
                }
            }
            .frame(width: 42, height: 42)
            .clipShape(RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                    .strokeBorder(isMine ? Ink.ink : Ink.rule, lineWidth: 1)
            )
            .opacity(isMine ? 1 : 0.4)
            .saturation(isMine ? 1 : 0.25)
        }
        .buttonStyle(PressableScaleStyle(scale: 0.92))
        .accessibilityLabel(provider.providerName)
        .accessibilityValue(isMine
                            ? String(localized: "Sur tes plateformes", bundle: .app)
                            : String(localized: "Hors de tes plateformes", bundle: .app))
    }

    private func open(_ provider: TMDBDetailWatchProviderItem) {
        for candidate in StreamingProviderLink.appURLs(forProviderID: provider.providerID, title: title)
        where UIApplication.shared.canOpenURL(candidate) {
            UIApplication.shared.open(candidate)
            return
        }
        guard let url = provider.webURL else { return }
        openURL(url)
    }
}

/// Le synopsis, dans le dessin de la fiche film.
struct DetailSynopsis: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DetailSectionHeader(title: String(localized: "Synopsis", bundle: .app))

            Text(text)
                .planFont(14)
                .foregroundStyle(Ink.ink2)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Metrics.margin)
        }
        .padding(.top, 24)
    }
}

/// Le casting, dans le dessin de la fiche film.
struct DetailCast: View {
    let cast: [TMDBDetailCastMember]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DetailSectionHeader(title: String(localized: "Casting", bundle: .app))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    // Par position : un même acteur peut tenir plusieurs rôles.
                    ForEach(Array(cast.enumerated()), id: \.offset) { _, member in
                        VStack(spacing: 8) {
                            Group {
                                if let url = member.profileURL {
                                    PosterImageView(url: url)
                                } else {
                                    Ink.ground3
                                }
                            }
                            .frame(width: 56, height: 56)
                            .clipShape(Circle())
                            .overlay(Circle().strokeBorder(Ink.rule, lineWidth: 1))

                            VStack(spacing: 2) {
                                Text(member.name)
                                    .planFont(10.5, weight: .medium)
                                    .foregroundStyle(Ink.ink)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)

                                if let character = member.character, !character.isEmpty {
                                    Text(character)
                                        .planFont(9.5)
                                        .foregroundStyle(Ink.ink2)
                                        .multilineTextAlignment(.center)
                                        .lineLimit(2)
                                }
                            }
                        }
                        .frame(width: 68)
                    }
                }
                .padding(.horizontal, Metrics.margin)
            }
            .scrollClipDisabled()
        }
        .padding(.top, 24)
    }
}

// MARK: - Le plancher

/// Un bouton du plancher de décision : aplat d'encre quand il est retenu,
/// contour sinon, aplat de papier quand il est l'action principale. Le point
/// dit lequel — plein pour « vu », creux pour « à voir ».
struct DetailFloorButton: View {
    enum Style { case paper, line, inked }
    enum Mark { case none, acquired, planned }

    let title: String
    var style: Style = .line
    var mark: Mark = .none
    var isWaiting = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Text(title)
                    .planFont(14, weight: style == .line ? .regular : .semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                if isWaiting {
                    CinechillSpinner(size: 12, tint: style == .line ? .brand : .onPaper)
                } else if mark == .acquired {
                    PlanLight(tint: Ink.ground)
                } else if mark == .planned {
                    PlanLightOutline(tint: Ink.ground)
                }
            }
            .foregroundStyle(style == .line ? Ink.ink : Ink.ground)
            .frame(maxWidth: .infinity)
            .frame(minHeight: Metrics.control)
            .background {
                switch style {
                case .paper:
                    RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                        .fill(Ink.paper)
                case .inked:
                    RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                        .fill(Ink.ink)
                case .line:
                    RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                        .strokeBorder(Ink.ruleSet, lineWidth: 1)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous))
        }
        .buttonStyle(PressableScaleStyle(scale: 0.96))
        .accessibilityAddTraits(style == .inked ? [.isSelected] : [])
        // Le faisceau qui tourne ne se voit pas : VoiceOver doit dire l'attente.
        .accessibilityValue(isWaiting ? String(localized: "Enregistrement…", bundle: .app) : "")
    }
}

// MARK: - L'échec

/// Une fiche qui n'est pas venue : ce qui manque, en une ligne, et une issue.
///
/// Elle se pose sous le générique, là où tournait l'attente, et non au pied de
/// la page : sur un iPhone SE l'erreur tombait sous le plancher, et l'écran
/// restait à moitié vide sans rien en dire. Le message du serveur n'y paraît
/// plus : « HTTP 503 » ne dit rien à personne.
struct DetailLoadFailure: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 11) {
            PlanLight(tint: Ink.warn)

            Text(message)
                .planFont(13)
                .foregroundStyle(Ink.warn)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            Button(action: retry) {
                Text("Réessayer", bundle: .app)
                    .planLabel()
                    .foregroundStyle(Ink.ink)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableScaleStyle())
        }
        .padding(.horizontal, Metrics.margin)
        .padding(.top, 14)
    }
}

// MARK: - Sonde de défilement

struct HeroOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Les glyphes de la fiche

/// Le retour et la lecture, dans l'écriture « La Gravure » : grille de 24, trait
/// de 1,5, extrémités rondes. La pointe de lecture est ouverte — une flèche
/// pleine serait un second élément plein, ce que la famille n'admet pas.
struct DetailGlyph: Shape {
    enum Kind { case back, play }

    let kind: Kind

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * scale, y: rect.minY + y * scale)
        }

        var path = Path()
        switch kind {
        case .back:
            path.move(to: p(14.6, 4.8))
            path.addLine(to: p(8, 12))
            path.addLine(to: p(14.6, 19.2))
        case .play:
            path.move(to: p(8.6, 5.6))
            path.addLine(to: p(18.4, 12))
            path.addLine(to: p(8.6, 18.4))
            path.closeSubpath()
        }
        return path
    }
}

/// Le cœur géométrique de l'artéfact, à l'échelle d'un bouton : deux arcs et
/// une pointe, le même tracé que l'emblème du médaillon.
struct DetailHeartShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * w, y: rect.minY + y * h)
        }

        var path = Path()
        path.move(to: p(0.5, 1))
        path.addCurve(to: p(0, 0.32), control1: p(0.18, 0.76), control2: p(0, 0.56))
        path.addCurve(to: p(0.27, 0), control1: p(0, 0.12), control2: p(0.12, 0))
        path.addCurve(to: p(0.5, 0.16), control1: p(0.38, 0), control2: p(0.46, 0.06))
        path.addCurve(to: p(0.73, 0), control1: p(0.54, 0.06), control2: p(0.62, 0))
        path.addCurve(to: p(1, 0.32), control1: p(0.88, 0), control2: p(1, 0.12))
        path.addCurve(to: p(0.5, 1), control1: p(1, 0.56), control2: p(0.82, 0.76))
        path.closeSubpath()
        return path
    }
}

// MARK: - La bande-annonce

/// La bande-annonce, jouée dans l'app et non dans YouTube : la salle se
/// baisse, l'écran passe au format cinéma, et l'on revient à la fiche d'un
/// tap. C'est le geste de CinéMatch, qui la joue sur l'écran de sa salle, et
/// le même lecteur.
private struct TrailerTheater: View {
    let key: String
    let onClose: () -> Void

    var body: some View {
        ZStack {
            // Toucher la salle autour de l'écran la rallume.
            Color.black.opacity(0.94)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)
                .accessibilityHidden(true)

            CineMatchTrailerPlayer(key: key)
                .aspectRatio(16 / 9, contentMode: .fit)
                .frame(maxWidth: .infinity)
        }
        .overlay(alignment: .topTrailing) {
            Button(action: onClose) {
                TrailerCloseGlyph()
                    .stroke(style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                    .foregroundStyle(Ink.ink)
                    .frame(width: 22, height: 22)
                    .frame(width: Metrics.control, height: Metrics.control)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableScaleStyle(scale: 0.9))
            .padding(.trailing, 10)
            .accessibilityLabel(String(localized: "Fermer la bande-annonce", bundle: .app))
        }
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, onClose)
    }
}

/// La croix, dans l'écriture des glyphes de la fiche : grille de 24, trait
/// de 1,5, extrémités rondes.
private struct TrailerCloseGlyph: Shape {
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

extension View {
    /// Joue la bande-annonce dont la clé YouTube est posée, par-dessus tout
    /// l'écran, plancher compris. Un fondu court, sans mouvement : la salle
    /// s'éteint, elle ne glisse pas.
    func trailerTheater(_ key: Binding<String?>) -> some View {
        overlay {
            if let value = key.wrappedValue {
                TrailerTheater(key: value) {
                    withAnimation(.easeOut(duration: 0.2)) { key.wrappedValue = nil }
                }
                .transition(.opacity)
            }
        }
    }
}
