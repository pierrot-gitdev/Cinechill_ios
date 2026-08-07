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

    /// Le splash joue sa séquence en entier avant de passer la main. On garde donc l'écran tant
    /// que l'animation n'est pas allée au bout **ou** que l'auth n'a pas répondu : la donnée
    /// arrive en tâche de fond pendant l'animation, et c'est le plus lent des deux qui décide.
    @State private var splashFinished = false

    var body: some Scene {
        WindowGroup {
            Group {
                if !splashFinished || authService.isInitializing {
                    SplashView { splashFinished = true }
                        .transition(.opacity)
                } else if authService.isAuthenticated {
                    MainTabView()
                        .transition(.opacity)
                } else {
                    LoginView()
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.45), value: splashFinished)
            .animation(.easeInOut(duration: 0.45), value: authService.isInitializing)
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
