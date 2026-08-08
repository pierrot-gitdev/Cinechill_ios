//
//  TasteSheetView.swift
//  Cinechill_iOS
//

import SwiftUI

/// Vos goûts : ce que l'application a compris de vous, en toutes lettres.
///
/// Un système qui apprend de quelqu'un sans jamais montrer ce qu'il en a conclu
/// devient une boîte noire — et une boîte noire qui se trompe est insupportable.
/// Cet écran est le contrat inverse : chaque critère est affiché en français,
/// avec ce qu'on ignore encore, et se corrige d'un geste. Une correction pèse
/// plus lourd que tout ce qu'on a pu déduire.
///
/// Le titre disait « Votre fiche », ce qui ne désignait rien de reconnaissable —
/// personne n'a de « fiche » chez soi. On nomme maintenant le contenu, pas le
/// contenant.
///
/// Ce qu'elle ne fait pas : aucun score de complétion, aucun « profil à 73 % »,
/// aucun badge de cinéphile accompli. La connaissance se manifeste par la brièveté
/// des séances et la justesse des trios, pas par une jauge qui transforme le goût
/// en devoir à finir.
struct TasteSheetView: View {
    let profile: TasteProfile
    /// Renvoie la correction au serveur. `nil` retire la correction.
    let onCorrect: (Axis, Double?) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var drafts: [Axis: Double] = [:]
    @State private var savingAxis: Axis?

