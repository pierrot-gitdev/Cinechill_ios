//
//  MainTabView.swift
//  Cinechill_iOS
//

import SwiftUI

struct MainTabView: View {
    @State private var homeModel: HomeViewModel
    @State private var selectedTab = 0

    init() {
        let client = BackendPopularClient()
        _homeModel = State(initialValue: HomeViewModel(
            repository: PopularRepository(client: client),
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
