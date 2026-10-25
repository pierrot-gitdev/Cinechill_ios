//
//  ProbeGridSheet.swift
//  Cinechill_iOS
//

import SwiftUI

/// La mosaïque : neuf affiches, « lesquels as-tu vus ? ».
///
/// Neuf réponses en dix secondes apprennent au deck davantage que neuf
/// cartes, et chaque affiche touchée entre en galerie. Deux usages :
///
/// - **Au départ**, à la première venue sur Découvrir : trois grilles. La
///   première couvre neuf familles de films éloignées ; les suivantes
///   resserrent autour de ce qui a été touché. Le deck vise juste dès sa
///   première carte, au lieu de commencer par les films que tout le monde a
///   vus, qu'un goût pointu balaie à gauche.
/// - **En relance**, quand le deck ne trouve plus rien : une grille, et une
///   seconde vers les familles de niche si rien n'est touché, avec une
///   recherche pour nommer soi-même un film aimé.
///
/// Ce qui est touché part en « vu ». Ce qui ne l'est pas part en « pas vu » :
/// la question est « lesquels as-tu vus ? », et une affiche laissée vide y
/// répond. Envoyée comme un demi-« pas vu » qui n'écrivait rien, elle
/// revenait ensuite dans le deck de Découvrir. Un film cherché et touché part
/// en coup de cœur : on l'a cherché parce qu'on l'a aimé.
struct ProbeGridSheet: View {
    let kind: ProbeGridKind
    /// Ce qui est rangé ou déjà servi : rien de cela ne doit revenir ici.
    let excludedIDs: [String]
    /// Appelé à la fermeture, avec les familles des affiches touchées.
    /// Les familles des affiches touchées, et les films cochés : le deck
    /// propose ensuite le reste de leur saga.
    let onFinish: (Set<String>, [SwipeCard]) -> Void

    private let client: any SwipeFeedFetching = BackendSwipeFeedClient()

    @State private var stage: ProbeGridStage
    @State private var cards: [SwipeCard] = []
    @State private var searchResults: [SwipeCard] = []
    @State private var selection: Set<String> = []
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var isSearching = false
    @State private var errorMessage: String?
    /// Les affiches des grilles précédentes : elles ne reviennent pas.
    @State private var shownIDs: [String] = []
    @State private var tickedFamilies: Set<String> = []
    @State private var tickedCards: [SwipeCard] = []
    @State private var query = ""
    /// Le serveur sait déjà que la mosaïque de départ est faite.
    @State private var startGridMarked = false

    init(kind: ProbeGridKind, excludedIDs: [String], onFinish: @escaping (Set<String>, [SwipeCard]) -> Void) {
        self.kind = kind
        self.excludedIDs = excludedIDs
        self.onFinish = onFinish
        _stage = State(initialValue: kind == .start ? .start1 : .relance1)
    }

    private static let columns = Array(
        repeating: GridItem(.flexible(), spacing: 8, alignment: .top),
        count: 3
    )

    var body: some View {
        ZStack {
            Ink.ground.ignoresSafeArea()

            VStack(spacing: 0) {
                PlanHeader(
                    String(localized: "Lesquels as-tu vus ?", bundle: .app),
                    // La mosaïque de départ ne se ferme pas : « Aucun de
                    // ceux-là » fait avancer, et l'échec garde son « Fermer ».
                    leading: kind == .start ? .none : .close,
                    onLeading: close
                ) {
                    if let step {
                        PlanHeaderCount(value: step)
                    }
                }
                // En feuille, l'en-tête touchait presque le bord du haut. En
                // plein écran, la zone sûre fait déjà cet écart.
                .padding(.top, kind == .start ? 0 : 14)

                if isLoading {
                    loadingState
                } else if let errorMessage, cards.isEmpty {
                    failureState(errorMessage)
                } else {
                    content
                }
            }
        }
        .presentationDetents([.large])
        // Glisser la feuille vers le bas vaut « passer » : la fermeture passe
        // par `close`, qui le dit au serveur.
        .interactiveDismissDisabled()
        .task(id: stage) { await load() }
        .task(id: query) { await search() }
    }

    /// « 1 sur 3 » pour la mosaïque de départ. La relance n'a pas de compte :
    /// sa seconde grille n'existe que si la première ne donne rien.
    private var step: String? {
        let order: [ProbeGridStage] = [.start1, .start2, .start3]
        guard let index = order.firstIndex(of: stage) else { return nil }
        return String(localized: "\(index + 1) sur \(order.count)", bundle: .app)
    }

    private var isSearchStage: Bool { stage == .relance2 }

    /// Ce qui s'affiche : les résultats de la recherche quand il y en a une,
    /// sinon la grille.
    private var displayed: [SwipeCard] {
        isSearchStage && query.trimmingCharacters(in: .whitespaces).count >= 2
            ? searchResults : cards
    }

