//
//  BadgeView.swift
//  Cinechill_iOS
//

import SwiftUI

/// Un badge, à n'importe quelle taille.
///
/// L'artwork est un PNG déjà composé — monture biseautée, champ émaillé,
/// scène illustrée — exporté depuis la planche de design plutôt que recomposé
/// à l'écran : quinze badges dessinés en direct avec dégradés angulaires,
/// filtres et animations multipliaient le coût de la vue à chaque frame,
/// c'est ce qui rendait la galerie et le profil lents à faire défiler.
struct BadgeView: View {
    let badge: Badge
    var isUnlocked: Bool = true
    var size: CGFloat = 104

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false

    var body: some View {
        Image(badge.imageName)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .saturation(isUnlocked ? 1 : 0)
            .brightness(isUnlocked ? 0 : -0.42)
            .shadow(color: haloColor, radius: breathing ? size * 0.16 : size * 0.1)
            .onAppear {
                guard isUnlocked, badge.rarity.breathes, !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                    breathing = true
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(badge.displayName(unlocked: isUnlocked))
            .accessibilityValue(isUnlocked ? "Obtenu" : "Verrouillé")
    }

    private var haloColor: Color {
        isUnlocked ? badge.rarity.halo : .clear
    }
}

#Preview {
    ScrollView {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 24) {
            ForEach(BadgeCatalog.all) { badge in
                VStack(spacing: 8) {
                    BadgeView(badge: badge, isUnlocked: true, size: 104)
                    Text(badge.name)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                }
            }
        }
        .padding()
    }
    .background(Color(.systemBackground))
}
