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
///
/// Elle nomme CinéMatch en tête et dit ce qu'il reste à faire pour l'ouvrir :
/// gagnée depuis Découvrir ou la galerie, une étape ne disait pas à quoi elle
/// servait, et on fêtait un médaillon sans savoir qu'il ouvrait CinéMatch.
///
/// Quand les quatre premières étapes sont faites, la planche change de rôle :
/// il ne reste que les comparaisons, et elle les propose tout de suite.
struct DoorCelebrationOverlay: View {
    let door: DoorState
    /// L'artéfact qui vient d'être gagné. Il part éteint et s'allume sous les
    /// yeux : c'est le seul mouvement de la planche.
    let unlocked: DoorArtifactKey
    let onDismiss: () -> Void
    /// « Voir ce qu'il reste » : la Porte, dans l'onglet CinéMatch.
    let onShowDoor: () -> Void
    /// « Comparer mes films » : les comparaisons, ouvertes directement.
    let onCompare: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false

    private var series: Bool { door.series }
    private var left: Int { max(0, 5 - door.litCount) }
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
                    .strokeBorder(Color(hex: borderHue).opacity(0.45), lineWidth: 1)
            )
            .padding(.horizontal, Metrics.margin)
            .planScrollsIfNeeded()
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
        // Modale : VoiceOver ne doit pas sortir vers l'onglet du dessous.
        .accessibilityAddTraits(.isModal)
    }

    // MARK: - Les mots

    /// Le cadre de la dernière étape prend la teinte des préférences : c'est
    /// elle que la planche propose.
    private var borderHue: UInt {
        door.onlyComparisonLeft ? DoorArtifactKey.horizons.hue : unlocked.hue
    }

    private var eyebrow: String {
        guard door.onlyComparisonLeft else { return String(localized: "Étape validée", bundle: .app) }
        return String(localized: "\(unlocked.displayName(series: series)) : étape validée", bundle: .app)
    }

    private var title: String {
        if door.onlyComparisonLeft { return String(localized: "Plus qu'une étape", bundle: .app) }
        if isUnlocked {
            return series
                ? String(localized: "CinéMatch des séries est débloqué", bundle: .app)
                : String(localized: "CinéMatch est débloqué", bundle: .app)
        }
        return String(localized: "\(unlocked.displayName(series: series)) : c'est fait.", bundle: .app)
    }

    private var countText: String {
        door.litCount <= 1
            ? String(localized: "\(door.litCount) étape sur 5", bundle: .app)
            : String(localized: "\(door.litCount) étapes sur 5", bundle: .app)
    }

    /// Ce que la planche dit en clair : ce qu'il reste, et ce que CinéMatch
    /// fera une fois ouvert. Une conséquence, jamais le mécanisme.
    private var message: String {
        if door.onlyComparisonLeft {
            let rounds = door.artifact(.horizons)?.target ?? (series ? 6 : 12)
            return series
                ? String(localized: "Compare des séries que tu as vues, \(rounds) fois. Ça prend deux minutes, et CinéMatch des séries s'ouvre juste après.", bundle: .app)
                : String(localized: "Compare des films que tu as vus, \(rounds) fois. Ça prend deux minutes, et CinéMatch s'ouvre juste après.", bundle: .app)
        }
        if isUnlocked {
            return series
                ? String(localized: "Il te propose une série à commencer, d'après tes goûts.", bundle: .app)
                : String(localized: "Il te propose le film de ce soir, d'après tes goûts.", bundle: .app)
        }
        if left == 1, let missing = DoorArtifactKey.allCases.first(where: { door.artifact($0)?.done != true }) {
            return String(localized: "Plus qu'une étape avant que CinéMatch s'ouvre : \(missing.displayName(series: series)).", bundle: .app)
        }
        return series
            ? String(localized: "Plus que \(left) étapes avant que CinéMatch s'ouvre. Il te proposera alors une série à commencer, d'après tes goûts.", bundle: .app)
            : String(localized: "Plus que \(left) étapes avant que CinéMatch s'ouvre. Il te proposera alors le film de ce soir, d'après tes goûts.", bundle: .app)
    }

    // MARK: - Les actions

    @ViewBuilder
    private var actions: some View {
        if door.onlyComparisonLeft {
            PlanButton(
                title: series
                    ? String(localized: "Comparer mes séries", bundle: .app)
                    : String(localized: "Comparer mes films", bundle: .app),
                action: onCompare
            )
            textButton(String(localized: "Plus tard", bundle: .app), action: onDismiss)
        } else if isUnlocked {
            PlanButton(title: String(localized: "Ouvrir CinéMatch", bundle: .app), action: onShowDoor)
            textButton(String(localized: "Plus tard", bundle: .app), action: onDismiss)
        } else {
            Button(action: onDismiss) {
                Text("Continuer", bundle: .app)
                    .planFont(15, weight: .semibold)
                    .foregroundStyle(Ink.ink)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: Metrics.buttonSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                            .strokeBorder(Ink.ruleSet, lineWidth: 1)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableScaleStyle(scale: 0.97))
            textButton(String(localized: "Voir ce qu'il reste", bundle: .app), action: onShowDoor)
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
        .buttonStyle(.plain)
        .padding(.top, 6)
    }

    // MARK: - La rangée

    /// Les cinq artéfacts, à leur place et nommés. Les acquis sont pleins, les
    /// autres en pierre — la même grammaire que sur la porte, pour qu'on
    /// reconnaisse l'objet sans avoir à l'apprendre deux fois. Les noms disent
    /// ce qui reste sans qu'on ait à toucher la porte.
    private var row: some View {
        HStack(alignment: .top, spacing: 4) {
            ForEach(DoorArtifactKey.allCases, id: \.self) { key in
                VStack(spacing: 7) {
                    artifact(key)
                    Text(key.displayName(series: series))
                        .planFont(10.5)
                        .foregroundStyle(key == unlocked ? Ink.ink : Ink.ink2)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                        .fixedSize(horizontal: false, vertical: true)
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
        // Les préférences, tant que les quatre autres manquent : verrouillées.
        let isLocked = key == .horizons && !door.canCompare && !lit
        // Les préférences proposées : le point de lumière, « à faire ».
        let isNext = key == .horizons && door.onlyComparisonLeft

        return Image(key.assetName)
            .resizable()
            .scaledToFit()
            .frame(width: 42, height: 42)
            .saturation(lit ? 1 : 0)
            .brightness(lit ? 0 : -0.42)
            .shadow(
                color: Color(hex: key.halo).opacity(lit ? (isNew ? 0.6 : 0.35) : 0),
                radius: isNew && revealed ? 14 : 8
            )
            .scaleEffect(isNew && revealed ? 1.14 : 1)
            .overlay {
                if isLocked {
                    DoorLockGlyph()
                        .stroke(Ink.ink2, style: StrokeStyle(lineWidth: 1.2, lineJoin: .round))
                        .frame(width: 11, height: 13)
                }
            }
            .overlay(alignment: .topTrailing) {
                if isNext { PlanLight() }
            }
            .accessibilityHidden(true)
    }

    // MARK: - La jauge

    private var gauge: some View {
        HStack(spacing: 6) {
            ForEach(DoorArtifactKey.allCases, id: \.self) { key in
                let lit = (door.artifact(key)?.done == true) && (key != unlocked || revealed)
                Rectangle()
                    .fill(lit ? Color(hex: key.hue) : Ink.rule)
                    .frame(height: 3)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Le cadenas d'une étape qui attend les autres : un anneau, un corps.
struct DoorLockGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let bodyTop = rect.minY + rect.height * 0.45
        path.addRoundedRect(
            in: CGRect(x: rect.minX, y: bodyTop, width: rect.width, height: rect.maxY - bodyTop),
            cornerSize: CGSize(width: 1.5, height: 1.5)
        )
        let inset = rect.width * 0.22
        path.move(to: CGPoint(x: rect.minX + inset, y: bodyTop))
        path.addLine(to: CGPoint(x: rect.minX + inset, y: rect.minY + rect.width * 0.3))
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.minY + rect.width * 0.3),
            radius: rect.width / 2 - inset,
            startAngle: .degrees(180),
            endAngle: .degrees(0),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.maxX - inset, y: bodyTop))
        return path
    }
}
