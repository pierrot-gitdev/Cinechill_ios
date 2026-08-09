//
//  AchievementCelebrationOverlay.swift
//  Cinechill_iOS
//

import SwiftUI

/// La popup de félicitations — badge tout juste débloqué, ou palier tout
/// juste franchi.
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
        case .tier(let tier): tierCard(tier)
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

    // MARK: - Palier franchi

    /// Le palier n'emprunte plus `seal.fill` au système : c'est le mark lui-même,
    /// à la teinte du palier. Célébrer un palier de cinéphilie avec un sceau
    /// générique, c'était le seul endroit de l'app où l'on avait un objet
    /// illustratif propre et où l'on n'a pas su s'en servir.
    private func tierCard(_ tier: CinephileTier) -> some View {
        VStack(spacing: 0) {
            eyebrow(String(localized: "Nouveau palier", bundle: .app), color: tier.accent)

            CinechillPlanOutline(lineWidth: 1.4)
                .foregroundStyle(tier.accent)
                .frame(width: 116, height: 116)
                .padding(.top, 26)

            Text(String(localized: "Palier \(tier.label.capitalized)", bundle: .app))
                .planTitle(24)
                .foregroundStyle(Ink.ink)
                .padding(.top, 26)

            Text("Votre profil change de couleur avec vous.", bundle: .app)
                .font(.system(size: 13))
                .foregroundStyle(Ink.ink2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)

            PlanButton(title: String(localized: "Continuer", bundle: .app), height: Metrics.control, action: onDismiss)
                .padding(.top, 28)
        }
        .padding(cardPadding)
        .frame(maxWidth: 340)
        .background(cardBackground(accent: tier.accent))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "Nouveau palier : \(tier.label.capitalized)", bundle: .app))
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
