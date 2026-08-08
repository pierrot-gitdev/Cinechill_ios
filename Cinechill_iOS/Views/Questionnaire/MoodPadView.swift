//
//  MoodPadView.swift
//  Cinechill_iOS
//

import SwiftUI

/// Le cadran : deux appuis, aucune étiquette à s'approprier.
///
/// Le premier pose où l'on est, le second où l'on veut finir ; le trait entre les
/// deux est la commande de la soirée. C'est la seule mesure du parcours qu'aucune
/// donnée ne peut remplacer — la Galerie dit ce qu'on aime, elle ne dit pas
/// comment on va ce soir.
///
/// Les deux repères se distinguent par leur **forme** — creux pour l'état actuel,
/// plein pour l'état visé — et non par une couleur : le carré de lumière garde
/// son sens unique ailleurs dans l'application, et l'écran reste lisible en
/// niveaux de gris.
struct MoodPadView: View {
    @Binding var now: MoodPoint?
    @Binding var goal: MoodPoint?

    /// Appelé à chaque repère posé, une fois le geste terminé.
    var onPlace: () -> Void = {}

    @State private var isAdjustingGoal = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let marker: CGFloat = 11

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size

            ZStack(alignment: .topLeading) {
                Rectangle()
                    .strokeBorder(Ink.ruleSet, lineWidth: 1)

                crosshair(in: size)
                edgeLabels(in: size)

                if let now {
                    if let goal {
                        vector(from: now, to: goal, in: size)
                    }
                    hollowMarker
                        .position(position(of: now, in: size))
                }

                if let goal {
                    filledMarker
                        .position(position(of: goal, in: size))
                }
            }
            .contentShape(Rectangle())
            .gesture(placementGesture(in: size))
            .animation(reduceMotion ? nil : Metrics.shift, value: now)
            .animation(reduceMotion ? nil : Metrics.shift, value: goal)
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Cadran d'humeur")
        .accessibilityValue(accessibilityReading)
        .accessibilityActions { accessibilityZones }
    }

    // MARK: - Le fond

    private func crosshair(in size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Ink.rule)
                .frame(width: size.width, height: 1)
                .offset(y: size.height / 2)
            Rectangle()
                .fill(Ink.rule)
                .frame(width: 1, height: size.height)
                .offset(x: size.width / 2)
        }
    }

    private func edgeLabels(in size: CGSize) -> some View {
        ZStack {
            label("activé").position(x: size.width / 2, y: 16)
            label("calme").position(x: size.width / 2, y: size.height - 16)
            label("pénible").rotationEffect(.degrees(-90)).position(x: 18, y: size.height / 2)
            label("agréable").rotationEffect(.degrees(90)).position(x: size.width - 18, y: size.height / 2)
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .planLabel()
            .foregroundStyle(Ink.ink3)
            .fixedSize()
    }

    // MARK: - Les repères

    private var hollowMarker: some View {
        Rectangle()
            .strokeBorder(Ink.ink2, lineWidth: 1.5)
            .frame(width: marker, height: marker)
    }

    private var filledMarker: some View {
        Rectangle()
            .fill(Ink.ink)
            .frame(width: marker, height: marker)
    }

    /// Le trajet, tracé sans pointe de flèche : c'est la position d'arrivée —
    /// pleine, donc acquise — qui dit le sens, pas un ornement.
    private func vector(from start: MoodPoint, to end: MoodPoint, in size: CGSize) -> some View {
        Path { path in
            path.move(to: position(of: start, in: size))
            path.addLine(to: position(of: end, in: size))
        }
        .stroke(Ink.ruleSet, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
    }

    // MARK: - Le geste

    private func placementGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let point = moodPoint(at: value.location, in: size)
                if now == nil {
                    now = point
                    isAdjustingGoal = false
                } else if isAdjustingGoal {
                    goal = point
                } else if goal == nil {
                    now = point
                } else {
                    // Les deux repères sont posés : un nouveau geste recommence
                    // le trajet plutôt que de déplacer un point au hasard.
                    now = point
                    goal = nil
                }
            }
            .onEnded { _ in
                // Le prochain geste pose l'arrivée, sauf si l'on vient de la poser.
                isAdjustingGoal = (now != nil && goal == nil)
                onPlace()
            }
    }

    // MARK: - Coordonnées

    private func position(of point: MoodPoint, in size: CGSize) -> CGPoint {
        CGPoint(
            x: (point.valence + 1) / 2 * size.width,
            y: (1 - point.activation) / 2 * size.height
        )
    }

    private func moodPoint(at location: CGPoint, in size: CGSize) -> MoodPoint {
        guard size.width > 0, size.height > 0 else { return .neutral }
        return MoodPoint(
            valence: location.x / size.width * 2 - 1,
            activation: 1 - location.y / size.height * 2
        )
    }

    // MARK: - Accessibilité

    /// Le cadran est un geste ; VoiceOver a besoin de mots. Cinq zones nommées
    /// suffisent à parcourir l'espace — c'est plus grossier que le doigt, mais
    /// c'est un vrai chemin, pas un pis-aller muet.
    private static let zones: [(String, MoodPoint)] = [
        ("Épuisé·e", MoodPoint(valence: -0.6, activation: -0.6)),
        ("Tendu·e", MoodPoint(valence: -0.6, activation: 0.6)),
        ("Neutre", .neutral),
        ("Posé·e", MoodPoint(valence: 0.6, activation: -0.6)),
        ("En forme", MoodPoint(valence: 0.6, activation: 0.6)),
    ]

    @ViewBuilder
    private var accessibilityZones: some View {
        ForEach(Self.zones, id: \.0) { name, point in
            Button(now == nil ? "Je suis \(name.lowercased())" : "Finir \(name.lowercased())") {
                if now == nil {
                    now = point
                } else {
                    goal = point
                }
                onPlace()
            }
        }
    }

    private var accessibilityReading: String {
        guard let now else { return "Aucun repère posé. Indiquez d'abord où vous en êtes." }
        guard let goal else { return "Départ : \(Self.describe(now)). Indiquez où vous voulez finir." }
        return "Départ : \(Self.describe(now)). Arrivée : \(Self.describe(goal))."
    }

    private static func describe(_ point: MoodPoint) -> String {
        let valence = point.valence < -0.3 ? "pénible" : (point.valence > 0.3 ? "agréable" : "neutre")
        let activation = point.activation < -0.3 ? "calme" : (point.activation > 0.3 ? "activé" : "moyen")
        return "\(valence), \(activation)"
    }
}

#Preview("Cadran") {
    struct Harness: View {
        @State private var now: MoodPoint? = MoodPoint(valence: -0.55, activation: -0.45)
        @State private var goal: MoodPoint? = MoodPoint(valence: 0.5, activation: -0.15)

        var body: some View {
            ZStack {
                Ink.ground.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 18) {
                    Text("Et quand le générique tombera ?")
                        .planTitle()
                        .foregroundStyle(Ink.ink)
                    MoodPadView(now: $now, goal: $goal)
                    if let now, let goal {
                        Text(MoodStrategy.from(MoodTrajectory(now: now, goal: goal)).reading)
                            .font(.system(size: 13))
                            .foregroundStyle(Ink.ink2)
                    }
                }
                .padding(Metrics.margin)
            }
        }
    }
    return Harness()
}
