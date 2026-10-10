//
//  OnboardingPages.swift
//  Cinechill_iOS
//

import SwiftUI

// MARK: - CinéMatch

/// Ce que fait CinéMatch, montré par son résultat : le film de ce soir. Le
/// questionnaire n'y est pas ; on le découvrira en s'en servant.
struct OnboardingCineMatchPage: View {
    @State private var isShown = false

    private var film: OnboardingFilm { OnboardingFilms.tonight }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            OnboardingHeading(
                eyebrow: "CinéMatch",
                title: String(localized: "Trouve ton film avec Cinechill.", bundle: .app)
            )

            HStack {
                Text("Le film de ce soir", bundle: .app)
                    .planLabel()
                    .foregroundStyle(Ink.ink2)
                Spacer(minLength: 8)
                HStack(spacing: 5) {
                    ForEach(0 ..< 5, id: \.self) { index in
                        Rectangle()
                            .fill(index == 0 ? Ink.ink : Ink.ink3)
                            .frame(width: 5, height: 5)
                    }
                }
                .accessibilityHidden(true)
            }
            .padding(.top, 30)
            .onboardingRise(isShown, delay: 0.12)

            card
                .padding(.top, 12)
                .onboardingRise(isShown, delay: 0.05)
                .layoutPriority(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Metrics.margin)
        .padding(.top, 16)
        .onAppear { isShown = true }
    }

    /// La carte des cinq de CinéMatch : l'affiche entière, une plaque fermée
    /// par un filet, l'année et le genre au-dessus du titre.
    private var card: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)

        return VStack(spacing: 0) {
            // L'affiche cède la première quand la place manque.
            PosterImageView(url: film.posterURL, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 110, maxHeight: 220)
                .padding(.vertical, 12)
                .background(Ink.ground2)

            PlanEdge(tint: Ink.ruleSet)

            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: "\(film.year) · \(film.genre)")
                    .planLabel()
                    .foregroundStyle(Ink.ink2)
                Text(film.title)
                    .planTitle(23)
                    .foregroundStyle(Ink.ink)
                    .padding(.top, 6)
                if let runtime = film.runtimeMinutes {
                    Text(verbatim: "\(runtime / 60)h\(String(format: "%02d", runtime % 60))")
                        .planFont(13)
                        .monospacedDigit()
                        .foregroundStyle(Ink.ink2)
                        .padding(.top, 4)
                }
                HStack(spacing: 8) {
                    PlanLight()
                    Text("Il devrait te plaire.", bundle: .app)
                        .planFont(13)
                        .foregroundStyle(Ink.ink)
                }
                .padding(.top, 10)
            }
            .padding(.horizontal, 16)
            .padding(.top, 13)
            .padding(.bottom, 15)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Ink.ground)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Ink.rule, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Tes goûts d'abord

/// Pourquoi CinéMatch est fermé : il lui faut 100 films vus. Les 100 cases se
/// remplissent sous les yeux, puis le cadenas s'ouvre : on voit la cible avant
/// de la lire.
struct OnboardingTastesPage: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var filled = 0

    private static let target = 100
    private static let columns = 20

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            OnboardingHeading(
                eyebrow: String(localized: "Avant ton premier CinéMatch", bundle: .app),
                title: String(localized: "D'abord, Cinechill doit connaître tes goûts.", bundle: .app),
                text: String(localized: "Cinechill choisit d'après les films que tu as vus. CinéMatch s'ouvre quand ta galerie en compte 100.", bundle: .app)
            )

            cells
                .padding(.top, 36)
                .accessibilityHidden(true)

            HStack(alignment: .firstTextBaseline) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(verbatim: "\(filled)")
                        .planTitle(30)
                        .monospacedDigit()
                        .foregroundStyle(Ink.ink)
                        .contentTransition(.numericText())
                    Text(String(localized: "sur \(Self.target)", bundle: .app))
                        .planFont(14)
                        .foregroundStyle(Ink.ink3)
                }
                Spacer(minLength: 8)
                HStack(spacing: 8) {
                    OnboardingLockGlyph(isOpen: filled >= Self.target)
                        .stroke(style: StrokeStyle(lineWidth: 1.3, lineJoin: .round))
                        .frame(width: 11, height: 13)
                    Text(verbatim: "CinéMatch")
                        .planFont(13.5)
                }
                .foregroundStyle(filled >= Self.target ? Ink.ink : Ink.ink2)
                .animation(.easeOut(duration: 0.2), value: filled >= Self.target)
            }
            .padding(.top, 14)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(localized: "100 films vus pour ouvrir CinéMatch", bundle: .app))

            Text("Tu auras ensuite quatre étapes plus courtes à valider.", bundle: .app)
                .planFont(13)
                .foregroundStyle(Ink.ink3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 12)
                .overlay(alignment: .top) { Rectangle().fill(Ink.rule).frame(height: 1) }
                .padding(.top, 18)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Metrics.margin)
        .padding(.top, 16)
        .task { await fill() }
    }

    /// Vingt colonnes, cinq rangées : cent affiches miniatures.
    private var cells: some View {
        VStack(spacing: 3) {
            ForEach(0 ..< Self.target / Self.columns, id: \.self) { row in
                HStack(spacing: 3) {
                    ForEach(0 ..< Self.columns, id: \.self) { column in
                        let isOn = row * Self.columns + column < filled
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(isOn ? Color(hex: DoorArtifactKey.memoire.hue) : Ink.ground3)
                            .overlay {
                                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                    .strokeBorder(Ink.rule, lineWidth: isOn ? 0 : 1)
                            }
                            .aspectRatio(2 / 3, contentMode: .fit)
                    }
                }
            }
        }
    }

    private func fill() async {
        try? await Task.sleep(for: .milliseconds(500))
        guard !reduceMotion else {
            filled = Self.target
            return
        }
        // Une case toutes les 14 millisecondes : 1,4 seconde pour cent films.
        while filled < Self.target, !Task.isCancelled {
            filled += 1
            try? await Task.sleep(for: .milliseconds(14))
        }
    }
}