    // MARK: - Contenu

    private var content: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(introduction)
                        .planFont(12.5)
                        .foregroundStyle(Ink.ink2)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)

                    if isSearchStage {
                        HallSearchField(
                            placeholder: String(localized: "Un film que tu as aimé", bundle: .app),
                            text: $query,
                            isBusy: isSearching
                        )
                    }

                    if displayed.isEmpty, isSearchStage, !query.isEmpty, !isSearching, errorMessage == nil {
                        Text("Aucun film trouvé.", bundle: .app)
                            .planFont(12.5)
                            .foregroundStyle(Ink.ink3)
                            .padding(.top, 8)
                    } else {
                        LazyVGrid(columns: Self.columns, spacing: 8) {
                            ForEach(displayed) { card in
                                tile(card)
                            }
                        }
                    }

                    if let errorMessage {
                        HStack(alignment: .top, spacing: 11) {
                            PlanLight(tint: Ink.warn).padding(.top, 6)
                            Text(errorMessage)
                                .planFont(12.5)
                                .foregroundStyle(Ink.warn)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.horizontal, Metrics.margin)
                .padding(.vertical, 20)
            }
            .scrollDismissesKeyboard(.interactively)

            floor
        }
    }

    private var introduction: String {
        switch stage {
        case .start1, .start2, .start3:
            String(localized: "Touche ceux que tu as vus : on les range dans ta galerie et on te proposera des films proches.", bundle: .app)
        case .relance1:
            String(localized: "Tu as passé beaucoup de films d'affilée. Touche ceux que tu as vus ici, on cherchera de ce côté.", bundle: .app)
        case .relance2:
            String(localized: "Aucun de ceux-là non plus. Cherche un film que tu as aimé, ou touche ceux que tu connais.", bundle: .app)
        }
    }

    /// Une affiche à toucher. La sélection se dit à l'encre, comme dans la
    /// feuille de saga : un filet clair autour de l'affiche et une coche dans
    /// son coin. Le titre et l'année restent lisibles sous l'affiche, parce
    /// qu'une affiche étrangère ou ancienne ne se reconnaît pas toujours.
    private func tile(_ card: SwipeCard) -> some View {
        let isOn = selection.contains(card.id)
        return Button {
            guard !isSaving else { return }
            withAnimation(Metrics.shift) {
                if isOn {
                    selection.remove(card.id)
                } else {
                    selection.insert(card.id)
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                PosterFrame(posterPath: card.posterPath, title: card.title)
                    .overlay {
                        RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                            .strokeBorder(Ink.paper, lineWidth: isOn ? 2 : 0)
                    }
                    .overlay(alignment: .topTrailing) {
                        if isOn {
                            checkBadge
                                .padding(5)
                                .transition(.opacity)
                        }
                    }
                    .opacity(isOn || selection.isEmpty ? 1 : 0.72)

                VStack(alignment: .leading, spacing: 1) {
                    Text(card.title)
                        .planFont(11, weight: isOn ? .semibold : .regular)
                        .foregroundStyle(Ink.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(verbatim: card.displayYear)
                        .planFont(10.5)
                        .monospacedDigit()
                        // `ink3` ne descend pas sous 13 pt : l'année passe un
                        // cran plus haut, comme dans la feuille de saga.
                        .foregroundStyle(Ink.ink2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // Trois colonnes d'un tiers d'écran : au-delà du premier cran
                // des tailles d'accessibilité, le titre ne tiendrait plus que
                // par mots coupés. Le même plafond que les cartes du deck ;
                // VoiceOver lit le titre entier.
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableScaleStyle())
        .accessibilityElement(children: .ignore)
        // L'année inconnue se tait : VoiceOver lisait « tiret ».
        .accessibilityLabel(Text(verbatim: card.releaseDate.map { $0.count >= 4 } == true
                                 ? "\(card.title), \(card.displayYear)" : card.title))
        .accessibilityValue(isOn ? String(localized: "Coché", bundle: .app) : "")
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : [.isButton])
    }

    private var checkBadge: some View {
        ZStack {
            Circle().fill(Ink.paper)
            SagaCheckGlyph()
                .stroke(Ink.ground, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                .padding(6)
        }
        .frame(width: 22, height: 22)
    }

    // MARK: - Le plancher

    private var floor: some View {
        VStack(spacing: 0) {
            PlanEdge().padding(.bottom, 12)
            PlanButton(
                title: primaryTitle,
                loadingTitle: String(localized: "Enregistrement…", bundle: .app),
                isLoading: isSaving,
                isEnabled: !displayed.isEmpty || !selection.isEmpty,
                height: Metrics.control
            ) {
                Task { await submit() }
            }
        }
        .padding(.horizontal, Metrics.margin)
        .padding(.bottom, 8)
    }

    /// Le libellé dit ce qui va être écrit.
    private var primaryTitle: String {
        switch selection.count {
        case 0: String(localized: "Aucun de ceux-là", bundle: .app)
        case 1: String(localized: "Ajouter 1 film", bundle: .app)
        default: String(localized: "Ajouter \(selection.count) films", bundle: .app)
        }
    }

    // MARK: - États

    private var loadingState: some View {
        VStack(spacing: 14) {
            CinechillSpinner(size: 26)
            Text("Chargement…", bundle: .app)
                .planFont(12.5)
                .foregroundStyle(Ink.ink3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func failureState(_ message: String) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            PlanEmptyState(
                icon: .salle,
                title: String(localized: "Impossible de charger les films", bundle: .app),
                message: message,
                actionTitle: String(localized: "Réessayer", bundle: .app),
                action: { Task { await load() } },
                secondaryTitle: String(localized: "Fermer", bundle: .app),
                secondaryAction: close
            )
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 34)
    }

    // MARK: - Chargement et écriture

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let loaded = try await client.fetchProbeGrid(
                stage: stage, query: nil, excludedIDs: excludedIDs + shownIDs
            )
            cards = loaded
            selection = []
            PosterImageCache.shared.prefetch(loaded.map(\.posterURL))
            // Une grille vide n'a rien à demander : on passe à la suite.
            if loaded.isEmpty { await advance(tickedAny: false) }
        } catch is CancellationError {
            return
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    /// La recherche de la seconde relance, une fois la frappe posée.
    private func search() async {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard isSearchStage, text.count >= 2 else {
            searchResults = []
            return
        }
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        isSearching = true
        defer { isSearching = false }
        do {
            let found = try await client.fetchProbeGrid(
                stage: .relance2, query: text, excludedIDs: excludedIDs + shownIDs
            )
            guard !Task.isCancelled else { return }
            errorMessage = nil
            searchResults = found
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            // Hors ligne, la recherche répondait « Aucun film trouvé » : on dit
            // plutôt ce qui s'est passé, sous le champ.
            searchResults = []
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    /// Écrit la grille et passe à la suivante, ou referme.
    ///
    /// Chaque grille est écrite avant que la suivante soit demandée : c'est ce
    /// qu'elle vient d'apprendre au serveur qui fait la grille d'après.
    private func submit() async {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let searched = Set(searchResults.map(\.id))
        let pool = Dictionary((cards + searchResults).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let ticked = pool.values.filter { selection.contains($0.id) }
        // Seules les affiches proposées comptent comme passées : un résultat
        // de recherche qu'on ne touche pas ne dit rien.
        let untouched = cards.filter { !selection.contains($0.id) }
        let decisions = ticked.map {
            PendingSwipe(card: $0, decision: .seen, loved: searched.contains($0.id), via: .grid)
        } + untouched.map {
            PendingSwipe(card: $0, decision: .skipped, via: .grid)
        }

        let finishing = isLastStage(tickedAny: !ticked.isEmpty)
        do {
            try await client.record(decisions, startGridDone: finishing && kind == .start)
            if finishing, kind == .start { startGridMarked = true }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
            return
        }
        if !ticked.isEmpty { Haptics.success() }
        for card in ticked { tickedFamilies.formUnion(card.families) }
        tickedCards += ticked
        shownIDs.append(contentsOf: pool.keys)
        await advance(tickedAny: !ticked.isEmpty)
    }

    private func isLastStage(tickedAny: Bool) -> Bool {
        switch stage {
        case .start3, .relance2: true
        // La seconde relance n'a de sens que si la première n'a rien donné.
        case .relance1: tickedAny
        case .start1, .start2: false
        }
    }

    private func advance(tickedAny: Bool) async {
        if isLastStage(tickedAny: tickedAny) {
            // Une dernière grille vide termine aussi le départ, sans rien
            // avoir écrit : il faut le dire au serveur.
            markStartGridDone()
            onFinish(tickedFamilies, tickedCards)
            return
        }
        query = ""
        searchResults = []
        stage = switch stage {
        case .start1: .start2
        case .start2: .start3
        case .relance1: .relance2
        case .start3, .relance2: stage
        }
    }

    /// Fermer, c'est passer. Ce qui a déjà été touché est écrit ; la
    /// mosaïque de départ ne se rouvrira pas.
    private func close() {
        markStartGridDone()
        onFinish(tickedFamilies, tickedCards)
    }

    private func markStartGridDone() {
        guard kind == .start, !startGridMarked else { return }
        startGridMarked = true
        let client = client
        Task { try? await client.record([], startGridDone: true) }
    }
}
