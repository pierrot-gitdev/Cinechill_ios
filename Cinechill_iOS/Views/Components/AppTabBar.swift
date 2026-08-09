//
//  AppTabBar.swift
//  Cinechill_iOS
//

import SwiftUI

/// La barre d'onglets — direction « Le Seuil ».
///
/// Il n'y a pas de barre, au sens d'un objet posé sur l'interface : il y a **un seuil qui
/// traverse l'écran**. Un filet d'un point, et sur ce filet une lampe posée au-dessus de
/// l'onglet actif. Un rail flottant est un objet *sur* l'interface ; un seuil en *fait partie* —
/// et pour une marque bâtie sur un plan d'architecture, c'est la seconde lecture qui est juste.
///
/// Trois décisions structurent le dessin :
/// - **Pleine largeur, aucune marge.** On récupère les 28 points que mangeaient les marges d'un
///   rail, ce qui élargit les cibles des onglets d'extrémité — les plus durs à atteindre au pouce.
/// - **Rien ne bouge en dehors de la lumière.** Les icônes ne grossissent pas, ne se déplacent
///   pas, ne changent pas de forme : elles s'éclairent. C'est ce qui rend le mouvement calme.
/// - **Les libellés occupent toujours leur place**, mais seul celui de l'onglet actif est visible.
///   Au repos la barre est aussi nue qu'une barre sans texte, et il n'y a jamais de décalage de
///   mise en page au changement d'onglet.
struct AppTabBar: View {
    @Binding var selectedTab: Int

    private static let height: CGFloat = 58

    private static let items: [(icon: CinechillIcon, label: String)] = [
        (.accueil, String(localized: "Accueil", bundle: .app)),
        (.cinematch, String(localized: "CinéMatch", bundle: .app)),
        (.decouvrir, String(localized: "Découvrir", bundle: .app)),
        (.galerie, String(localized: "Galerie", bundle: .app)),
        (.watchlist, String(localized: "Watchlist", bundle: .app))
    ]

    /// Courbe du volet 04 : lente au départ, longue à l'arrivée. Une lumière qui se déplace trop
    /// vite scintille au lieu de couler.
    private static let travel = Animation.timingCurve(0.22, 1, 0.32, 1, duration: 0.44)

    var body: some View {
        GeometryReader { proxy in
            let step = proxy.size.width / CGFloat(Self.items.count)
            let lampX = step * (CGFloat(selectedTab) + 0.5)

            ZStack(alignment: .topLeading) {
                // La nappe descend de la lampe et s'évanouit avant le bas. Plus large que sur un
                // rail : sans conteneur pour la retenir, la lumière doit se diffuser davantage
                // pour créer une zone repérable.
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [light.opacity(0.26), light.opacity(0.05), .clear],
                            center: .top, startRadius: 0, endRadius: 76
                        )
                    )
                    .frame(width: min(168, step * 2.8), height: 76)
                    .position(x: lampX, y: 26)
                    .allowsHitTesting(false)

                sill

                Capsule()
                    .fill(lamp)
                    .frame(width: 24, height: 2.5)
                    .shadow(color: light.opacity(0.85), radius: 5)
                    .shadow(color: light.opacity(0.45), radius: 12)
                    .position(x: lampX, y: 1)
                    .allowsHitTesting(false)

                tabRow
            }
            .animation(Self.travel, value: selectedTab)
        }
        .frame(height: Self.height)
        .background { scrim }
    }

    // MARK: Le seuil

    /// Le filet s'évanouit aux extrémités : il sépare sans jamais fermer.
    private var sill: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: sillTint, location: 0.12),
                .init(color: sillTint, location: 0.88),
                .init(color: .clear, location: 1)
            ],
            startPoint: .leading, endPoint: .trailing
        )
        .frame(height: 1)
        .frame(maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(false)
    }

    /// Sans fond propre, la lisibilité dépend de ce qui défile dessous. Le voile la garantit
    /// quel que soit le contenu, et se prolonge sous l'indicateur d'accueil.
    private var scrim: some View {
        LinearGradient(
            stops: [
                .init(color: Ink.ground.opacity(0), location: 0),
                .init(color: Ink.ground.opacity(0.92), location: 0.5),
                .init(color: Ink.ground, location: 1)
            ],
            startPoint: .top, endPoint: .bottom
        )
        .ignoresSafeArea(edges: .bottom)
    }

    // MARK: Les onglets

    private var tabRow: some View {
        HStack(spacing: 0) {
            ForEach(Self.items.indices, id: \.self) { index in
                tabButton(index)
            }
        }
    }

    private func tabButton(_ index: Int) -> some View {
        let item = Self.items[index]
        let isSelected = selectedTab == index

        return Button {
            select(index)
        } label: {
            VStack(spacing: 3) {
                CinechillNavIcon(item.icon)
                    .frame(width: 22, height: 22)

                Text(item.label)
                    .font(.system(size: 8.5, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    // L'opacité, jamais la présence : la place reste réservée, donc rien
                    // ne se déplace quand le libellé apparaît.
                    .opacity(isSelected ? 1 : 0)
                    .animation(.easeInOut(duration: 0.28), value: isSelected)
            }
            .foregroundStyle(isSelected ? activeTint : inactiveTint)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.label)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func select(_ index: Int) {
        guard selectedTab != index else { return }
        Haptics.selection()
        selectedTab = index
    }

    // MARK: Palette

    // L'app est verrouillée en sombre (voir `Cinechill_iOSApp`) : l'identité étain/cyan n'est
    // dessinée que pour ce fond, donc une seule palette suffit ici.
    private let light = CinechillPalette.light
    private let lamp = CinechillPalette.lightPale
    private let sillTint = CinechillPalette.rimMid.opacity(0.24)
    private let activeTint = Color(red: 0.93, green: 0.97, blue: 1.0)
    private let inactiveTint = Color.secondary.opacity(0.78)
}

#Preview("Le Seuil") {
    VStack(spacing: 0) {
        Spacer()
        AppTabBar(selectedTab: .constant(0))
    }
    .background(
        LinearGradient(
            colors: [CinechillPalette.night, CinechillPalette.nightDeep],
            startPoint: .top, endPoint: .bottom
        )
        .ignoresSafeArea()
    )
}
