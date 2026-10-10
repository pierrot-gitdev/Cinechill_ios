//
//  SwipeMilestoneOverlay.swift
//  Cinechill_iOS
//

import SwiftUI

/// La célébration d'un palier — le seul moment où la feature se met en avant.
///
/// Elle n'a plus de carte : un chiffre en graisse 200, une ligne, et le voile de
/// la nuit. Le dégradé indigo→rose sur un nombre de 64 pt était l'effet le plus
/// appuyé de l'application, et il ne disait rien que le chiffre ne disait déjà.
struct SwipeMilestoneOverlay: View {
    let count: Int
    var isSeries = false

    var body: some View {
        VStack(spacing: 0) {
            Text(verbatim: "\(count)")
                .planTitle(64)
                .monospacedDigit()
                .foregroundStyle(Ink.ink)

            // Le palier compte ce qu'on classe : des séries en mode Séries.
            Text(isSeries ? String(localized: "séries ajoutées", bundle: .app)
                          : String(localized: "films ajoutés", bundle: .app))
                .planLabel()
                .foregroundStyle(Ink.light)
                .padding(.top, 10)

            Text("Chaque ajout compte dans tes suggestions.", bundle: .app)
                .planFont(13)
                .foregroundStyle(Ink.ink2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 16)
        }
        .padding(.horizontal, 34)
        .padding(.vertical, 32)
        .frame(maxWidth: 300)
        .background(
            Ink.ground.opacity(0.94),
            in: RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                .strokeBorder(Ink.ruleSet, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Self.spokenText(count: count, isSeries: isSeries))
    }

    static func spokenText(count: Int, isSeries: Bool) -> String {
        isSeries
            ? String(localized: "\(count) séries ajoutées à ta galerie", bundle: .app)
            : String(localized: "\(count) films ajoutés à ta galerie", bundle: .app)
    }
}

/// Le palier tant que CinéMatch est fermé : la galerie entière, rapportée aux
/// films qui l'ouvrent.
///
/// « 50 films ajoutés » comptait la session et ne disait pas à quoi servait le
/// compte. Le chiffre est maintenant celui de la galerie, posé sur sa cible,
/// et la phrase dit ce qu'il reste et ce que ça ouvre.
struct SwipeGoalMilestoneOverlay: View {
    let count: Int
    let target: Int
    var isSeries = false

    private var fraction: Double { target > 0 ? min(1, Double(count) / Double(target)) : 0 }

    var body: some View {
        VStack(spacing: 0) {
            Text(verbatim: "CinéMatch")
                .planLabel()
                .foregroundStyle(Ink.light)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: "\(count)")
                    .planTitle(64)
                    .monospacedDigit()
                    .foregroundStyle(Ink.ink)
                Text(String(localized: "sur \(target)", bundle: .app))
                    .planTitle(22)
                    .monospacedDigit()
                    .foregroundStyle(Ink.ink3)
            }
            .padding(.top, 12)

            Text(isSeries ? String(localized: "séries vues", bundle: .app)
                          : String(localized: "films vus", bundle: .app))
                .planLabel()
                .foregroundStyle(Ink.ink2)
                .padding(.top, 8)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Ink.rule)
                    Rectangle()
                        .fill(Color(hex: DoorArtifactKey.memoire.hue))
                        .frame(width: proxy.size.width * fraction)
                }
            }
            .frame(height: 3)
            .padding(.top, 20)

            HStack {
                Text(verbatim: "0")
                Spacer(minLength: 0)
                Text(verbatim: "\(target)")
            }
            .planFont(12)
            .monospacedDigit()
            .foregroundStyle(Ink.ink3)
            .padding(.top, 6)

            Text(Self.message(count: count, target: target, isSeries: isSeries))
                .planFont(13.5)
                .foregroundStyle(Ink.ink2)
                .lineSpacing(2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 30)
        .frame(maxWidth: 300)
        .background(Ink.ground, in: RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                .strokeBorder(Ink.ruleSet, lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.spokenText(count: count, target: target, isSeries: isSeries))
    }

    static func message(count: Int, target: Int, isSeries: Bool) -> String {
        let left = max(0, target - count)
        if isSeries {
            return left == 1
                ? String(localized: "Encore 1 série et CinéMatch des séries s'ouvre.", bundle: .app)
                : String(localized: "Encore \(left) séries et CinéMatch des séries s'ouvre.", bundle: .app)
        }
        return left == 1
            ? String(localized: "Encore 1 film et CinéMatch s'ouvre. Il te proposera le film de ce soir, d'après tes goûts.", bundle: .app)
            : String(localized: "Encore \(left) films et CinéMatch s'ouvre. Il te proposera le film de ce soir, d'après tes goûts.", bundle: .app)
    }

    static func spokenText(count: Int, target: Int, isSeries: Bool) -> String {
        let total = isSeries
            ? String(localized: "\(count) séries vues sur \(target).", bundle: .app)
            : String(localized: "\(count) films vus sur \(target).", bundle: .app)
        return total + " " + message(count: count, target: target, isSeries: isSeries)
    }

    /// Les paliers d'une cible : le quart, la moitié, les trois quarts et le
    /// dernier dixième. Proportionnels, pour que la Porte des séries (15) en
    /// ait autant que celle des films (100).
    static func steps(for target: Int) -> [Int] {
        let raw = [0.25, 0.5, 0.75, 0.9].map { Int((Double(target) * $0).rounded()) }
        var seen = Set<Int>()
        return raw.filter { $0 > 0 && $0 < target && seen.insert($0).inserted }
    }
}

#Preview {
    ZStack {
        Ink.ground.ignoresSafeArea()
        SwipeMilestoneOverlay(count: 25)
    }
}
