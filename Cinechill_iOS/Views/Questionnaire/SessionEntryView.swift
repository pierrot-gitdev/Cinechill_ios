//
//  SessionEntryView.swift
//  Cinechill_iOS
//

import SwiftUI

/// L'entrée de CinéMatch : on vient de franchir la porte, on est dans la Salle.
///
/// L'écran d'origine décrivait une procédure — une icône, un paragraphe, trois
/// étapes numérotées, un bouton « Commencer » qui n'ouvrait qu'un formulaire. Un
/// mur d'affiches l'a remplacé, qui avait au moins le mérite de montrer des
/// films. **Ce mur disparaît à son tour**, et pour une raison de récit : une fois
/// la porte gagnée, montrer un catalogue contredit exactement ce qu'on vient
/// d'obtenir. On n'est plus devant une vitrine, on est assis quelque part.
///
/// Ce qui le remplace tient en deux décisions.
///
/// - **Le décor est la salle elle-même**, éclairée à plein : c'est le premier
///   palier de `SalleLight`, et la séance l'éteindra cran par cran jusqu'au
///   verdict. La lumière est la seule jauge d'avancement du parcours.
/// - **La question est projetée sur la toile**, et on y répond en allumant des
///   fauteuils. Le geste dit la réponse avant qu'on ait lu le texte, et c'est le
///   seul « vous » de groupe de l'application : il s'adresse aux personnes
///   devant l'écran, pas à celle qui tient le téléphone.
///
/// **L'encart du verdict de la veille n'est pas revenu** : il coupait l'entrée en
/// deux et arrivait avant qu'on ait rien demandé. `VerdictPromptView` existe
/// toujours et n'attend qu'un endroit qui lui aille — la conséquence à connaître
/// est que, sans lui, plus rien ne recueille « Je l'ai adoré », le signal le plus
/// sûr du trait et l'une des sources du coup de cœur.
struct SessionEntryView: View {
    @Binding var audience: Audience?
    let onProfileTap: () -> Void
    let onNext: () -> Void

    var body: some View {
        SalleStage(question: String(localized: "Vous êtes combien ?", bundle: .app)) {
            content
        }
        .overlay(alignment: .top) {
            AppHeaderView(
                title: String(localized: "CinéMatch", bundle: .app),
                onProfileTap: onProfileTap
            )
        }
    }

    // MARK: - La question

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)

            // Quatre cases plutôt qu'une rangée de puces : le libellé le plus
            // long tient sur deux lignes sans rétrécir les autres, et chaque
            // case a la place d'allumer ses fauteuils.
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10),
                ],
                spacing: 10
            ) {
                ForEach(Audience.allCases, id: \.self) { value in
                    SeatChoice(audience: value, isOn: audience == value) {
                        audience = value
                    }
                }
            }

            // La conséquence, dite au moment où elle devient vraie plutôt qu'en
            // permanence : elle ne prend de la place que si elle en dit.
            if audience == .family {
                Text("On écartera l'horreur et les films interdits aux moins de 18 ans.", bundle: .app)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Ink.ink3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
                    .transition(.opacity)
            }

            PlanButton(
                title: String(localized: "Suivant", bundle: .app),
                isEnabled: audience != nil,
                action: onNext
            )
            .padding(.top, 22)
        }
        .padding(.horizontal, Metrics.margin)
        .padding(.bottom, Metrics.margin)
        .animation(Metrics.unfold, value: audience)
    }
}

/// Une composition, dite en fauteuils allumés.
///
/// Le nombre de sièges est la réponse ; le libellé la confirme. C'est le seul
/// endroit de l'application où une puce devient un dessin, et il le mérite : la
/// question porte sur les gens assis dans la salle qu'on vient de dessiner.
private struct SeatChoice: View {
    /// La hauteur du plus long libellé sur deux lignes, marges comprises. Les
    /// quatre cases s'y alignent, quel que soit leur texte.
    private static let cellHeight: CGFloat = 92

    let audience: Audience
    let isOn: Bool
    let action: () -> Void

    /// Combien de sièges, et combien d'entre eux sont des petits. La famille se
    /// dit par deux grands et deux petits : personne n'a besoin de lire le
    /// libellé pour le comprendre.
    private var seats: (total: Int, small: Int) {
        switch audience {
        case .alone: (1, 0)
        case .couple: (2, 0)
        case .friends: (3, 0)
        case .family: (4, 2)
        }
    }

    var body: some View {
        Button(action: action) {
            // Une hauteur plancher commune, et le contenu centré dedans.
            // « En famille, avec des enfants » replie sur deux lignes et
            // faisait sa case plus haute que les trois autres ; réserver la
            // hauteur du plus long égalise la grille, et le centrage évite que
            // les libellés d'une seule ligne pendent en haut de leur case.
            VStack(spacing: 10) {
                seatRow
                Text(audience.label)
                    .font(.system(size: 11.5, weight: isOn ? .semibold : .regular))
                    .foregroundStyle(isOn ? Ink.ink : Ink.ink2)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: Self.cellHeight)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                    .fill(isOn ? Ink.light.opacity(0.07) : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                    .strokeBorder(isOn ? Ink.light : Ink.ruleSet, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(minHeight: Metrics.control)
        .accessibilityLabel(audience.label)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }

    private var seatRow: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(0 ..< seats.total, id: \.self) { index in
                let isSmall = index >= seats.total - seats.small
                RoundedRectangle(cornerRadius: isSmall ? 4 : 6, style: .continuous)
                    .fill(isOn ? Ink.ink : Color(hex: 0x2A3644))
                    .frame(width: isSmall ? 14 : 17, height: isSmall ? 10 : 18)
            }
        }
        .frame(height: 18, alignment: .bottom)
        .accessibilityHidden(true)
    }
}

#Preview("L'entrée") {
    struct Harness: View {
        @State private var audience: Audience? = .couple

        var body: some View {
            ZStack {
                SalleBackdrop(light: SalleLight.entry).ignoresSafeArea()
                SessionEntryView(audience: $audience, onProfileTap: {}, onNext: {})
            }
        }
    }
    return Harness()
}
