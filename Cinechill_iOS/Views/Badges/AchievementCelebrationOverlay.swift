//
//  AchievementCelebrationOverlay.swift
//  Cinechill_iOS
//

import SwiftUI

/// La popup de félicitations : badge tout juste décroché, ou distinction tout
/// juste décernée.
///
/// Affichée par-dessus l'app entière plutôt que dans un seul onglet : la
/// galerie grossit depuis le deck, la fiche film ou CinéMatch, et le moment
/// doit être célébré quel que soit l'endroit d'où il vient.
struct AchievementCelebrationOverlay: View {
    let celebration: BadgesViewModel.Celebration
    var onEquip: () -> Void
    var onDismiss: () -> Void

    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Ink.ground.opacity(0.86)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            card
                .scaleEffect(appeared ? 1 : 0.8)
                .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            Haptics.success()
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.45, dampingFraction: 0.72)) {
                appeared = true
            }
        }
        .accessibilityAddTraits(.isModal)
    }

    @ViewBuilder
    private var card: some View {
        switch celebration {
        case .badge(let badge): badgeCard(badge)
        case .distinction(let distinction): distinctionCard(distinction)
        }
    }

    // MARK: - Badge débloqué

    private func badgeCard(_ badge: Badge) -> some View {
        VStack(spacing: 0) {
            eyebrow(String(localized: "Nouveau badge", bundle: .app), color: badge.rarity.accent)

            BadgeView(badge: badge, isUnlocked: true, size: 138)
                .padding(.top, 22)

            Text(badge.name)
                .planTitle(24)
                .foregroundStyle(Ink.ink)
                .multilineTextAlignment(.center)
                .padding(.top, 24)

            Text(badge.rarity.label)
                .planLabel()
                .foregroundStyle(badge.rarity.accent)
                .padding(.top, 9)

            Text(badge.condition)
                .font(.system(size: 13))
                .foregroundStyle(Ink.ink2)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)

            PlanButton(title: String(localized: "Équiper ce badge", bundle: .app), height: Metrics.control, action: onEquip)
                .padding(.top, 28)

            Button(String(localized: "Plus tard", bundle: .app), action: onDismiss)
                .font(.system(size: 13))
                .foregroundStyle(Ink.ink2)
                .padding(.top, 16)
        }
        .padding(cardPadding)
        .frame(maxWidth: 340)
        .background(cardBackground(accent: badge.rarity.accent))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "Nouveau badge débloqué : \(badge.name), \(badge.rarity.label). \(badge.condition)", bundle: .app))
    }

    // MARK: - Distinction décernée

    /// La cérémonie. C'est la version haute de la carte d'un badge, et cette
    /// différence d'échelle est ce qui installe la hiérarchie entre une citation
    /// et un rang : un badge se décroche, une distinction se décerne.
    ///
    /// L'emblème est montré seul, sans sa couronne. Au moment du franchissement
    /// la couronne vient de se refermer et n'apprend plus rien ; ce qui est neuf,
    /// et donc ce qu'on montre, c'est l'objet frappé au pied.
    private func distinctionCard(_ distinction: Distinction) -> some View {
        VStack(spacing: 0) {
            eyebrow(distinction.citation, color: distinction.accent)

            DistinctionEmblem(distinction: distinction)
                .stroke(
                    distinction.accent,
                    style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)
                )
                .frame(width: 116, height: 116)
                .padding(.top, 26)

            Text(distinction.label)
                .planTitle(24)
                .foregroundStyle(Ink.ink)
                .padding(.top, 26)

            Text(distinction.matiere)
                .planLabel()
                .foregroundStyle(distinction.accent)
                .padding(.top, 9)

            Text(String(localized: "Pour \(distinction.lowerBound) films portés à ton dossier.", bundle: .app))
                .font(.system(size: 13))
                .foregroundStyle(Ink.ink2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)

            Text(verbatim: Millesime.roman(Calendar.current.component(.year, from: Date())))
                .planLabel()
                .foregroundStyle(Ink.ink3)
                .padding(.top, 18)

            PlanButton(title: String(localized: "Continuer", bundle: .app), height: Metrics.control, action: onDismiss)
                .padding(.top, 26)
        }
        .padding(cardPadding)
        .frame(maxWidth: 340)
        .background(cardBackground(accent: distinction.accent))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            String(localized: "\(distinction.citation) : \(distinction.label), pour \(distinction.lowerBound) films", bundle: .app)
        )
    }

    // MARK: - Pièces communes

    private var cardPadding: EdgeInsets {
        EdgeInsets(top: 30, leading: 26, bottom: 22, trailing: 26)
    }

    private func eyebrow(_ text: String, color: Color) -> some View {
        Text(text)
            .planLabel()
            .foregroundStyle(color)
    }

    /// Le seul conteneur que la direction admette encore : une célébration est
    /// bien un bloc posé *sur* l'interface, qu'on ferme d'un tap. Le filet est à
    /// la teinte de ce qu'on vient d'obtenir — l'unique endroit où une couleur de
    /// données borde une surface, parce que c'est précisément son sujet.
    private func cardBackground(accent: Color) -> some View {
        RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
            .fill(Ink.ground)
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                    .strokeBorder(accent.opacity(0.45), lineWidth: 1)
            )
    }
}

#Preview {
    ZStack {
        Ink.ground.ignoresSafeArea()
        AchievementCelebrationOverlay(
            celebration: .badge(BadgeCatalog.all[2]),
            onEquip: {},
            onDismiss: {}
        )
    }
}
