//
//  PosterTile.swift
//  Cinechill_iOS
//

import SwiftUI

/// L'affiche, à n'importe quelle taille.
///
/// Le seul composant que la galerie et la watchlist partagent : elles n'ont
/// aucune structure en commun, mais la tuile d'affiche n'a aucune raison
/// d'exister en double. S'appuie sur `PosterImageCache` plutôt que sur
/// `AsyncImage`, pour que les affiches déjà vues ailleurs dans l'app
/// s'affichent instantanément.
struct PosterTile: View {
    let posterPath: String?
    let title: String
    let width: CGFloat
    var cornerRadius: CGFloat = Metrics.radius

    private var height: CGFloat { width * 3 / 2 }

    var body: some View {
        PosterSurface(posterPath: posterPath, title: title, cornerRadius: cornerRadius)
            .frame(width: width, height: height)
            .accessibilityLabel(title)
    }
}

/// L'affiche qui prend la largeur qu'on lui donne, au ratio 2/3.
///
/// C'est la variante dont les grilles ont besoin : `PosterTile` impose sa
/// largeur, ce qui interdit un `LazyVGrid` à colonnes flexibles — et c'est ce
/// qui avait justifié l'existence d'un second composant de carte.
struct PosterFrame: View {
    let posterPath: String?
    let title: String
    var cornerRadius: CGFloat = Metrics.radius

    var body: some View {
        PosterSurface(posterPath: posterPath, title: title, cornerRadius: cornerRadius)
            .aspectRatio(2 / 3, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .accessibilityLabel(title)
    }
}

/// Le dessin commun aux deux : l'image, son masque, son filet. Sans ombre
/// portée — le liseré suffit à détacher l'affiche de la nuit, et l'ombre était
/// le dernier effet décoratif du composant le plus répété de l'app.
private struct PosterSurface: View {
    let posterPath: String?
    let title: String
    let cornerRadius: CGFloat

    private var url: URL? {
        guard let posterPath, !posterPath.isEmpty else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w342\(posterPath)")
    }

    var body: some View {
        Group {
            if url != nil {
                PosterImageView(url: url)
            } else {
                fallback
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Ink.rule, lineWidth: 1)
        )
    }

    /// Sans affiche, on montre le titre plutôt qu'une icône générique : c'est
    /// la seule chose qui permette encore de reconnaître le film.
    private var fallback: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                Color(hex: 0x151B23)
                Text(title)
                    .font(.system(size: max(8, side * 0.11), weight: .medium))
                    .foregroundStyle(Ink.ink3)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(side * 0.12)
            }
        }
    }
}

/// Une affiche et son titre, dans une grille.
///
/// Le seul gabarit de vignette de l'application. Il remplace à la fois le
/// `posterCell` privé de l'accueil et `ContentCardView`, qui disaient la même
/// chose avec deux dessins, deux typographies et deux jeux de pastilles d'état.
///
/// Deux lignes sont réservées au titre quoi qu'il arrive : sans hauteur fixe, un
/// titre court et un titre long ne donnent pas la même hauteur de cellule, et
/// les affiches se désalignent d'une rangée à l'autre.
struct PosterCell: View {
    let posterPath: String?
    let title: String
    var inGallery: Bool = false
    var inWatchlist: Bool = false

    /// Hauteur réservée au titre — deux lignes à 11 pt.
    static let titleHeight: CGFloat = 29

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            PosterFrame(posterPath: posterPath, title: title)
                .overlay(alignment: .topTrailing) {
                    LibraryMark(inGallery: inGallery, inWatchlist: inWatchlist)
                        .padding(6)
                }

            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(Ink.ink)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, minHeight: Self.titleHeight, alignment: .topLeading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        title
            + (inGallery ? String(localized: ", déjà vu", bundle: .app) : "")
            + (inWatchlist ? String(localized: ", dans ta watchlist", bundle: .app) : "")
    }
}

#Preview("Affiches") {
    ZStack {
        Ink.ground.ignoresSafeArea()
        VStack(spacing: 30) {
            HStack(alignment: .bottom, spacing: 10) {
                PosterTile(posterPath: nil, title: "Blade Runner", width: 40)
                PosterTile(posterPath: nil, title: "Interstellar", width: 60)
                PosterTile(posterPath: nil, title: "Le Fabuleux Destin d'Amélie Poulain", width: 80)
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
                spacing: 14
            ) {
                PosterCell(posterPath: nil, title: "Blade Runner 2049", inGallery: true)
                PosterCell(posterPath: nil, title: "Interstellar", inWatchlist: true)
                PosterCell(posterPath: nil, title: "Premier Contact")
            }
            .padding(.horizontal, Metrics.margin)
        }
    }
}
