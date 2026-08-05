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
    var cornerRadius: CGFloat = 6

    private var height: CGFloat { width * 3 / 2 }

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
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.16), radius: width * 0.08, y: width * 0.04)
        .accessibilityLabel(title)
    }

    /// Sans affiche, on montre le titre plutôt qu'une icône générique : c'est
    /// la seule chose qui permette encore de reconnaître le film.
    private var fallback: some View {
        ZStack {
            LinearGradient(
                colors: [Color(.tertiarySystemFill), Color(.quaternarySystemFill)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Text(title)
                .font(.system(size: max(7, width * 0.13), weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .padding(width * 0.1)
        }
    }
}

#Preview {
    HStack(alignment: .bottom, spacing: 10) {
        PosterTile(posterPath: nil, title: "Blade Runner", width: 40)
        PosterTile(posterPath: nil, title: "Interstellar", width: 60)
        PosterTile(posterPath: nil, title: "Le Fabuleux Destin d'Amélie Poulain", width: 80)
    }
    .padding()
}
