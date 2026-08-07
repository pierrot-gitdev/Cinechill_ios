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
            Color.black.opacity(0.55)
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
        VStack(spacing: 18) {
            eyebrow("NOUVEAU BADGE", color: badge.rarity.accent)

            BadgeView(badge: badge, isUnlocked: true, size: 140)
                .padding(.vertical, 4)

            VStack(spacing: 6) {
                Text(badge.name)
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .multilineTextAlignment(.center)

                rarityPill(badge.rarity)

                Text(badge.condition)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                    .padding(.top, 2)
            }

            VStack(spacing: 10) {
                primaryButton("Équiper ce badge", action: onEquip)
                Button("Plus tard", action: onDismiss)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 6)
        }
        .padding(cardPadding)
        .frame(maxWidth: 340)
        .background(cardBackground(accent: badge.rarity.accent))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Nouveau badge débloqué : \(badge.name), \(badge.rarity.label). \(badge.condition)")
    }

    // MARK: - Palier franchi

    private func tierCard(_ tier: CinephileTier) -> some View {
        VStack(spacing: 18) {
            eyebrow("NOUVEAU PALIER", color: tier.accent)

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [tier.accent.opacity(0.4), .clear],
                            center: .center, startRadius: 4, endRadius: 80
                        )
                    )
                    .frame(width: 150, height: 150)
                Image(systemName: "seal.fill")
                    .font(.system(size: 62))
                    .foregroundStyle(tier.accent)
                    .shadow(color: tier.accent.opacity(0.55), radius: 18)
            }
            .padding(.vertical, 4)

            VStack(spacing: 6) {
                Text("Palier \(tier.label.capitalized)")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                Text("Votre carte de profil change de couleur avec vous.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
            }

            primaryButton("Continuer", action: onDismiss)
                .padding(.top, 6)
        }
        .padding(cardPadding)
        .frame(maxWidth: 340)
        .background(cardBackground(accent: tier.accent))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Nouveau palier : \(tier.label.capitalized)")
    }

    // MARK: - Pièces communes

    private var cardPadding: EdgeInsets {
        EdgeInsets(top: 30, leading: 28, bottom: 24, trailing: 28)
    }

    private func eyebrow(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .heavy, design: .rounded))
            .kerning(1.4)
            .foregroundStyle(color)
    }

    private func rarityPill(_ rarity: BadgeRarity) -> some View {
        Text(rarity.label.uppercased())
            .font(.system(size: 10, weight: .heavy, design: .rounded))
            .kerning(1.2)
            .foregroundStyle(rarity.accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(rarity.accent.opacity(0.15), in: Capsule())
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(colors: [.indigo, .pink], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
        }
        .buttonStyle(PressableScaleStyle(scale: 0.97))
    }

    private func cardBackground(accent: Color) -> some View {
        RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(Color(.secondarySystemBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(accent.opacity(0.4), lineWidth: 1.5)
            )
            .shadow(color: .black.opacity(0.35), radius: 30, y: 12)
    }
}

#Preview {
    ZStack {
        Color(.systemBackground).ignoresSafeArea()
        AchievementCelebrationOverlay(
            celebration: .badge(BadgeCatalog.all[2]),
            onEquip: {},
            onDismiss: {}
        )
    }
}
