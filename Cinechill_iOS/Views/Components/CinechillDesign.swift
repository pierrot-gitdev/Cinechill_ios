//
//  CinechillDesign.swift
//  Cinechill_iOS
//

import SwiftUI

// MARK: - Les encres

/// Les six valeurs de l'application — direction « Le Plan ».
///
/// Trois gris, deux états, un fond. En régime courant un écran n'en emploie que
/// quatre : l'accent et l'écart ne servent qu'à dire quelque chose. Toutes sont
/// dérivées de `CinechillPalette`, à plat — aucun dégradé, aucune lueur.
///
/// Ces valeurs ont d'abord vécu dans `AuthComponents` sous le nom `AuthInk`,
/// parce que l'authentification est le premier écran à avoir été dessiné dans
/// cette direction. Elles n'ont jamais été propres à l'authentification :
/// `AuthInk` n'est plus qu'un renvoi vers ce jeu-ci.
enum Ink {
    static let ground = CinechillPalette.night          // #0A0F16
    static let ink = Color(hex: 0xEDF1F5)
    static let ink2 = Color(hex: 0x8D9AA8)              // étain
    static let ink3 = Color(hex: 0x59636E)              // ardoise

    static let rule = Color(hex: 0xC6D3DF).opacity(0.13)
    static let ruleSet = Color(hex: 0xC6D3DF).opacity(0.26)

    /// Le point de lumière de la famille d'icônes. **Deux occurrences par écran
    /// au maximum**, et jamais autrement que sous la forme d'un carré de 5 pt.
    /// Un sens unique dans toute l'app : *acquis, vérifié, non lu*.
    static let light = CinechillPalette.light           // #7FE3FF
    /// L'écart. Seule teinte chaude de l'application — elle remplace partout le
    /// rouge et l'orange du système.
    static let warn = Color(hex: 0xE5A276)
}

// MARK: - Les mesures

/// Les mesures communes à toutes les planches. Elles ne dépendent d'aucun
/// contenu : c'est cette constance — pas un effet — qui fait qu'on reconnaît
/// l'application d'un écran à l'autre.
enum Metrics {
    /// Marge d'écran. Une seule, partout.
    static let margin: CGFloat = 24
    /// Gouttière entre deux objets d'une même rangée.
    static let gutter: CGFloat = 10

    /// **Le seul rayon de l'application.** Les avatars sont des cercles, tout le
    /// reste — contrôles, affiches, logos, vignettes — passe par cette valeur.
    static let radius: CGFloat = 3

    static let field: CGFloat = 32
    static let button: CGFloat = 52
    static let buttonSecondary: CGFloat = 48
    /// La hauteur d'un contrôle posé dans le contenu (barre de décision, chips
    /// pleine largeur) : plus bas qu'une action de plancher d'authentification.
    static let control: CGFloat = 44

    /// Une transition de valeur, pas une animation : rien ne se déplace.
    static let shift = Animation.easeOut(duration: 0.18)
    /// Le dépliage d'un bloc — seul mouvement de mise en page autorisé.
    static let unfold = Animation.easeOut(duration: 0.2)
}

// MARK: - Le point

/// Le seul aplat d'accent de l'interface, à la taille de la famille d'icônes.
///
/// Il ne dit qu'une chose, partout : **c'est acquis**. Un pseudo libre à
/// l'inscription, une plateforme retenue dans les réglages, un film déjà vu sur
/// une affiche, une notification non lue. Un signe, un sens.
struct PlanLight: View {
    var tint: Color = Ink.light

    var body: some View {
        Rectangle()
            .fill(tint)
            .frame(width: 5, height: 5)
            .transition(.opacity)
    }
}

/// Le même point, creux. Il dit « prévu » là où le point plein dit « acquis » :
/// c'est le remplissage, et non la teinte, qui porte la différence — l'écran
/// reste donc lisible en niveaux de gris.
struct PlanLightOutline: View {
    var tint: Color = Ink.light

