//
//  CineMatchView.swift
//  Cinechill_iOS
//

import SwiftUI

/// L'onglet CinéMatch : la Porte, puis le parcours de la soirée.
///
/// La Porte est reprise **à l'identique** de `QuestionnaireView` : même état de
/// session pour le seuil, même profil, même planche des coups de cœur, même
/// remesure au retour sur l'onglet. Seule nouveauté, l'artéfact « Tes
/// préférences » ouvre les comparaisons entre films vus.
///
/// Passé le seuil, l'écran n'a plus de décor commun : chaque étape porte le sien
/// (le salon à l'accueil, une page plate pour les questions, la planche des
/// cinq). Le conteneur ne fait qu'aiguiller sur `viewModel.step`.
struct CineMatchView: View {
    let viewModel: CineMatchViewModel
    /// L'onglet courant : la porte envoie vers Découvrir, là où la galerie se
    /// remplit.
    @Binding var selectedTab: Int

    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var libraryStore: LibraryStore
    @EnvironmentObject private var profileStore: UserProfileStore
    @EnvironmentObject private var socialStore: SocialStore
    @Environment(BadgesViewModel.self) private var badgesModel
    @Environment(DoorStore.self) private var doorStore
    @Environment(MediaCatalog.self) private var catalog
    @Environment(OnboardingTour.self) private var tour

    @State private var showProfile = false
    @State private var showLovePicker = false
    @State private var showDoorComparison = false
    /// Le seuil a été franchi **dans cette ouverture de l'app**. Volontairement
    /// un état de session et non une préférence gardée : la cérémonie se rejoue
    /// à chaque lancement, elle ne se consomme pas une fois pour toutes.
    @State private var hasCrossedThreshold = false

    var body: some View {
        NavigationStack {
            ZStack {
                Ink.ground.ignoresSafeArea()
                content
            }
            .navigationBarHidden(true)
            .fullScreenCover(isPresented: $showProfile) {
                ProfileView(badgesModel: badgesModel)
                    .environmentObject(profileStore)
                    .environmentObject(libraryStore)
                    .environmentObject(authService)
                    .environmentObject(socialStore)
            }
            .sheet(isPresented: $showLovePicker) {
                LovePickerView(
                    target: doorStore.door.artifact(.coeur)?.target ?? 12,
                    onClose: { showLovePicker = false }
                )
                .environmentObject(libraryStore)
            }
            .fullScreenCover(isPresented: $showDoorComparison) {
                CineMatchDoorComparisonView(onClose: { showDoorComparison = false })
                    .environmentObject(libraryStore)
                    .environment(doorStore)
                    .environment(catalog)
            }
        }
        // Chaque retour sur l'onglet remesure la porte : la galerie a pu se
        // remplir depuis Découvrir, et la jauge doit le raconter sans attendre.
        .onChange(of: selectedTab) { _, tab in
            guard tab == 1 else { return }
            Task { await doorStore.refresh() }
        }
        // La planche refermée, on remesure aussi : c'est peut-être elle qui
        // vient d'allumer le Cœur.
        .onChange(of: showLovePicker) { _, isOpen in
            guard !isOpen else { return }
            Task { await doorStore.refresh() }
        }
        // Même chose au retour des comparaisons : ce sont elles qui font
        // avancer « Tes préférences ».
        .onChange(of: showDoorComparison) { _, isOpen in
            guard !isOpen else { return }
            Task { await doorStore.refresh() }
        }
        // Les plateformes vivent dans la bibliothèque, pas dans la séance : un
        // changement fait depuis les réglages ou depuis la feuille du scénario
        // doit se retrouver dans la prochaine recherche.
        .onChange(of: libraryStore.preferredPlatformIDs) { _, _ in
            syncPlatforms()
        }
        .task { syncPlatforms() }
    }

    @ViewBuilder
    private var content: some View {
        // Pendant la prise en main, l'onglet se montre au lieu de servir : le
        // salon d'abord, même verrouillé, puis la porte telle qu'un compte neuf
        // la trouve. Tout reste inerte : la visite montre, elle ne sert pas.
        switch tour.step {
        case .cinematch?:
            CineMatchHomeView(viewModel: viewModel, onProfileTap: {}, showsScenario: false)
                .transition(.opacity)
        case .porte?:
            CineMatchGateView(
                door: tourDoor,
                isMeasured: false,
                lovedCount: libraryStore.lovedCount,
                onProfileTap: {},
                onDiscover: {},
                onLovePicker: {},
                onCompare: {},
                onEnter: {}
            )
            .transition(.opacity)
        default:
            servingContent
        }
    }

    /// La porte montrée par la visite. Elle ne peut pas être ouverte : une
    /// porte gagnée jouerait sa cérémonie sous le cartouche, et la visite ne
    /// présente que des comptes à la bibliothèque vide.
    private var tourDoor: DoorState {
        doorStore.door.unlocked ? .initial : doorStore.door
    }

    @ViewBuilder
    private var servingContent: some View {
        // La porte garde l'onglet tant que le profil n'est pas prêt, et reste
        // une dernière fois pour l'ouverture : le seuil ne se franchit qu'en la
        // voyant céder. Elle ne peut s'interposer qu'à l'accueil, jamais au
        // milieu d'une recherche.
        if viewModel.step == .home && (!doorStore.door.unlocked || !hasCrossedThreshold) {
            CineMatchGateView(
                door: doorStore.door,
                isMeasured: doorStore.hasMeasured,
                lovedCount: libraryStore.lovedCount,
                onProfileTap: { showProfile = true },
                onDiscover: { selectedTab = 2 },
                onLovePicker: { showLovePicker = true },
                onCompare: { showDoorComparison = true },
                onEnter: {
                    withAnimation(.easeOut(duration: 0.45)) { hasCrossedThreshold = true }
                },
                isCelebrating: doorStore.celebration != nil
            )
            // Le raccord : le travelling finit dans l'accueil au lieu de le
            // laisser apparaître d'un coup.
            .transition(.opacity)
            .task { await doorStore.refresh() }
        } else {
            stepContent
                .transition(.opacity)
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch viewModel.step {
        case .home:
            CineMatchHomeView(viewModel: viewModel, onProfileTap: { showProfile = true })
        case .want, .energy, .comparison, .loadingFive:
            CineMatchQuizView(viewModel: viewModel)
        case .five:
            CineMatchFiveView(viewModel: viewModel, mode: .five)
                // L'exposition s'accumule pendant qu'on fait défiler les cartes
                // et part d'un seul envoi quand on quitte les résultats.
                .onDisappear { Task { await viewModel.flushExposure() } }
        case .daily:
            CineMatchFiveView(viewModel: viewModel, mode: .daily)
                .onDisappear { Task { await viewModel.flushExposure() } }
        case .conclusion:
            CineMatchConclusionView(viewModel: viewModel)
        }
    }

    /// Recopie les plateformes de la bibliothèque dans la situation, sans
    /// toucher à la compagnie ni à la durée.
    private func syncPlatforms() {
        let ids = libraryStore.preferredPlatformIDs.sorted()
        guard viewModel.situation.platformIDs != ids else { return }
        var situation = viewModel.situation
        situation.platformIDs = ids
        viewModel.updateSituation(situation)
    }
}
