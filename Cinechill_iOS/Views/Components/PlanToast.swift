//
//  PlanToast.swift
//  Cinechill_iOS
//

import SwiftUI

/// L'accusé de réception d'un classement : ce qui vient d'être rangé, et où.
///
/// Il ne demande rien et ne se ferme pas — il passe. Trois décisions le tiennent
/// dans la direction :
/// - **Le film est nommé.** Un « Ajouté ! » seul ne vaut rien quand on tranche
///   une carte toutes les deux secondes : ce qu'on veut vérifier, c'est *lequel*
///   est parti, et où.
/// - **Le point dit l'état, pas la couleur.** Plein pour ce qui est acquis, creux
///   pour ce qui est prévu — le vocabulaire de `LibraryMark`, de la fiche film et
///   des grilles. L'écran reste lisible en niveaux de gris.
/// - **Un aplat de nuit, un filet.** Ni matériau translucide, ni ombre portée :
///   c'est la plaque de `SwipeMilestoneOverlay` à une autre échelle.
struct PlanToast: View {
    /// Ce qui vient d'être rangé.
    let title: String
    /// Où il est allé, en niveau de service : « Ajouté à votre galerie ».
    let destination: String
    /// Acquis (point plein) plutôt que prévu (point creux).
    var isAcquired: Bool = true
    /// Le bord contre lequel l'appelant le pose. Il entre par là : un toast qui
    /// arriverait du côté opposé à son ancrage se lirait comme un objet qui passe
    /// devant l'écran, pas comme un mot glissé au bord.
    var edge: VerticalEdge = .top
    /// Le toast connaît sa propre durée, et dit quand le retirer.
    var onFinished: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var travel: CGFloat = 0
    @State private var opacity: Double = 0

    /// Le temps de lecture, une fois posé. Assez long pour être lu de biais,
    /// assez court pour qu'il ait disparu avant la carte suivante.
    private static let dwell = 1500

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                if isAcquired {
                    PlanLight()
                } else {
                    PlanLightOutline()
                }
            }
            .padding(.top, 5)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Ink.ink)
                    .lineLimit(1)

                Text(destination)
                    .planLabel()
                    .foregroundStyle(Ink.ink2)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .frame(maxWidth: 320)
        .background(Ink.ground)
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                .strokeBorder(Ink.ruleSet, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous))
        .offset(y: travel)
        .opacity(opacity)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(destination)")
        .task { await play() }
    }

    /// Le retrait de départ : négatif sous un ancrage haut, positif sous un
    /// ancrage bas. Il rentre toujours **vers** le centre de l'écran.
    private var entryTravel: CGFloat {
        edge == .top ? -14 : 14
    }

    private func play() async {
        guard !reduceMotion else {
            travel = 0
            withAnimation(.easeOut(duration: 0.2)) { opacity = 1 }
            try? await Task.sleep(for: .milliseconds(Self.dwell))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.22)) { opacity = 0 }
            try? await Task.sleep(for: .milliseconds(240))
            guard !Task.isCancelled else { return }
            onFinished()
            return
        }

        // Il glisse depuis son bord pour entrer et s'éteint sur place : repartir
        // en sens inverse le ferait lire comme un tiroir qu'on referme, alors
        // qu'il n'a jamais été une surface qu'on ouvre.
        travel = entryTravel
        // Une frame de battement, sinon la pose et la détente se regroupent et
        // le toast apparaît déjà arrivé.
        try? await Task.sleep(for: .milliseconds(16))
        guard !Task.isCancelled else { return }

        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
            travel = 0
            opacity = 1
        }

        try? await Task.sleep(for: .milliseconds(Self.dwell))
        guard !Task.isCancelled else { return }

        withAnimation(.easeIn(duration: 0.24)) { opacity = 0 }
        try? await Task.sleep(for: .milliseconds(260))
        guard !Task.isCancelled else { return }
        onFinished()
    }
}

#Preview("Le toast") {
    ZStack {
        Ink.ground.ignoresSafeArea()
        VStack(spacing: 14) {
            PlanToast(
                title: "Interstellar",
                destination: String(localized: "Ajouté à votre galerie", bundle: .app)
            )
            PlanToast(
                title: "Le Voyage de Chihiro",
                destination: String(localized: "Ajouté à votre watchlist", bundle: .app),
                isAcquired: false
            )
        }
        .padding(Metrics.margin)
    }
}