    var body: some View {
        Rectangle()
            .strokeBorder(tint, lineWidth: 1)
            .frame(width: 6, height: 6)
            .transition(.opacity)
    }
}

// MARK: - Le filet

/// Le plafond, le plancher, la clôture d'un bloc. Un point, à plat.
struct PlanEdge: View {
    var tint: Color = Ink.rule

    var body: some View {
        Rectangle()
            .fill(tint)
            .frame(height: 1)
    }
}

/// Le filet qui s'évanouit à ses extrémités — celui de `AppHeaderView` et de
/// `AppTabBar`. Il sépare sans jamais fermer, et c'est son égalité d'un écran à
/// l'autre qui fait lire l'application comme un seul volume.
struct PlanRail: View {
    var tint: Color = CinechillPalette.rimMid.opacity(0.20)

    var body: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: tint, location: 0.12),
                .init(color: tint, location: 0.88),
                .init(color: .clear, location: 1)
            ],
            startPoint: .leading, endPoint: .trailing
        )
        .frame(height: 1)
    }
}

// MARK: - Le voile

/// Ce qui remplace `ultraThinMaterial` sous un en-tête épinglé.
///
/// Un matériau translucide emprunte l'esthétique du système d'exploitation —
/// c'est exactement ce que la direction cherche à ne pas faire. Le voile obtient
/// la même lisibilité avec la nuit de la marque, et s'éteint avant son filet :
/// c'est lui, et non un bord de matériau, qui marque la limite.
struct PlanScrim: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: Ink.ground, location: 0),
                .init(color: Ink.ground, location: 0.62),
                .init(color: Ink.ground.opacity(0), location: 1)
            ],
            startPoint: .top, endPoint: .bottom
        )
    }
}

// MARK: - Typographie

extension View {
    /// Le niveau de service : libellés de section, actions secondaires, unités.
    /// Interlettré parce que des capitales serrées ne se lisent pas, semi-gras
    /// parce qu'à 10 pt une graisse fine disparaît.
    func planLabel() -> some View {
        self.font(.system(size: 10, weight: .semibold))
            .tracking(1.8)
            .textCase(.uppercase)
    }

    /// Un titre de planche. La graisse et l'interlettrage sont ceux de
    /// l'authentification — c'est la seule échelle de titre de l'application.
    func planTitle(_ size: CGFloat = 22) -> some View {
        self.font(.system(size: size, weight: .light))
            // −0,028 em, la valeur du parcours d'authentification.
            .kerning(-size * 0.028)
    }
}

/// Le libellé d'une section, avec sa note de service optionnelle.
///
/// La note dit la **conséquence**, jamais le mécanisme : « ce qui n'est pas chez
/// vous ne vous sera pas proposé » plutôt que la liste des écrans qui consomment
/// le réglage.
struct PlanSectionLabel: View {
    let title: String
    var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .planLabel()
                .foregroundStyle(Ink.ink2)

