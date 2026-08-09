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
                Text("Vos goûts", bundle: .app)
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
                .accessibilityLabel(String(localized: "Fermer", bundle: .app))
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
            Text("Ce qu'on a compris de vos goûts", bundle: .app)
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
            return String(localized: "On ne sait encore rien de vous. À chaque film que vous marquez comme vu et à chaque recherche, cette page se remplit — et il y a de moins en moins de questions à vous poser.", bundle: .app)
        }
        // L'accord du pluriel n'est pas une affaire de « s » ajouté au bout :
        // il se règle dans le catalogue, langue par langue.
        var parts: [String] = []
        if profile.galleryCount > 0 {
            parts.append(String(localized: "\(profile.galleryCount) films que vous avez vus", bundle: .app))
        }
        if profile.watchlistCount > 0 {
            parts.append(String(localized: "\(profile.watchlistCount) films de votre liste à voir", bundle: .app))
        }
        let sources = parts.formatted(.list(type: .and))
        return String(localized: "Ces conclusions viennent de \(sources), et de vos réponses. Si l'une d'elles est fausse, déplacez le curseur : c'est vous qui aurez raison.", bundle: .app)
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
            return String(localized: "Tout reste à découvrir. Quelques recherches suffiront.", bundle: .app)
        }
        let list = names.count <= 3
            ? names.formatted(.list(type: .and))
            : String(localized: "\(names.prefix(3).formatted(.list(type: .and))) et d'autres", bundle: .app)
        return String(localized: "On ne sait pas encore grand-chose sur : \(list). Ça viendra.", bundle: .app)
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
                    Text("modifié par vous", bundle: .app)
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
        case .charge: (String(localized: "léger", bundle: .app), String(localized: "bouleversant", bundle: .app))
        case .rythme: (String(localized: "calme", bundle: .app), String(localized: "nerveux", bundle: .app))
        case .familiarite: (String(localized: "films connus", bundle: .app), String(localized: "films rares", bundle: .app))
        case .densite: (String(localized: "facile à suivre", bundle: .app), String(localized: "exigeant", bundle: .app))
        case .ancrage: (String(localized: "réaliste", bundle: .app), String(localized: "imaginaire", bundle: .app))
        case .ton: (String(localized: "sombre", bundle: .app), String(localized: "chaleureux", bundle: .app))
        case .echelle: (String(localized: "histoires intimes", bundle: .app), String(localized: "grand spectacle", bundle: .app))
        case .investissement: (String(localized: "films courts", bundle: .app), String(localized: "films longs", bundle: .app))
        }
    }

    /// La position dite comme on la dirait à quelqu'un, jamais en chiffres. Une
    /// phrase entière plutôt qu'un adjectif : « Plutôt limpide » ne dit pas au
    /// lecteur si c'est une observation sur lui ou une consigne donnée à l'app.
    private static func phrase(for axis: Axis, value: Double, known: Bool) -> String {
        guard known else { return String(localized: "Pas encore assez d'éléments pour le dire.", bundle: .app) }
        let strong = abs(value) > 0.45
        switch axis {
        case .charge:
            return value > 0
                ? (strong ? String(localized: "Vous aimez les films qui remuent.", bundle: .app) : String(localized: "Un peu d'émotion forte ne vous gêne pas.", bundle: .app))
                : (strong ? String(localized: "Vous préférez les films qui restent légers.", bundle: .app) : String(localized: "Plutôt des films légers.", bundle: .app))
        case .rythme:
            return value > 0
                ? (strong ? String(localized: "Il vous faut des films où ça avance vite.", bundle: .app) : String(localized: "Vous aimez que ça ne traîne pas.", bundle: .app))
                : (strong ? String(localized: "Vous aimez les films qui prennent leur temps.", bundle: .app) : String(localized: "Plutôt des films calmes.", bundle: .app))
        case .familiarite:
            return value > 0
                ? (strong ? String(localized: "Vous aimez découvrir des films dont personne ne parle.", bundle: .app) : String(localized: "Vous êtes curieux·se, sans chercher l'obscur.", bundle: .app))
                : (strong ? String(localized: "Vous préférez les films dont vous avez déjà entendu parler.", bundle: .app) : String(localized: "Plutôt des films connus.", bundle: .app))
        case .densite:
            return value > 0
                ? (strong ? String(localized: "Vous aimez les films qui demandent de l'attention.", bundle: .app) : String(localized: "Un film un peu exigeant ne vous fait pas peur.", bundle: .app))
                : (strong ? String(localized: "Vous voulez des films qui se laissent suivre facilement.", bundle: .app) : String(localized: "Plutôt des films faciles à suivre.", bundle: .app))
        case .ancrage:
            return value > 0
                ? (strong ? String(localized: "Vous aimez qu'un film vous emmène dans un autre monde.", bundle: .app) : String(localized: "Un peu d'imaginaire vous va bien.", bundle: .app))
                : (strong ? String(localized: "Vous préférez les histoires qui pourraient être vraies.", bundle: .app) : String(localized: "Plutôt des histoires réalistes.", bundle: .app))
        case .ton:
            return value > 0
                ? (strong ? String(localized: "Vous aimez les films qui font du bien.", bundle: .app) : String(localized: "Plutôt des films bienveillants.", bundle: .app))
                : (strong ? String(localized: "Les films sombres ne vous dérangent pas.", bundle: .app) : String(localized: "Plutôt des films sans complaisance.", bundle: .app))
        case .echelle:
            return value > 0
                ? (strong ? String(localized: "Le grand spectacle vous parle.", bundle: .app) : String(localized: "Vous aimez qu'il y ait de l'ampleur.", bundle: .app))
                : (strong ? String(localized: "Ce sont les histoires de quelques personnes qui vous touchent.", bundle: .app) : String(localized: "Plutôt des histoires à taille humaine.", bundle: .app))
        case .investissement:
            return value > 0
                ? (strong ? String(localized: "Un film de plus de deux heures ne vous fait pas peur.", bundle: .app) : String(localized: "Vous acceptez volontiers les films longs.", bundle: .app))
                : (strong ? String(localized: "Vous préférez que ça tienne en une heure et demie.", bundle: .app) : String(localized: "Plutôt des films courts.", bundle: .app))
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