/// Le cadenas de CinéMatch : fermé, puis ouvert à cent films.
struct OnboardingLockGlyph: Shape {
    var isOpen: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let bodyTop = rect.minY + rect.height * 0.45
        path.addRoundedRect(
            in: CGRect(x: rect.minX, y: bodyTop, width: rect.width, height: rect.maxY - bodyTop),
            cornerSize: CGSize(width: 1.5, height: 1.5)
        )
        let inset = rect.width * 0.22
        let radius = rect.width / 2 - inset
        let arcY = rect.minY + radius
        path.move(to: CGPoint(x: rect.minX + inset, y: bodyTop))
        path.addLine(to: CGPoint(x: rect.minX + inset, y: arcY))
        path.addArc(
            center: CGPoint(x: rect.midX, y: arcY),
            radius: radius,
            startAngle: .degrees(180),
            endAngle: .degrees(0),
            clockwise: false
        )
        // Ouvert, l'anse ne redescend pas dans le corps.
        if !isOpen {
            path.addLine(to: CGPoint(x: rect.maxX - inset, y: bodyTop))
        }
        return path
    }
}

// MARK: - Tes plateformes

/// Les plateformes, demandées ici et non plus dans une feuille à part : c'est
/// une question du parcours, au même rythme que les autres. Chaque toucher
/// est enregistré tout de suite.
struct OnboardingPlatformsPage: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    @Environment(MediaCatalog.self) private var catalog
    @State private var loadFailed = false

    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                OnboardingHeading(
                    eyebrow: String(localized: "Tes plateformes", bundle: .app),
                    title: String(localized: "Tu regardes sur quelles plateformes ?", bundle: .app),
                    text: String(localized: "On ne te propose que ce que tu peux regarder.", bundle: .app)
                )

                Group {
                    if catalog.platforms.isEmpty, loadFailed {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text("Impossible de charger les plateformes.", bundle: .app)
                                .planFont(13)
                                .foregroundStyle(Ink.ink2)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 8)
                            Button {
                                Task { await load() }
                            } label: {
                                Text("Réessayer", bundle: .app)
                                    .planLabel()
                                    .foregroundStyle(Ink.ink)
                                    .frame(minHeight: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(PressableScaleStyle())
                        }
                    } else if catalog.platforms.isEmpty {
                        HStack(spacing: 10) {
                            CinechillSpinner(size: 18)
                            Text("Chargement des plateformes…", bundle: .app)
                                .planFont(13)
                                .foregroundStyle(Ink.ink2)
                        }
                    } else {
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(catalog.platforms) { platform in
                                tile(platform)
                            }
                        }
                    }
                }
                .padding(.top, 26)
            }
            .padding(.horizontal, Metrics.margin)
            .padding(.top, 16)
            .padding(.bottom, 16)
        }
        .scrollIndicators(.hidden)
        .task { await load() }
    }

    private func tile(_ platform: StreamingPlatform) -> some View {
        let isOn = libraryStore.preferredPlatformIDs.contains(platform.id)
        let shape = RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)

        return Button {
            Haptics.selection()
            var selection = libraryStore.preferredPlatformIDs
            if isOn { selection.remove(platform.id) } else { selection.insert(platform.id) }
            libraryStore.setPreferredPlatforms(selection)
        } label: {
            HStack(spacing: 10) {
                Group {
                    if let url = platform.logoURL {
                        PosterImageView(url: url)
                    } else {
                        Ink.ground3
                    }
                }
                .frame(width: 26, height: 26)
                .clipShape(RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous))

                Text(platform.name)
                    .planFont(14.5, weight: .semibold)
                    .foregroundStyle(Ink.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 4)

                PlanLight()
                    .opacity(isOn ? 1 : 0)
                    .scaleEffect(isOn ? 1 : 0.6)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background(isOn ? Ink.ground2 : Color.clear, in: shape)
            .overlay(shape.strokeBorder(isOn ? Ink.ink : Ink.ruleSet, lineWidth: 1))
            .contentShape(shape)
            .animation(.easeOut(duration: 0.16), value: isOn)
        }
        .buttonStyle(PressableScaleStyle(scale: 0.97))
        .accessibilityLabel(platform.name)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }

    private func load() async {
        loadFailed = false
        await catalog.loadIfNeeded()
        loadFailed = catalog.platforms.isEmpty
    }
}
