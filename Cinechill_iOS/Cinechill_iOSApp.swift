//
//  Cinechill_iOSApp.swift
//  Cinechill_iOS
//

import SwiftUI
import UserNotifications
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
        // Le délégué des notifications se pose avant la fin du lancement : un
        // toucher qui vient de lancer l'app lui est remis tout de suite après.
        UNUserNotificationCenter.current().delegate = NotificationCenterDelegate.shared
        NotificationCategories.register()
        PushRegistration.shared.start()
        // Un démarrage à froid repart d'un CinéMatch vierge : l'activité d'un
        // film lancé par le processus précédent n'a plus de résultat derrière
        // elle.
        CineMatchLiveActivity.endAll()
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        PushRegistration.shared.didReceiveAPNsToken(deviceToken)
    }

    /// Simulateur, ou capacité Push absente du profil de signature : l'app
    /// vit sans notifications distantes, rien d'autre ne change.
    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {}
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
    /// appartient pourtant, pour la même raison que l'onboarding : changer de langue
    /// rebâtit tout l'écran (`.id` plus bas), et rejouer sept secondes d'animation pour un
    /// réglage serait une punition.
    @State private var splashFinished = false

    /// L'onboarding. Tenu à la racine, et non dans `MainTabView`, pour une
    /// raison précise : changer de langue rebâtit tout l'écran (`.id` plus bas),
    /// et un onboarding en cours ne doit pas repartir de zéro pour autant. L'état
    /// de la vue ne survivrait pas ; celui de l'application, si.
    @State private var tour = OnboardingTour()

    /// Où mène le toucher d'une notification. Partagé avec le délégué des
    /// notifications, qui le remplit hors de toute vue.
    @State private var notificationRouter = NotificationRouter.shared

    @Environment(\.scenePhase) private var scenePhase

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
            // Le texte suit la taille choisie dans les réglages de l'iPhone,
            // jusqu'au deuxième cran des tailles d'accessibilité. Au-delà, les
            // grilles d'affiches et les planches ne tiennent plus sur un écran
            // de téléphone sans perdre ce qu'elles montrent.
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            // L'identité — étain, cyan, nuit — est dessinée pour le sombre ; le clair n'est
            // qu'un filet de sécurité pour du code encore non porté. On verrouille donc l'app
            // plutôt que de maintenir deux palettes dont une seule est réellement dessinée.
            .preferredColorScheme(.dark)
            .environmentObject(authService)
            .environmentObject(libraryStore)
            .environmentObject(profileStore)
            .environmentObject(socialStore)
            .environment(tour)
            .environment(notificationRouter)
            // Le seul moment où l'app reprend la main après un film lancé :
            // l'activité « en cours » dont la durée est passée s'y retire.
            .onChange(of: scenePhase, initial: true) { _, phase in
                if phase == .active { CineMatchLiveActivity.endFinished() }
                // Les notifications ont pu être autorisées ou coupées dans les
                // réglages de l'iPhone pendant l'absence.
                if phase == .active {
                    Task {
                        await authService.verifyAppleCredential()
                        await NotificationPermission.shared.refresh()
                        await PushRegistration.shared.sync()
                    }
                }
            }
            // Les notifications se rédigent dans la langue de l'app : le serveur
            // l'apprend, les libellés des actions et la question du lendemain
            // déjà programmée se réécrivent.
            .onChange(of: language.selection) { _, _ in
                // Changer de langue reconstruit l'app, résultat de CinéMatch
                // compris : son activité part avec lui.
                CineMatchLiveActivity.endAll()
                NotificationCategories.register()
                Task {
                    await PushRegistration.shared.sync()
                    await LocalReminders.relocalizeVerdict()
                }
            }
            .task {
                libraryStore.start()
                socialStore.start()
                profileStore.refresh()
            }
        }
    }
}
