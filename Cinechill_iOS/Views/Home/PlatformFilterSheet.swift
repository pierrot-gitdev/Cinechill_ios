import SwiftUI

struct PlatformFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var libraryStore: LibraryStore

    let platforms: [StreamingPlatform]
    @State private var draftSelection: Set<String>

    init(platforms: [StreamingPlatform], selectedIDs: Set<String>) {
        self.platforms = platforms
        _draftSelection = State(initialValue: selectedIDs)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Capsule()
                    .fill(Color.gray.opacity(0.35))
                    .frame(width: 70, height: 6)
                    .padding(.top, 6)

                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(platforms) { platform in
                            platformChip(platform)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                }

                Divider()

                HStack {
                    Button("Tout effacer") {
                        draftSelection = []
                    }
                    .foregroundStyle(.primary)

                    Spacer()

                    Button("Enregistrer") {
                        libraryStore.setPreferredPlatforms(draftSelection)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            }
            .navigationTitle("Filtrer vos recommandations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    }

    private func platformChip(_ platform: StreamingPlatform) -> some View {
        let selected = draftSelection.contains(platform.id)
        return Button {
            if selected {
                draftSelection.remove(platform.id)
            } else {
                draftSelection.insert(platform.id)
            }
        } label: {
            HStack(spacing: 8) {
                if let logoURL = platform.logoURL {
                    AsyncImage(url: logoURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                        default:
                            Text(platform.shortLabel)
                                .font(.caption2.weight(.bold))
                        }
                    }
                    .frame(width: 24, height: 24)
                } else {
                    Text(platform.shortLabel)
                        .font(.caption2.weight(.bold))
                        .frame(width: 24, height: 24)
                }

                Text(platform.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(selected ? Color.indigo.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(selected ? Color.indigo : Color.gray.opacity(0.35), lineWidth: selected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}

