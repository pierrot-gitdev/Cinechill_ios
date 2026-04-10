//
//  MainTabView.swift
//  Cinechill_iOS
//

import SwiftUI

struct MainTabView: View {
    @State private var homeModel = HomeViewModel(
        repository: PopularRepository(
            client: BackendPopularClient()
        )
    )
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(homeModel: homeModel)
                .tabItem {
                    Label("Accueil", systemImage: "house.fill")
                }
                .tag(0)

            GalleryView(selectedTab: $selectedTab)
                .tabItem {
                    Label("Galerie", systemImage: "trophy.fill")
                }
                .tag(1)

            WatchlistView(selectedTab: $selectedTab)
                .tabItem {
                    Label("Watchlist", systemImage: "bookmark.fill")
                }
                .tag(2)
        }
    }
}
