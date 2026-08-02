//
//  GradientSpinner.swift
//  Cinechill_iOS
//

import SwiftUI

/// Anneau en rotation continue avec une traîne dégradée, utilisé comme indicateur de
/// chargement partout où un `ProgressView` nu tranchait avec le reste du design (boutons en
/// pilule dégradée, cartes…).
struct GradientSpinner: View {
    var size: CGFloat = 20
    var lineWidth: CGFloat = 2.5
    var colors: [Color] = [.white, .white.opacity(0.05)]

    @State private var rotation: Double = 0

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.75)
            .stroke(
                AngularGradient(colors: colors, center: .center),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
            .frame(width: size, height: size)
            .rotationEffect(.degrees(rotation))
            .onAppear {
                withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
}

#Preview {
    GradientSpinner(size: 32, lineWidth: 3, colors: [.indigo, .pink.opacity(0.1)])
}
