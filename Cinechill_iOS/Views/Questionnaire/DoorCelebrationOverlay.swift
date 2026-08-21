//
//  DoorCelebrationOverlay.swift
//  Cinechill_iOS
//

import SwiftUI

/// L'annonce d'un artéfact gagné, où que l'on soit dans l'application.
///
/// Elle ne ressemble pas à la célébration d'un badge, et c'est voulu : un badge
/// se contemple seul, un artéfact ne vaut que **par rapport aux quatre autres**.
/// La planche montre donc la rangée entière — ce qui est acquis, ce qui reste,
/// et lequel vient de s'allumer, seul à s'animer. On lit sa progression, pas
/// une récompense isolée.
struct DoorCelebrationOverlay: View {
    let door: DoorState
    /// L'artéfact qui vient d'être gagné. Il part éteint et s'allume sous les
    /// yeux : c'est le seul mouvement de la planche.
    let unlocked: DoorArtifactKey
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false

    var body: some View {
        ZStack {
            Ink.ground.opacity(0.88)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Text("Artéfact gagné", bundle: .app)
                    .planLabel()
                    .foregroundStyle(Color(hex: unlocked.hue))

                row
                    .padding(.top, 22)

                Text("\(unlocked.displayName) s'allume.", bundle: .app)
                    .planTitle(24)
                    .foregroundStyle(Ink.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 22)

                Text(unlocked.consequence)
                    .font(.system(size: 13))
                    .foregroundStyle(Ink.ink2)
                    .lineSpacing(2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)

                gauge
                    .padding(.top, 20)

                Text(remainingText)
                    .planLabel()
                    .foregroundStyle(Ink.ink3)
                    .padding(.top, 10)

                Button(action: onDismiss) {
                    Text("Continuer", bundle: .app)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Ink.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: Metrics.buttonSecondary)
                        .overlay(
                            RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                                .strokeBorder(Ink.ruleSet, lineWidth: 1)
                        )
                }
                .buttonStyle(PressableScaleStyle(scale: 0.97))
                .padding(.top, 20)
            }
            .padding(26)
            .frame(width: 320)
            .background(Ink.ground)
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                    .strokeBorder(Color(hex: unlocked.hue).opacity(0.45), lineWidth: 1)
            )
        }
        .task {
            Haptics.success()
            guard !reduceMotion else {
                revealed = true
                return
            }
            try? await Task.sleep(for: .milliseconds(420))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.55, dampingFraction: 0.52)) {
                revealed = true
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "\(unlocked.displayName) s'allume. \(door.litCount) artéfacts sur 5.", bundle: .app))
    }

    // MARK: - La rangée

    /// Les cinq artéfacts, à leur place. Les acquis sont pleins, les autres en
    /// pierre — la même grammaire que sur la porte, pour qu'on reconnaisse
    /// l'objet sans avoir à l'apprendre deux fois.
    private var row: some View {
        HStack(spacing: 8) {
            ForEach(DoorArtifactKey.allCases, id: \.self) { key in
                artifact(key)
            }
        }
    }

    private func artifact(_ key: DoorArtifactKey) -> some View {
        let isNew = key == unlocked
        // Le nouveau part éteint quoi qu'en dise la porte : c'est son passage
        // de la pierre à l'or qui est l'objet de la planche.
        let lit = (door.artifact(key)?.done == true) && (!isNew || revealed)

        return Image(key.assetName)
            .resizable()
            .scaledToFit()
            .frame(width: 46, height: 46)
            .saturation(lit ? 1 : 0)
            .brightness(lit ? 0 : -0.42)
            .shadow(
                color: Color(hex: key.halo).opacity(lit ? (isNew ? 0.6 : 0.35) : 0),
                radius: isNew && revealed ? 14 : 8
            )
            .scaleEffect(isNew && revealed ? 1.16 : 1)
            .accessibilityHidden(true)
    }

    // MARK: - La jauge

    private var gauge: some View {
        HStack(spacing: 6) {
            ForEach(DoorArtifactKey.allCases, id: \.self) { key in
                let lit = (door.artifact(key)?.done == true) && (key != unlocked || revealed)
                Rectangle()
                    .fill(lit ? Color(hex: key.hue) : Color(hex: 0xC6D3DF).opacity(0.13))
                    .frame(height: 3)
            }
        }
        .accessibilityHidden(true)
    }

    private var remainingText: String {
        let left = max(0, 5 - door.litCount)
        if left == 0 {
            return String(localized: "La porte s'ouvre", bundle: .app)
        }
        return String(localized: "\(door.litCount) sur 5", bundle: .app)
    }
}
