//
//  Cinechill_iOSApp.swift
//  Cinechill_iOS
//

import SwiftUI
import FirebaseCore
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

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
    @StateObject private var socialStore = SocialStore()

    /// Le splash joue sa séquence en entier avant de passer la main. On garde donc l'écran tant
    /// que l'animation n'est pas allée au bout **ou** que l'auth n'a pas répondu : la donnée
    /// arrive en tâche de fond pendant l'animation, et c'est le plus lent des deux qui décide.
    @State private var splashFinished = false

    /// Le code d'action d'un lien « mot de passe oublié ». L'app est seule à
    /// voir passer les URL entrantes ; elle le transmet à l'écran, qui le
    /// consomme puis le rend.
    @State private var passwordResetCode: String?

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
                    AuthView(
                        resetCode: passwordResetCode,
                        onResetCodeConsumed: { passwordResetCode = nil }
                    )
                    .transition(.opacity)
                }
            }
            // Le lien de réinitialisation ramène dans l'app plutôt que sur la
            // page web de Firebase — à condition qu'une URL d'action
            // personnalisée soit déclarée en console et le domaine associé dans
            // les entitlements. Sans cette configuration, ce bloc n'est jamais
            // atteint et le parcours s'arrête à l'écran « lien envoyé ».
            .onOpenURL { url in
                if let code = AuthService.passwordResetCode(from: url) {
                    passwordResetCode = code
                    splashFinished = true
                    return
                }
#if canImport(GoogleSignIn)
                // Le retour de la feuille Google, quand elle passe par Safari.
                _ = GIDSignIn.sharedInstance.handle(url)
#endif
            }
            .animation(.easeInOut(duration: 0.45), value: splashFinished)
            .animation(.easeInOut(duration: 0.45), value: authService.isInitializing)
            // L'identité — étain, cyan, nuit — est dessinée pour le sombre ; le clair n'est
            // qu'un filet de sécurité pour du code encore non porté. On verrouille donc l'app
            // plutôt que de maintenir deux palettes dont une seule est réellement dessinée.
            .preferredColorScheme(.dark)
            .environmentObject(authService)
            .environmentObject(libraryStore)
            .environmentObject(profileStore)
            .environmentObject(socialStore)
            .task {
                libraryStore.start()
                socialStore.start()
                profileStore.refresh()
            }
        }
    }
}
