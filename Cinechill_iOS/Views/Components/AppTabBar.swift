//
//  AppTabBar.swift
//  Cinechill_iOS
//

import SwiftUI

/// La barre d'onglets de l'app.
///
/// Remplace la barre native pour une seule raison : le bouton central du deck
/// de swipe doit être surélevé et mis en avant, ce que `tabItem` ne permet pas.
/// Les cinq destinations gardent les mêmes tags que la `TabView` sous-jacente,
/// qui continue de porter l'état de chaque onglet.
struct AppTabBar: View {
    @Binding var selectedTab: Int

    private static let barHeight: CGFloat = 58
    /// Le bouton central tient entièrement dans la pilule : le faire déborder
    /// par le haut le détachait visuellement de la barre.
    private static let centerSize: CGFloat = 56

    var body: some View {
        HStack(spacing: 0) {
            tabButton(icon: "house.fill", label: "Accueil", tag: 0)
            tabButton(icon: "popcorn.fill", label: "CinéMatch", tag: 1)
            centerButton
            tabButton(icon: "trophy.fill", label: "Galerie", tag: 3)
            tabButton(icon: "bookmark.fill", label: "Watchlist", tag: 4)
        }
        .frame(height: Self.barHeight)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.07), lineWidth: 1))
        .shadow(color: .black.opacity(0.10), radius: 18, y: 6)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private func tabButton(icon: String, label: String, tag: Int) -> some View {
        Button {
            select(tag)
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .medium))
                Text(label)
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(selectedTab == tag ? AnyShapeStyle(selectedGradient) : AnyShapeStyle(Color.secondary))
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableScaleStyle(scale: 0.9))
        .accessibilityLabel(label)
        .accessibilityAddTraits(selectedTab == tag ? [.isSelected] : [])
    }

    private var centerButton: some View {
        Button {
            select(2)
        } label: {
            ZStack {
                Circle()
                    .fill(selectedGradient)
                Image(systemName: "rectangle.stack.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: Self.centerSize, height: Self.centerSize)
            .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
            .shadow(color: .indigo.opacity(selectedTab == 2 ? 0.45 : 0.28), radius: 10, y: 4)
            .scaleEffect(selectedTab == 2 ? 1.06 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: selectedTab)
        }
        .buttonStyle(PressableScaleStyle(scale: 0.92))
        .frame(maxWidth: .infinity)
        .offset(y: -8)
        .accessibilityLabel("Découvrir")
        .accessibilityAddTraits(selectedTab == 2 ? [.isSelected] : [])
    }

    private var selectedGradient: LinearGradient {
        LinearGradient(
            colors: [.indigo, .pink],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func select(_ tag: Int) {
        guard selectedTab != tag else { return }
        Haptics.selection()
        selectedTab = tag
    }
}

#Preview {
    VStack {
        Spacer()
        AppTabBar(selectedTab: .constant(2))
    }
    .background(Color(.systemBackground))
}
