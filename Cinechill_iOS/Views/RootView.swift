//
//  RootView.swift
//  Cinechill_iOS
//

import SwiftUI
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

/// L'aiguillage de l'app : l'ouverture, puis l'authentification ou les onglets.
///
/// Cette vue existe pour une raison que le fichier `App` ne pouvait pas remplir : elle vit
/// **pendant** l'ouverture. `MainTabView` n'est construite qu'une fois le splash terminé, si
/// bien que tout ce que l'accueil demande au réseau ne partait qu'à ce moment-là. Toute
/// l'ouverture s'écoulait sans qu'aucune donnée ne soit en vol.
///
/// L'accueil est donc préchargé ici, dès que l'auth a répondu, et son modèle est prêté à
/// `MainTabView` plutôt que créé par elle. Les deux appels au chargement se croisent sans se
/// gêner : `loadAllIfNeeded` ne fait rien si le préchargement est déjà passé, et l'écran
/// affiche son attente normale s'il est encore en vol.
///
/// Le périmètre est volontairement l'accueil seul. Les quatre autres onglets ne sont pas montés
/// à l'ouverture, et les précharger reviendrait à lancer cinq écrans de requêtes pour un
/// utilisateur qui en regardera un.
struct RootView: View {
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var libraryStore: LibraryStore

    /// Le répertoire et l'accueil sont tenus ici plutôt que dans `MainTabView` : c'est ce qui
    /// leur permet d'exister, et donc de charger, avant que le moindre onglet ne soit monté.
    @State private var catalog = MediaCatalog()
    @State private var homeModel: HomeViewModel

    /// Vit dans le fichier `App` pour survivre au changement de langue, qui rebâtit cette vue.
    @Binding var splashFinished: Bool

    /// Le code d'action d'un lien « mot de passe oublié ». L'app est seule à
    /// voir passer les URL entrantes ; elle le transmet à l'écran, qui le
    /// consomme puis le rend.
    @State private var passwordResetCode: String?

    init(splashFinished: Binding<Bool>) {
        _splashFinished = splashFinished
        let client = BackendPopularClient()
        _homeModel = State(initialValue: HomeViewModel(
            repository: PopularRepository(client: client),
            metadataClient: client
        ))
    }

    var body: some View {
        Group {
            if !splashFinished || authService.isInitializing {
                SplashView { splashFinished = true }
                    .transition(.opacity)
            } else if authService.isAuthenticated {
                MainTabView(catalog: catalog, homeModel: homeModel)
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
        .task(id: authService.isAuthenticated) {
            await preloadHome()
        }
    }

    /// Remplit l'accueil pendant que l'ouverture se joue.
    ///
    /// L'ordre compte. Le répertoire des genres et des plateformes part tout de suite : il ne
    /// dépend de personne, et une bonne moitié de l'app l'attend. Le reste attend les
    /// plateformes déclarées, sans quoi « populaire » serait chargé sans filtre puis rechargé
    /// avec — deux fois le même aller-retour, et une liste qui change sous les yeux au moment
    /// précis où l'écran apparaît.
    private func preloadHome() async {
        guard authService.isAuthenticated else { return }

        async let repertoire: Void = catalog.loadIfNeeded()
        // Les écrans réveillent les fonctions dont ils ont besoin en les appelant. Celle qui
        // écrit les statuts n'est appelée que bien plus tard, quand l'utilisateur marque un
        // film : on la réveille donc ici, pendant que l'ouverture se joue, plutôt que de lui
        // faire attendre plusieurs secondes au premier « Vu ».
        async let awake: Void = libraryStore.warmUpStatusEndpoint()

        await libraryStore.waitForPreferences(upTo: .seconds(2))
        await homeModel.loadAllIfNeeded(preferredPlatformIDs: libraryStore.preferredPlatformIDs)
        await repertoire
        await awake
    }
}