    var body: some View {
        NavigationStack {
            ZStack {
                Ink.ground.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        header

                        ForEach(Axis.allCases, id: \.self) { axis in
                            PlanEdge()
                            axisRow(axis)
                                .padding(.vertical, 18)
                        }

                        PlanEdge()
                        footer
                    }
                    .padding(.horizontal, Metrics.margin)
                    .padding(.bottom, Metrics.margin)
                }
            }
            .navigationBarHidden(true)
            .safeAreaInset(edge: .top) { closeBar }
        }
    }

    // MARK: - Chrome

    private var closeBar: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Vos goûts")
                    .planLabel()
                    .foregroundStyle(Ink.ink2)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Ink.ink2)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Fermer")
            }
            .padding(.horizontal, Metrics.margin - 8)
            .padding(.top, 8)
            .padding(.bottom, 10)

            PlanRail()
        }
        .background(Ink.ground)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ce qu'on a compris de vos goûts")
                .planTitle(24)
                .foregroundStyle(Ink.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text(provenanceLine)
                .font(.system(size: 12.5))
                .foregroundStyle(Ink.ink2)
                .lineSpacing(1)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 24)
        .padding(.bottom, 22)
    }

    /// D'où viennent ces conclusions, et ce qu'on peut en faire. Deux questions
    /// qu'un écran de profil doit répondre avant toute autre chose.
    private var provenanceLine: String {
        guard !profile.isEmpty else {
            return "On ne sait encore rien de vous. À chaque film que vous marquez comme vu et à chaque recherche, cette page se remplit — et il y a de moins en moins de questions à vous poser."
        }
        var parts: [String] = []
        if profile.galleryCount > 0 {
            parts.append("\(profile.galleryCount) film\(profile.galleryCount > 1 ? "s" : "") que vous avez vu\(profile.galleryCount > 1 ? "s" : "")")
        }
        if profile.watchlistCount > 0 {
            parts.append("\(profile.watchlistCount) film\(profile.watchlistCount > 1 ? "s" : "") de votre liste à voir")
        }
        let sources = parts.joined(separator: " et ")
        return "Ces conclusions viennent de \(sources), et de vos réponses. Si l'une d'elles est fausse, déplacez le curseur : c'est vous qui aurez raison."
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            let open = Axis.allCases.filter { profile.evidence($0) <= 0.5 }
            if !open.isEmpty {
                Text(openLine(open))
                    .font(.system(size: 12))
                    .foregroundStyle(Ink.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 18)
    }

    /// On dit ce qu'on ignore encore. C'est ce qui rend crédible le reste de la page.
    private func openLine(_ axes: [Axis]) -> String {
        let names = axes.map { $0.label.lowercased() }
        if names.count == Axis.allCases.count {
            return "Tout reste à découvrir. Quelques recherches suffiront."
        }
        let list = names.count <= 3
            ? names.formatted(.list(type: .and))
            : "\(names.prefix(3).formatted(.list(type: .and))) et d'autres"
        return "On ne sait pas encore grand-chose sur : \(list). Ça viendra."
    }

    // MARK: - Une ligne d'axe

    private func axisRow(_ axis: Axis) -> some View {
        let value = drafts[axis] ?? profile.mean(axis)
        let known = profile.evidence(axis) > 0.5
        let corrected = profile.correctedAxes.contains(axis)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(axis.label)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Ink.ink)

                if corrected { PlanLight() }

                Spacer(minLength: 12)

                if savingAxis == axis {
                    CinechillSpinner(size: 12)
                } else if corrected {
                    Text("modifié par vous")
                        .planLabel()
                        .foregroundStyle(Ink.light)
                }
            }

            Text(Self.phrase(for: axis, value: value, known: known))
                .font(.system(size: 12.5))
                .foregroundStyle(known ? Ink.ink2 : Ink.ink3)
                .fixedSize(horizontal: false, vertical: true)

            Slider(
                value: Binding(
                    get: { drafts[axis] ?? profile.mean(axis) },
                    set: { drafts[axis] = $0 }
                ),
                in: -1...1,
                onEditingChanged: { editing in
                    guard !editing, let draft = drafts[axis] else { return }
                    Task {
                        savingAxis = axis
                        await onCorrect(axis, draft)
                        savingAxis = nil
                    }
                }
            )
            .tint(Ink.ink)
            .accessibilityLabel(axis.label)
            .accessibilityValue(Self.phrase(for: axis, value: value, known: known))

            HStack {
                Text(Self.poles(for: axis).0)
                Spacer(minLength: 12)
                Text(Self.poles(for: axis).1)
            }
            .planLabel()
            .foregroundStyle(Ink.ink3)
        }
    }

    // MARK: - Les mots

    private static func poles(for axis: Axis) -> (String, String) {
        switch axis {
        case .charge: ("léger", "bouleversant")
        case .rythme: ("calme", "nerveux")
        case .familiarite: ("films connus", "films rares")
        case .densite: ("facile à suivre", "exigeant")
        case .ancrage: ("réaliste", "imaginaire")
        case .ton: ("sombre", "chaleureux")
        case .echelle: ("histoires intimes", "grand spectacle")
        case .investissement: ("films courts", "films longs")
        }
    }

    /// La position dite comme on la dirait à quelqu'un, jamais en chiffres. Une
    /// phrase entière plutôt qu'un adjectif : « Plutôt limpide » ne dit pas au
    /// lecteur si c'est une observation sur lui ou une consigne donnée à l'app.
    private static func phrase(for axis: Axis, value: Double, known: Bool) -> String {
        guard known else { return "Pas encore assez d'éléments pour le dire." }
        let strong = abs(value) > 0.45
        switch axis {
        case .charge:
            return value > 0
                ? (strong ? "Vous aimez les films qui remuent." : "Un peu d'émotion forte ne vous gêne pas.")
                : (strong ? "Vous préférez les films qui restent légers." : "Plutôt des films légers.")
        case .rythme:
            return value > 0
                ? (strong ? "Il vous faut des films où ça avance vite." : "Vous aimez que ça ne traîne pas.")
                : (strong ? "Vous aimez les films qui prennent leur temps." : "Plutôt des films calmes.")
        case .familiarite:
            return value > 0
                ? (strong ? "Vous aimez découvrir des films dont personne ne parle." : "Vous êtes curieux·se, sans chercher l'obscur.")
                : (strong ? "Vous préférez les films dont vous avez déjà entendu parler." : "Plutôt des films connus.")
        case .densite:
            return value > 0
                ? (strong ? "Vous aimez les films qui demandent de l'attention." : "Un film un peu exigeant ne vous fait pas peur.")
                : (strong ? "Vous voulez des films qui se laissent suivre facilement." : "Plutôt des films faciles à suivre.")
        case .ancrage:
            return value > 0
                ? (strong ? "Vous aimez qu'un film vous emmène dans un autre monde." : "Un peu d'imaginaire vous va bien.")
                : (strong ? "Vous préférez les histoires qui pourraient être vraies." : "Plutôt des histoires réalistes.")
        case .ton:
            return value > 0
                ? (strong ? "Vous aimez les films qui font du bien." : "Plutôt des films bienveillants.")
                : (strong ? "Les films sombres ne vous dérangent pas." : "Plutôt des films sans complaisance.")
        case .echelle:
            return value > 0
                ? (strong ? "Le grand spectacle vous parle." : "Vous aimez qu'il y ait de l'ampleur.")
                : (strong ? "Ce sont les histoires de quelques personnes qui vous touchent." : "Plutôt des histoires à taille humaine.")
        case .investissement:
            return value > 0
                ? (strong ? "Un film de plus de deux heures ne vous fait pas peur." : "Vous acceptez volontiers les films longs.")
                : (strong ? "Vous préférez que ça tienne en une heure et demie." : "Plutôt des films courts.")
        }
    }
}

#Preview("Vos goûts") {
    TasteSheetView(
        profile: TasteProfile(
            mu: [.charge: 0.62, .rythme: -0.38, .familiarite: 0.55, .densite: 0.61,
                 .ancrage: -0.44, .ton: 0.05],
            tau: [.charge: 4.2, .rythme: 3.1, .familiarite: 3.8, .densite: 3.4,
                  .ancrage: 2.9, .ton: 1.2],
            galleryCount: 42,
            watchlistCount: 7,
            correctedAxes: [.charge]
        ),
        onCorrect: { _, _ in }
    )
}
