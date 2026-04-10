//
//  ItemDetailView.swift
//  Cinechill_iOS
//

import SwiftUI

struct ItemDetailView: View {
    let item: MediaItem

    @State private var detail: TMDBDetailResponse?
    @State private var loading = true
    @State private var errorMessage: String?

    private var displayItem: MediaItem {
        detail.map { $0.asMediaItem(mediaType: item.mediaType) } ?? item
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                metaRow
                synopsis
                if let d = detail, !d.castLine.isEmpty {
                    castSection(d.castLine)
                }
            }
            .padding()
        }
        .navigationTitle(displayItem.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadDetail() }
    }

    @ViewBuilder
    private var header: some View {
        ZStack(alignment: .bottomLeading) {
            if let url = detail?.backdropURL ?? displayItem.posterURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        Color.secondary.opacity(0.2)
                    }
                }
                .frame(height: 200)
                .clipped()
            } else {
                Color.secondary.opacity(0.2)
                    .frame(height: 200)
            }

            HStack(alignment: .bottom, spacing: 12) {
                posterThumb
                VStack(alignment: .leading, spacing: 4) {
                    Text(displayItem.title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                    Text("\(displayItem.mediaType.singularLabel) · \(displayItem.displayYear)")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.9))
                }
                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    colors: [.black.opacity(0.75), .clear],
                    startPoint: .bottom,
                    endPoint: .center
                )
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private var posterThumb: some View {
        let url = detail?.posterDetailURL ?? displayItem.posterURL
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        Color.secondary.opacity(0.3)
                    }
                }
            } else {
                Color.secondary.opacity(0.3)
            }
        }
        .frame(width: 88, height: 132)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private var metaRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Label("\(displayItem.voteAverageText)/10", systemImage: "star.fill")
                    .foregroundStyle(.yellow)
                if loading {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            .font(.subheadline.weight(.semibold))

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private var synopsis: some View {
        Group {
            if let text = detail?.overview ?? displayItem.overview, !text.isEmpty {
                Text(text)
                    .font(.body)
                    .foregroundStyle(.primary)
            }
        }
    }

    private func castSection(_ line: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Distribution")
                .font(.headline)
            Text(line)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func loadDetail() async {
        loading = true
        errorMessage = nil
        defer { loading = false }
        let client = BackendDetailClient()
        do {
            detail = try await client.itemDetails(id: item.tmdbId, mediaType: item.mediaType)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
