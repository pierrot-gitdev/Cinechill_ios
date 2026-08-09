//
//  GallerySignatureView.swift
//  Cinechill_iOS
//

import SwiftUI

/// La carte d'identité de la collection : de quoi se reconnaître en trois
/// secondes, sans basculer dans le tableau de bord.
struct GallerySignatureView: View {
    let signature: GallerySignature

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            countRow

            if !signature.shares.isEmpty {
                genreBar
                legend
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 4)
    }

    private var countRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Text(verbatim: "\(signature.total)")
                .planTitle(38)
                .monospacedDigit()
                .foregroundStyle(Ink.ink)
                .contentTransition(.numericText())

            Text(signature.total > 1 ? String(localized: "films vus", bundle: .app) : String(localized: "film vu", bundle: .app))
                .planLabel()
                .foregroundStyle(Ink.ink2)

            Spacer(minLength: 0)

            // Ce qui vient d'entrer s'allume — le même signe que partout, plutôt
            // qu'une pastille verte qui n'appartenait à rien.
            if signature.addedThisMonth > 0 {
                HStack(spacing: 7) {
                    PlanLight()
                    Text(String(localized: "+\(signature.addedThisMonth) ce mois", bundle: .app))
                        .planLabel()
                        .monospacedDigit()
                        .foregroundStyle(Ink.light)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "\(signature.total) films vus, dont \(signature.addedThisMonth) ce mois", bundle: .app))
    }

    /// Une seule ligne proportionnelle plutôt qu'un camembert : la comparaison
    /// de longueurs est immédiate, celle d'angles ne l'est jamais.
    private var genreBar: some View {
        GeometryReader { proxy in
            HStack(spacing: 1.5) {
                ForEach(signature.shares) { share in
                    Capsule()
                        .fill(share.color)
                        .frame(width: max(2, proxy.size.width * share.share - 1.5))
                }
            }
        }
        .frame(height: 9)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            signature.shares
                .map { "\($0.name) \($0.percentText)" }
                .joined(separator: ", ")
        )
    }

    private var legend: some View {
        FlowLayout(spacing: 12) {
            ForEach(signature.shares.prefix(4)) { share in
                HStack(spacing: 5) {
                    Circle()
                        .fill(share.color)
                        .frame(width: 6, height: 6)
                    Text(share.name)
                        .foregroundStyle(.secondary)
                    Text(share.percentText)
                        .foregroundStyle(.primary)
                }
                .font(.system(size: 11))
            }
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    GallerySignatureView(
        signature: GallerySignature(
            total: 142,
            addedThisMonth: 18,
            shares: [
                GenreShare(id: 28, name: "Action", share: 0.24, colorIndex: 0),
                GenreShare(id: 18, name: "Drame", share: 0.19, colorIndex: 1),
                GenreShare(id: 878, name: "Science-fiction", share: 0.15, colorIndex: 2),
                GenreShare(id: 53, name: "Thriller", share: 0.12, colorIndex: 3),
                GenreShare(id: 35, name: "Comédie", share: 0.09, colorIndex: 4),
                GenreShare(id: -1, name: "Autres", share: 0.21, colorIndex: -1),
            ]
        )
    )
}
