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
        // Avant `configure()`, impérativement : Firebase instancie son
        // fournisseur d'attestation à ce moment-là et ne le relit plus ensuite.
        AppAttestation.install()
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

    /// La langue choisie dans les réglages. Lue ici pour une seule raison :
    /// c'est à la racine qu'on peut redemander l'écran entier quand elle change.
    @State private var language = LanguageStore.shared

    /// L'ouverture est-elle allée jusqu'au bout. Tenue ici, et non dans `RootView` à qui elle
    /// appartient pourtant, pour la même raison que la prise en main : changer de langue
    /// rebâtit tout l'écran (`.id` plus bas), et rejouer sept secondes d'animation pour un
    /// réglage serait une punition.
    @State private var splashFinished = false

    /// La prise en main. Tenue à la racine, et non dans `MainTabView`, pour une
    /// raison précise : changer de langue rebâtit tout l'écran (`.id` plus bas),
    /// et une visite en cours ne doit pas repartir de zéro pour autant. L'état
    /// de la vue ne survivrait pas ; celui de l'application, si.
    @State private var tour = OnboardingTour()

    var body: some Scene {
        WindowGroup {
            // L'aiguillage vit dans `RootView`, et non ici, parce qu'il doit exister pendant
            // l'ouverture : c'est là que l'accueil se précharge, tandis que le splash joue.
            RootView(splashFinished: $splashFinished)
            // Changer de langue rebâtit l'écran de fond en comble.
            //
            // La quasi-totalité des chaînes de l'app se résolvent par
            // `String(localized:bundle:)`, hors de toute dépendance SwiftUI :
            // rien n'irait redemander leur corps aux vues déjà affichées. Le
            // `.id` le fait sans détour, au prix d'un retour à l'onglet
            // d'accueil — ce que fait iOS lui-même quand on change la langue
            // d'une app depuis ses réglages système.
            //
            // La locale d'environnement suit, pour les dates et les nombres que
            // SwiftUI formate lui-même.
            .id(language.selection)
            .environment(\.locale, language.selection.locale)
            // L'identité — étain, cyan, nuit — est dessinée pour le sombre ; le clair n'est
            // qu'un filet de sécurité pour du code encore non porté. On verrouille donc l'app
            // plutôt que de maintenir deux palettes dont une seule est réellement dessinée.
            .preferredColorScheme(.dark)
            .environmentObject(authService)
            .environmentObject(libraryStore)
            .environmentObject(profileStore)
            .environmentObject(socialStore)
            .environment(tour)
            .task {
                libraryStore.start()
                socialStore.start()
                profileStore.refresh()
            }
        }
    }
}
