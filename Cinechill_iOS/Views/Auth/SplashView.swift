//
//  SplashView.swift
//  Cinechill_iOS
//

import SwiftUI

/// Écran affiché le temps que Firebase Auth détermine l'état de connexion au lancement —
/// remplace un `ProgressView` nu par quelque chose qui porte l'identité de l'app. Ce n'est
/// pas le launch screen natif (statique, généré par Xcode) : celui-ci prend le relais dès que
/// SwiftUI démarre, pendant la brève fenêtre où on ne sait pas encore si on va vers le login
/// ou l'app.
struct SplashView: View {
    @State private var badgePulse = false
    @State private var glowPulse = false

    var body: some View {
        ZStack {
            backgroundLayer

            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [.indigo.opacity(0.45), .clear],
                                center: .center, startRadius: 4, endRadius: 100
                            )
                        )
                        .frame(width: 200, height: 200)
                        .scaleEffect(glowPulse ? 1.15 : 0.88)

                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .fill(
                            LinearGradient(colors: [.indigo, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 104, height: 104)
                        .shadow(color: .indigo.opacity(0.45), radius: 26, y: 14)

                    Image(systemName: "popcorn.fill")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .scaleEffect(badgePulse ? 1.05 : 1)

                Text("Cinechill")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                LoadingDotsView()
                    .padding(.top, 4)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                badgePulse = true
                glowPulse = true
            }
        }
    }

    private var backgroundLayer: some View {
        ZStack {
            Color(red: 0.05, green: 0.05, blue: 0.09)
            RadialGradient(
                colors: [.indigo.opacity(0.28), .clear],
                center: UnitPoint(x: 0.5, y: 0.32), startRadius: 10, endRadius: 420
            )
        }
        .ignoresSafeArea()
    }
}

/// Trois points qui pulsent en cascade — signal d'activité minimal, cohérent avec le reste
/// des états de chargement de l'app plutôt qu'un `ProgressView` générique.
private struct LoadingDotsView: View {
    @State private var animate = false

    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(.white.opacity(0.75))
                    .frame(width: 7, height: 7)
                    .scaleEffect(animate ? 1 : 0.4)
                    .opacity(animate ? 1 : 0.4)
                    .animation(
                        .easeInOut(duration: 0.6).repeatForever(autoreverses: true).delay(Double(index) * 0.15),
                        value: animate
                    )
            }
        }
        .onAppear { animate = true }
    }
}

#Preview {
    SplashView()
}
