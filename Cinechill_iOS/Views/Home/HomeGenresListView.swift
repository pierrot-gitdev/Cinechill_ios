import SwiftUI

/// Tous les genres — la suite de la rangée « Parcourir » de l'accueil.
///
/// C'était une liste de dix-huit noms à chevrons : rien n'y appartenait à
/// l'application, et surtout le geste changeait de langue en cours de route —
/// on quittait une rangée d'affiches pour arriver sur un tableau de réglages.
///
/// La grille reprend donc **exactement** la carte de la rangée dont elle est
/// issue. Continuer un geste, ce n'est pas seulement garder les couleurs : c'est
/// garder l'objet qu'on vient de toucher.
struct HomeGenresListView: View {
    let categories: [HomeBrowseCategory]
    let homeModel: HomeViewModel

    private let columns = [
        GridItem(.flexible(), spacing: Metrics.gutter),
        GridItem(.flexible(), spacing: Metrics.gutter)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: Metrics.gutter) {
                ForEach(categories) { category in
                    NavigationLink(value: category) {
                        BrowseCardView(
                            title: category.title,
                            posterURL: homeModel.browsePosterURL(for: category.id)
                        )
                    }
                    .buttonStyle(PressableScaleStyle(scale: 0.96))
                }
            }
            .padding(.horizontal, Metrics.margin)
            .padding(.top, 18)
            .padding(.bottom, 28)
        }
        .background(Ink.ground)
        .safeAreaInset(edge: .top) {
            PlanHeader("Parcourir") {
                PlanHeaderCount(value: "\(categories.count)")
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}