            if let note, !note.isEmpty {
                Text(note)
                    .font(.system(size: 12))
                    .foregroundStyle(Ink.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Les actions

/// L'action principale : le seul aplat clair de l'écran, et donc le seul objet
/// sur lequel l'œil n'hésite pas.
///
/// Le chargement se joue dans le bouton — un filet de 2 pt parcourt son bord
/// bas. Pas de voile, pas de roue posée ailleurs, et le libellé dit ce qui se
/// passe plutôt que de disparaître.
struct PlanButton: View {
    let title: String
    var loadingTitle: String?
    var isLoading: Bool = false
    var isEnabled: Bool = true
    /// Hauteur du bouton. Le plancher d'authentification est plus haut qu'une
    /// action posée dans le contenu.
    var height: CGFloat = Metrics.button
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var travel: CGFloat = -1

    var body: some View {
        Button(action: action) {
            Text(isLoading ? (loadingTitle ?? title) : title)
                .font(.system(size: 15.5, weight: .semibold))
                .kerning(-0.08)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .foregroundStyle(Ink.ground)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(Ink.ink)
                .overlay(alignment: .bottomLeading) { progress }
                .clipShape(RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous))
                .opacity(isEnabled && !isLoading ? 1 : 0.6)
        }
        .buttonStyle(PressableScaleStyle(scale: 0.985))
        .disabled(isLoading || !isEnabled)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isLoading ? [.updatesFrequently] : [])
    }

    @ViewBuilder
    private var progress: some View {
        if isLoading && !reduceMotion {
            GeometryReader { geo in
                Rectangle()
                    .fill(Ink.ground.opacity(0.4))
                    .frame(width: geo.size.width * 0.45, height: 2)
                    .offset(x: travel * geo.size.width)
                    .onAppear {
                        travel = -0.45
                        withAnimation(.easeInOut(duration: 1.05).repeatForever(autoreverses: false)) {
                            travel = 1
                        }
                    }
            }
            .frame(height: 2)
        }
    }
}

/// Une porte tierce, un retour, une action de second rang. Contour, jamais
/// rempli : ce sont des alternatives, pas des concurrentes de l'action
/// principale.
struct PlanSecondaryButton: View {
    let title: String
    var icon: Image?
    var isEnabled: Bool = true
    var height: CGFloat = Metrics.buttonSecondary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                if let icon {
                    icon.font(.system(size: 15, weight: .medium))
                }
                Text(title)
                    .font(.system(size: 14.5, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(Ink.ink)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                    .stroke(Ink.ruleSet, lineWidth: 1)
            )
            .opacity(isEnabled ? 1 : 0.5)
        }
        .buttonStyle(PressableScaleStyle(scale: 0.985))
        .disabled(!isEnabled)
    }
}

// MARK: - La puce

/// Une puce d'option : contour au repos, aplat d'encre une fois retenue.
///
/// Un seul composant pour tous les sélecteurs de l'app — axe de la galerie,
/// budget de la watchlist, filtre des badges, génération des réglages. Les
/// quatre en avaient chacun un, avec quatre dessins et trois couleurs.
struct PlanChip: View {
    let title: String
    var isOn: Bool
    /// La puce d'exclusion : barrée et à l'écart, la forme dit le retrait avant
    /// la couleur — l'écran reste lisible en niveaux de gris.
    var isExcluded: Bool = false
    var fillsWidth: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12.5, weight: isOn ? .semibold : .regular))
                .monospacedDigit()
                .strikethrough(isExcluded, pattern: .solid, color: Ink.warn)
                .foregroundStyle(foreground)
                .lineLimit(1)
                .frame(maxWidth: fillsWidth ? .infinity : nil)
                .padding(.horizontal, fillsWidth ? 6 : 12)
                .padding(.vertical, 8)
                .background {
                    if isOn {
                        RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                            .fill(Ink.ink)
                    } else {
                        RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                            .strokeBorder(isExcluded ? Ink.warn.opacity(0.5) : Ink.ruleSet, lineWidth: 1)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous))
        }
        .buttonStyle(PressableScaleStyle(scale: 0.96))
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }

    private var foreground: Color {
        if isOn { return Ink.ground }
        return isExcluded ? Ink.warn : Ink.ink2
    }
}

// MARK: - La mesure

/// Une progression, tracée plutôt que remplie.
///
/// Un filet d'un point, la part parcourue à l'encre pleine, et un repère de
/// lumière au front. C'est le même dispositif que le plafond et le plancher :
/// la mesure se lit, elle ne se remplit pas. Remplace partout les jauges en
/// dégradé indigo→rose.
struct PlanProgressRule: View {
    /// Entre 0 et 1.
    let fraction: Double
    var showsMarker: Bool = true

    private var clamped: Double { min(1, max(0, fraction)) }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Ink.rule)
                    .frame(height: 1)

                Rectangle()
                    .fill(Ink.ink)
                    .frame(width: max(1, proxy.size.width * clamped), height: 1)

                if showsMarker, clamped > 0, clamped < 1 {
                    Rectangle()
                        .fill(Ink.light)
                        .frame(width: 1, height: 5)
                        .offset(x: max(0, proxy.size.width * clamped - 0.5))
                }
            }
            .frame(height: 5)
        }
        .frame(height: 5)
        .accessibilityHidden(true)
    }
}

