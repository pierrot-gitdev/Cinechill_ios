//
//  TasteSheetView.swift
//  Cinechill_iOS
//

import SwiftUI

/// La Fiche : ce que Cinechill croit savoir de vous, en toutes lettres.
///
/// Un système qui apprend de quelqu'un sans jamais montrer ce qu'il en a conclu
/// devient une boîte noire — et une boîte noire qui se trompe est insupportable.
/// La Fiche est le contrat inverse : chaque axe est affiché en français, avec sa
/// marge de doute et sa provenance, et se corrige d'un geste. Une correction pèse
/// plus lourd que toute inférence.
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
                Text("Votre fiche")
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
            Text("Ce que Cinechill croit savoir")
                .planTitle(24)
                .foregroundStyle(Ink.ink)

            Text(provenanceLine)
                .font(.system(size: 12.5))
                .foregroundStyle(Ink.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 24)
        .padding(.bottom, 22)
    }

    private var provenanceLine: String {
        guard !profile.isEmpty else {
            return "Rien encore. Chaque film marqué comme vu, chaque séance, viendra préciser ces huit traits."
        }
        var parts: [String] = []
        if profile.galleryCount > 0 {
            parts.append("\(profile.galleryCount) film\(profile.galleryCount > 1 ? "s" : "") vu\(profile.galleryCount > 1 ? "s" : "")")
        }
        if profile.watchlistCount > 0 {
            parts.append("\(profile.watchlistCount) en attente")
        }
        return "D'après " + parts.joined(separator: ", ") + ". Faites glisser un repère pour corriger."
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
            return "Tout reste à cerner — quelques séances y suffiront."
        }
        let list = names.count <= 3
            ? names.formatted(.list(type: .and))
            : "\(names.prefix(3).formatted(.list(type: .and))) et d'autres"
        return "Encore incertain : \(list). Quelques séances les préciseront."
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
                    Text("corrigé")
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
        case .charge: ("léger", "éprouvant")
        case .rythme: ("posé", "haletant")
        case .familiarite: ("terrain connu", "inconnu")
        case .densite: ("limpide", "exigeant")
        case .ancrage: ("le réel", "l'imaginaire")
        case .ton: ("distancié", "chaleureux")
        case .echelle: ("intime", "épique")
        case .investissement: ("court", "long")
        }
    }

    /// La position dite en français d'humain. « Vous encaissez volontiers du lourd »
    /// plutôt que « CH = +0,6 » : la Fiche est un contrat de confiance, pas un dump.
    private static func phrase(for axis: Axis, value: Double, known: Bool) -> String {
        guard known else { return "On ne sait pas encore." }
        let strong = abs(value) > 0.45
        switch axis {
        case .charge:
            return value > 0
                ? (strong ? "Vous encaissez volontiers du lourd." : "Un peu de gravité ne vous gêne pas.")
                : (strong ? "Vous préférez qu'on vous épargne." : "Plutôt léger, sans y tenir.")
        case .rythme:
            return value > 0
                ? (strong ? "Il vous faut que ça avance." : "Vous aimez qu'on ne traîne pas trop.")
                : (strong ? "Vous laissez volontiers un film prendre son temps." : "Plutôt posé.")
        case .familiarite:
            return value > 0
                ? (strong ? "Vous cherchez ce que personne ne vous a vendu." : "Curieux, sans chercher l'obscur.")
                : (strong ? "Les valeurs sûres vous vont très bien." : "Plutôt en terrain connu.")
        case .densite:
            return value > 0
                ? (strong ? "Vous aimez avoir à chercher." : "Un peu d'exigence vous va.")
                : (strong ? "Vous voulez que ça se laisse suivre." : "Plutôt limpide.")
        case .ancrage:
            return value > 0
                ? (strong ? "Vous aimez qu'on vous emmène ailleurs." : "Un peu d'imaginaire vous va.")
                : (strong ? "Vous préférez ce qui pourrait exister." : "Plutôt ancré dans le réel.")
        case .ton:
            return value > 0
                ? (strong ? "Vous aimez qu'un film soit chaleureux." : "Plutôt bienveillant.")
                : (strong ? "Vous supportez très bien la froideur." : "Plutôt distancié.")
        case .echelle:
            return value > 0
                ? (strong ? "Le grand spectacle vous parle." : "Vous aimez qu'il y ait de l'ampleur.")
                : (strong ? "Ce sont les histoires intimes qui vous touchent." : "Plutôt à hauteur d'humain.")
        case .investissement:
            return value > 0
                ? (strong ? "Vous vous engagez volontiers sur la durée." : "Un film long ne vous fait pas peur.")
                : (strong ? "Vous préférez que ça tienne en une heure et demie." : "Plutôt court.")
        }
    }
}

#Preview("La fiche") {
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
