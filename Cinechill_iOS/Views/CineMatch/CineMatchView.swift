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
///
/// L'interrupteur Films · Séries est celui de Découvrir : le même réglage, lu
/// ici. Chaque format a sa Porte, et la franchir pour l'un ne l'ouvre pas pour
/// l'autre.
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

    @AppStorage(MediaFormat.storageKey) private var formatRaw = MediaFormat.film.rawValue

    @State private var showProfile = false
    @State private var showLovePicker = false
    @State private var showDoorComparison = false
    /// Les formats dont le seuil a été franchi **dans cette ouverture de
    /// l'app**. Volontairement un état de session et non une préférence
    /// gardée : la cérémonie se rejoue à chaque lancement, elle ne se consomme
    /// pas une fois pour toutes. Un par format : avoir franchi la Porte des
    /// films ne dispense pas de voir s'ouvrir celle des séries.
    @State private var crossedFormats: Set<MediaFormat> = []

    private var format: MediaFormat { MediaFormat(rawValue: formatRaw) ?? .film }

    /// La Porte du format courant.
    private var door: DoorState { doorStore.door(for: format) }

    /// Les cœurs comptés par la Porte affichée : des films, ou des saisons.
    private var lovedCount: Int {
        format == .series ? libraryStore.lovedSeasonCount : libraryStore.lovedCount
    }

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
                    target: door.artifact(.coeur)?.target ?? (format == .series ? 4 : 12),
                    format: format,
                    onClose: { showLovePicker = false }
                )
                .environmentObject(libraryStore)
            }
            .fullScreenCover(isPresented: $showDoorComparison) {
                CineMatchDoorComparisonView(format: format, onClose: { showDoorComparison = false })
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
        // L'interrupteur a pu basculer ici ou dans Découvrir : le parcours
        // repart sur l'autre profil.
        .onChange(of: formatRaw) { _, _ in
            viewModel.setFormat(format)
        }
        .task {
            viewModel.setFormat(format)
            syncPlatforms()
            handleDoorRequest()
        }
        // La planche d'une étape, affichée au-dessus de n'importe quel onglet,
        // envoie ici : montrer la Porte, ou ouvrir les comparaisons.
        .onChange(of: doorStore.request) { _, _ in
            handleDoorRequest()
        }
    }

    private func handleDoorRequest() {
        guard let request = doorStore.consumeRequest() else { return }
        // La planche parle d'une Porte précise : l'interrupteur la suit.
        if request.format != format { formatRaw = request.format.rawValue }
        if case .compare = request, doorStore.door(for: request.format).canCompare {
            showDoorComparison = true
        }
    }

    @ViewBuilder
    private var content: some View {
        // La porte garde l'onglet tant que le profil n'est pas prêt, et reste
        // une dernière fois pour l'ouverture : le seuil ne se franchit qu'en la
        // voyant céder. Elle ne peut s'interposer qu'à l'accueil, jamais au
        // milieu d'une recherche.
        if viewModel.step == .home && (!door.unlocked || !crossedFormats.contains(format)) {
            CineMatchGateView(
                door: door,
                isMeasured: doorStore.hasMeasured,
                lovedCount: lovedCount,
                onProfileTap: { showProfile = true },
                onDiscover: { selectedTab = 2 },
                onLovePicker: { showLovePicker = true },
                onCompare: { showDoorComparison = true },
                onEnter: {
                    let crossed = format
                    withAnimation(.easeOut(duration: 0.45)) { _ = crossedFormats.insert(crossed) }
                },
                isCelebrating: doorStore.celebration != nil
            )
            // Une Porte par format : basculer remonte l'écran, pour que la
            // cérémonie de l'autre Porte parte de zéro et non de l'état de
            // celle qu'on quitte.
            .id(format)
            // Le raccord : le travelling finit dans l'accueil au lieu de le
            // laisser apparaître d'un coup.
            .transition(.opacity)
            .task { await doorStore.refresh() }
        } else {
            // Les grandes étapes se relaient en fondu. Le `.transition` posé
            // sur le `switch` ne jouait jamais : rien n'animait le changement
            // d'étape, et chaque passage était une coupe sèche.
            ZStack {
                stepContent
                    .id(stage)
                    .transition(.opacity)
            }
            .animation(.easeOut(duration: 0.2), value: stage)
        }
    }

    /// Les écrans, regroupés : les questions s'enchaînent dans une même vue,
    /// qui ne doit pas se reconstruire d'une question à l'autre.
    private var stage: Int {
        switch viewModel.step {
        case .home: 0
        case .want, .energy, .comparison, .loadingFive: 1
        case .five: 2
        case .daily: 3
        case .conclusion: 4
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
