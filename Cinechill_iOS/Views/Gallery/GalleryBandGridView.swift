//
//  GalleryBandGridView.swift
//  Cinechill_iOS
//

import SwiftUI

/// Une bande ouverte en grille plein écran.
///
/// C'est le mode « je cherche un titre précis », que la vue en bandes ne
/// couvre pas : elle donne la forme de la collection, pas l'accès à un film.
struct GalleryBandGridView: View {
    let band: GalleryBand

    private let columns = [GridItem(.adaptive(minimum: 92, maximum: 130), spacing: 12)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(band.entries) { entry in
                    NavigationLink(destination: ItemDetailView(item: entry.mediaItem)) {
                        VStack(alignment: .leading, spacing: 6) {
                            PosterTile(
                                posterPath: entry.posterPath,
                                title: entry.title,
                                width: 110,
                                cornerRadius: 9
                            )
                            Text(entry.title)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .frame(width: 110, alignment: .leading)
                        }
                    }
                    .buttonStyle(PressableScaleStyle(scale: 0.94))
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
        .background(Color(.systemBackground))
        .navigationTitle(band.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Text("\(band.count)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }
}
