//
//  Cinechill_iOSApp.swift
//  Cinechill_iOS
//

import SwiftUI
import FirebaseCore

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseApp.configure()
        return true
    }
}

@main
struct Cinechill_iOSApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var authService = AuthService()
    @StateObject private var libraryStore = LibraryStore()
    @StateObject private var profileStore = UserProfileStore()

    var body: some Scene {
        WindowGroup {
            Group {
                if authService.isInitializing {
                    ProgressView("Initialisation…")
                } else if authService.isAuthenticated {
                    MainTabView()
                } else {
                    LoginView()
                }
            }
            .environmentObject(authService)
            .environmentObject(libraryStore)
            .environmentObject(profileStore)
            .task {
                libraryStore.start()
                profileStore.refresh()
            }
        }
    }
}
