//
//  MainTabView.swift
//  Cinechill_iOS
//

import SwiftUI

struct MainTabView: View {
    @State private var homeModel: HomeViewModel
    @State private var questionnaireModel: QuestionnaireViewModel
    @State private var selectedTab = 0

    init() {
        let client = BackendPopularClient()
        _homeModel = State(initialValue: HomeViewModel(
            repository: PopularRepository(client: client),
            metadataClient: client
        ))
        _questionnaireModel = State(initialValue: QuestionnaireViewModel(
            recommendationClient: BackendRecommendationClient(),
            metadataClient: client
        ))
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(homeModel: homeModel)
                .tabItem {
                    Label("Accueil", systemImage: "house.fill")
                }
                .tag(0)

            QuestionnaireView(viewModel: questionnaireModel)
                .tabItem {
                    Label("CinéMatch", systemImage: "popcorn.fill")
                }
                .tag(1)

            GalleryView(selectedTab: $selectedTab)
                .tabItem {
                    Label("Galerie", systemImage: "trophy.fill")
                }
                .tag(2)

            WatchlistView(selectedTab: $selectedTab)
                .tabItem {
                    Label("Watchlist", systemImage: "bookmark.fill")
                }
                .tag(3)
        }
    }
}
