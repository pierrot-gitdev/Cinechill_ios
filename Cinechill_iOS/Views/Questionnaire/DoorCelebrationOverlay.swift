//
//  DoorCelebrationOverlay.swift
//  Cinechill_iOS
//

import SwiftUI

/// L'annonce d'un artéfact gagné, où que l'on soit dans l'application.
///
/// Elle ne ressemble pas à la célébration d'un badge, et c'est voulu : un badge
/// se contemple seul, un artéfact ne vaut que **par rapport aux trois autres**.
/// La planche montre donc la rangée entière — ce qui est acquis, ce qui reste,
/// et lequel vient de s'allumer, seul à s'animer. On lit sa progression, pas
/// une récompense isolée.
///
/// Elle nomme CinéMatch en tête et dit ce qu'il reste à faire pour l'ouvrir :
/// gagnée depuis Découvrir ou la galerie, une étape ne disait pas à quoi elle
/// servait, et on fêtait un médaillon sans savoir qu'il ouvrait CinéMatch.
struct DoorCelebrationOverlay: View {
    let door: DoorState
    /// L'artéfact qui vient d'être gagné. Il part éteint et s'allume sous les
    /// yeux : c'est le seul mouvement de la planche.
    let unlocked: DoorArtifactKey
    let onDismiss: () -> Void
    /// « Ouvrir CinéMatch », une fois la dernière étape gagnée.
    let onShowDoor: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false

    private var series: Bool { door.series }
    private var left: Int { max(0, door.stepCount - door.litCount) }
    private var isUnlocked: Bool { left == 0 }

