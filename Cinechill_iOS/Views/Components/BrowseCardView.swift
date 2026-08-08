import SwiftUI

/// La carte d'une catégorie : un nom, et l'affiche du film qui la représente.
///
/// Elle prend la largeur qu'on lui donne, pour servir aussi bien la rangée
/// horizontale de l'accueil que la grille de l'écran « Parcourir ». C'est la
/// condition pour que les deux soient réellement le même objet.
///
/// L'affiche ne penche plus. La rotation de 10° était le seul élément
/// décoratif d'un composant par ailleurs strictement fonctionnel, et elle
/// obligeait à rogner la carte pour cacher le coin qui dépassait.
struct BrowseCardView: View {
    let title: String
    let posterURL: URL?
    var height: CGFloat = 84

    var body: some View {
        HStack(spacing: 0) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Ink.ink)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.leading, 13)
                .padding(.trailing, 8)
                .padding(.vertical, 12)

            poster
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                .strokeBorder(Ink.rule, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }

    @ViewBuilder
    private var poster: some View {
        if let posterURL {
            PosterImageView(url: posterURL)
                .frame(width: (height - 16) * 2 / 3, height: height - 16)
                .clipShape(RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous))
                .padding(.trailing, 8)
        }
    }
}

#Preview("Parcourir") {
    ZStack {
        Ink.ground.ignoresSafeArea()
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
            spacing: 10
        ) {
            BrowseCardView(title: "Science-fiction", posterURL: nil)
            BrowseCardView(title: "Comédie", posterURL: nil)
            BrowseCardView(title: "Documentaire", posterURL: nil)
            BrowseCardView(title: "Films d'animation", posterURL: nil)
        }
        .padding(Metrics.margin)
    }
}
