import SwiftUI

struct GalleryView: View {
    @Binding var selectedTab: Int

    var body: some View {
        NavigationView {
            ZStack {
                Color(.systemBackground)
                .ignoresSafeArea()

                emptyState
                    .padding()
            }
            .navigationTitle("Ma galerie")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.stack.3d.up.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Votre galerie est vide pour le moment.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Explorer l’accueil") {
                selectedTab = 0
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}