// MARK: - L'état vide

/// L'état vide type : une icône de la famille, ce qui manque, la conséquence,
/// et une sortie. Jamais un encouragement creux.
///
/// Un seul composant pour les six implémentations qui existaient — galerie,
/// watchlist, deck (×2), hall, genre — et qui reposaient toutes sur
/// `.borderedProminent` teinté d'indigo.
struct PlanEmptyState: View {
    var icon: CinechillHallIcon = .salle
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?
    var secondaryTitle: String?
    var secondaryAction: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            CinechillHallIconView(icon)
                .frame(width: 34, height: 34)
                .foregroundStyle(Ink.ink3)

            Text(title)
                .planTitle(21)
                .foregroundStyle(Ink.ink)
                .multilineTextAlignment(.center)
                .padding(.top, 22)

            Text(message)
                .font(.system(size: 13.5))
                .foregroundStyle(Ink.ink2)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)

            if let actionTitle, let action {
                PlanButton(title: actionTitle, height: Metrics.control, action: action)
                    .padding(.top, 30)
            }

            if let secondaryTitle, let secondaryAction {
                Button(action: secondaryAction) {
                    Text(secondaryTitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Ink.ink2)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(Ink.ruleSet)
                                .frame(height: 1)
                                .offset(y: 2)
                        }
                }
                .buttonStyle(.plain)
                .padding(.top, 18)
            }
        }
        .frame(maxWidth: 300)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - La possession

/// Ce qu'on sait déjà d'un film, posé sur son affiche.
///
/// Point plein : vu. Point creux : en watchlist. C'est le **remplissage**, et
/// non la teinte, qui porte la différence — là où l'app codait les deux mêmes
/// états par un vert et un bleu, appris par convention. L'écran reste lisible en
/// niveaux de gris, et le signe est celui de toute l'application.
struct LibraryMark: View {
    let inGallery: Bool
    let inWatchlist: Bool

    var body: some View {
        Group {
            if inGallery {
                PlanLight()
                    .accessibilityLabel("Déjà vu")
            } else if inWatchlist {
                PlanLightOutline()
                    .accessibilityLabel("Dans votre watchlist")
            }
        }
        // Le point est posé sur une affiche, dont on ne connaît pas la valeur :
        // un liseré de nuit le détache quel que soit le fond.
        .shadow(color: Ink.ground.opacity(0.9), radius: 1.5)
    }
}

#Preview("Composants") {
    ZStack {
        Ink.ground.ignoresSafeArea()
        ScrollView {
            VStack(alignment: .leading, spacing: 34) {
                PlanSectionLabel(
                    title: "Mes abonnements",
                    note: "Ce qui n'est pas chez vous ne vous sera pas proposé."
                )

                HStack(spacing: 7) {
                    PlanChip(title: "Action", isOn: false) {}
                    PlanChip(title: "Horreur", isOn: false, isExcluded: true) {}
                    PlanChip(title: "Drame", isOn: true) {}
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text("214").planTitle(26).foregroundStyle(Ink.ink).monospacedDigit()
                        Text("sur 250 · il en reste 36").planLabel().foregroundStyle(Ink.ink3)
                    }
                    PlanProgressRule(fraction: 0.86)
                }

                PlanEdge()

                HStack(spacing: 10) {
                    PlanButton(title: "Vu", height: Metrics.control) {}
                    PlanSecondaryButton(title: "À voir", height: Metrics.control) {}
                }

                PlanEmptyState(
                    icon: .hall,
                    title: "Votre collection est vide",
                    message: "Chaque film que vous marquez comme vu vient s'y ranger, et dessine peu à peu votre profil de cinéphile.",
                    actionTitle: "Commencer à swiper",
                    action: {}
                )
            }
            .padding(Metrics.margin)
        }
    }
}