    var body: some View {
        ZStack {
            Ink.ground.opacity(0.88)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Text(verbatim: "CinéMatch")
                    .planLabel()
                    .foregroundStyle(Ink.ink)

                Text(eyebrow)
                    .planLabel()
                    .foregroundStyle(Color(hex: unlocked.hue))
                    .multilineTextAlignment(.center)
                    .padding(.top, 6)

                row
                    .padding(.top, 20)

                Text(title)
                    .planTitle(24)
                    .foregroundStyle(Ink.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 22)

                gauge
                    .padding(.top, 18)

                Text(countText)
                    .planLabel()
                    .monospacedDigit()
                    .foregroundStyle(Ink.ink2)
                    .padding(.top, 10)

                Text(message)
                    .planFont(13.5)
                    .foregroundStyle(Ink.ink2)
                    .lineSpacing(2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)

                actions
                    .padding(.top, 20)
            }
            .padding(24)
            .frame(maxWidth: 340)
            .background(Ink.ground)
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                    .strokeBorder(Color(hex: unlocked.hue).opacity(0.45), lineWidth: 1)
            )
            .padding(.horizontal, Metrics.margin)
            .planScrollsIfNeeded()
        }
        .task {
            Haptics.success()
            // Le passage de la pierre à l'or est l'objet de la planche : il se
            // joue aussi en mouvement réduit, en fondu, sans l'agrandissement.
            // Allumé d'office, on ne voyait plus lequel venait de s'allumer.
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 250 : 420))
            guard !Task.isCancelled else { return }
            // Un ressort qui se pose sans rebondir trois fois : la planche est
            // rare, elle peut marquer le coup, pas sautiller.
            withAnimation(reduceMotion ? Animation.easeOut(duration: 0.3) : .spring(response: 0.5, dampingFraction: 0.7)) {
                revealed = true
            }
        }
        .accessibilityElement(children: .contain)
        // Modale : VoiceOver ne doit pas sortir vers l'onglet du dessous.
        .accessibilityAddTraits(.isModal)
    }

    // MARK: - Les mots

    private var eyebrow: String {
        String(localized: "Étape validée", bundle: .app)
    }

    private var title: String {
        if isUnlocked {
            return series
                ? String(localized: "CinéMatch des séries est débloqué", bundle: .app)
                : String(localized: "CinéMatch est débloqué", bundle: .app)
        }
        return String(localized: "\(unlocked.displayName(series: series)) : c'est fait.", bundle: .app)
    }

    private var countText: String {
        door.litCount <= 1
            ? String(localized: "\(door.litCount) étape sur \(door.stepCount)", bundle: .app)
            : String(localized: "\(door.litCount) étapes sur \(door.stepCount)", bundle: .app)
    }

    /// Ce que la planche dit en clair : ce qu'il reste, et ce que CinéMatch
    /// fera une fois ouvert. Une conséquence, jamais le mécanisme.
    private var message: String {
        if isUnlocked {
            return series
                ? String(localized: "Il te propose une série à commencer, d'après tes goûts.", bundle: .app)
                : String(localized: "Il te propose le film de ce soir, d'après tes goûts.", bundle: .app)
        }
        if left == 1, let missing = door.keys.first(where: { door.artifact($0)?.done != true }) {
            return String(localized: "Plus qu'une étape avant que CinéMatch s'ouvre : \(missing.displayName(series: series)).", bundle: .app)
        }
        return series
            ? String(localized: "Plus que \(left) étapes avant que CinéMatch s'ouvre. Il te proposera alors une série à commencer, d'après tes goûts.", bundle: .app)
            : String(localized: "Plus que \(left) étapes avant que CinéMatch s'ouvre. Il te proposera alors le film de ce soir, d'après tes goûts.", bundle: .app)
    }

    // MARK: - Les actions

    @ViewBuilder
    private var actions: some View {
        if isUnlocked {
            PlanButton(title: String(localized: "Ouvrir CinéMatch", bundle: .app), action: onShowDoor)
            textButton(String(localized: "Plus tard", bundle: .app), action: onDismiss)
        } else {
            // Une seule issue : la rangée dit déjà ce qu'il reste, et « Voir ce
            // qu'il reste » emmenait vers la Porte en coupant ce qu'on faisait.
            // Seule, l'action prend l'aplat de l'action principale.
            PlanButton(title: String(localized: "Continuer", bundle: .app), action: onDismiss)
        }
    }

    private func textButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .planFont(13.5, weight: .medium)
                .foregroundStyle(Ink.ink2)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableScaleStyle())
        .padding(.top, 6)
    }

    // MARK: - La rangée

    /// Les trois artéfacts, à leur place et nommés. Les acquis sont pleins, les
    /// autres en pierre — la même grammaire que sur la porte, pour qu'on
    /// reconnaisse l'objet sans avoir à l'apprendre deux fois. Les noms disent
    /// ce qui reste sans qu'on ait à toucher la porte.
    private var row: some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(door.keys, id: \.self) { key in
                VStack(spacing: 7) {
                    artifact(key)
                    Text(key.displayName(series: series))
                        .planFont(10.5)
                        .foregroundStyle(key == unlocked ? Ink.ink : Ink.ink2)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                        .fixedSize(horizontal: false, vertical: true)
                        // Quatre colonnes de 66 pt : passé xxxLarge, « Coups de
                        // cœur » se coupe au milieu d'un mot. Le compte et le
                        // message en dessous disent la même chose en grand.
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(key.displayName(series: series))
                .accessibilityValue(door.artifact(key)?.done == true
                    ? String(localized: "validée", bundle: .app)
                    : String(localized: "à faire", bundle: .app))
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
            .scaleEffect(isNew && revealed && !reduceMotion ? 1.14 : 1)
            .accessibilityHidden(true)
    }

    // MARK: - La jauge

    private var gauge: some View {
        HStack(spacing: 6) {
            ForEach(door.keys, id: \.self) { key in
                let lit = (door.artifact(key)?.done == true) && (key != unlocked || revealed)
                Rectangle()
                    .fill(lit ? Color(hex: key.hue) : Ink.rule)
                    .frame(height: 3)
            }
        }
        .accessibilityHidden(true)
    }
}
