//
//  SwipeDeckViewModel.swift
//  Cinechill_iOS
//

import Foundation

/// Les trois directions de swipe, et ce qu'elles veulent dire.
enum SwipeDirection {
    /// Droite — « je l'ai vu » : le film part en galerie.
    case right
    /// Gauche — « je ne l'ai pas vu » : mis en cooldown, il reviendra plus tard.
    case left
    /// Haut — « envie de le voir » : le film part en watchlist.
    case up

    var decision: SwipeDecision {
        switch self {
        case .right: .seen
        case .left: .skipped
        case .up: .watchlist
        }
    }
}

/// Quelle mosaïque ouvrir.
enum ProbeGridKind: Identifiable, Hashable {
    /// À la première venue sur Découvrir : trois grilles pour viser juste
    /// dès la première carte.
    case start
    /// Le deck ne trouve plus rien : une grille, deux si rien n'est coché.
    case relance

    var id: Self { self }
}

/// La feuille proposée après un « vu », avec le film qui l'a ouverte.
struct PendingDeckSheet: Equatable {
    let offer: DeckSheetOffer
    let originID: String
    let originTitle: String
}

@Observable
@MainActor
final class SwipeDeckViewModel {
    /// En dessous de ce nombre de cartes restantes, on va chercher le lot
    /// suivant. Un lot fait dix cartes : on le demande assez tôt pour que
    /// l'utilisateur n'attende jamais, assez tard pour qu'il tienne compte
    /// des dernières réponses.
    private static let refillThreshold = 4
    /// Affiches préchargées d'avance.
    private static let prefetchDepth = 5
    /// Paliers qui déclenchent une célébration, en nombre d'ajouts de session.
    static let milestones = [10, 25, 50, 100]

    // MARK: Garde-fous

    /// Refus d'affilée après lesquels une carte de réserve passe devant.
    /// Elle est posée derrière la carte suivante, déjà dessinée sous celle du
    /// dessus : trois refus, et la quatrième carte est sûre.
    private static let streakBeforeReserve = 2
    /// Une carte de réserve à peine probable ne protège de rien.
    private static let reserveMinPSeen = 0.45
    /// Sous ce rendement sur dix cartes, le deck se recentre ; il en sort
    /// au-dessus du second.
    private static let recentrageBelow = 0.45
    private static let recentrageExitAt = 0.55
    /// Au plus trois « vu » sur quinze cartes : la mosaïque de relance.
    private static let relanceWindow = 15
    private static let relanceMaxSeen = 3
    /// Cartes entre deux feuilles « dans la même veine ».
    private static let sheetSpacing = 10

    private let client: any SwipeFeedFetching
    private let queue: SwipeDecisionQueue

    /// Le deck, carte du dessus en premier.
    private(set) var cards: [SwipeCard] = []
    private(set) var isLoading = false
    private(set) var isExhausted = false
    private(set) var errorMessage: String?
    /// Films marqués « vu » depuis l'ouverture de l'onglet.
    private(set) var addedThisSession = 0
    /// Palier tout juste franchi, à célébrer puis à remettre à `nil`.
    var celebratedMilestone: Int?
    /// Les paliers de session ne parlent qu'une fois CinéMatch ouvert. Avant,
    /// c'est la vue qui fête la galerie entière, rapportée aux films qui
    /// ouvrent CinéMatch : « 50 films ajoutés » dans la session ne disait pas
    /// où l'on en était.
    var sessionMilestonesEnabled = true
    private(set) var canUndo = false
    /// Films ou séries : le profil que le deck remplit en ce moment.
    private(set) var format: MediaFormat = .film
    /// Normal, ou recentré sur ce que la personne a de bonnes chances
    /// d'avoir vu.
    private(set) var mode: DeckMode = .normal
    /// La mosaïque à ouvrir. La vue la présente, puis la remet à `nil`.
    var gridRequest: ProbeGridKind?
    /// La feuille à proposer après un « vu ». La vue la présente, puis la
    /// remet à `nil`.
    var pendingSheet: PendingDeckSheet?

    /// Décision de la dernière carte, gardée en main tant que l'utilisateur
    /// n'a pas swipé la suivante : c'est ce qui rend le retour arrière toujours
    /// possible, sans avoir à défaire une écriture déjà partie.
    private var heldSwipe: PendingSwipe?
    private var servedIDs: [String] = []
    private var servedSet: Set<String> = []
    /// Ce que l'utilisateur a déjà en galerie ou en watchlist, tenu à jour par
    /// la vue. Le backend filtre déjà, mais il peut ignorer un ajout fait à
    /// l'instant depuis un autre onglet.
    private var libraryIDs: Set<String> = []
    private var emptyBatchStreak = 0

    /// Les cartes sûres du dernier lot, gardées de côté.
    private var reserve: [SwipeCard] = []
    /// Les cartes de réserve passées dans le deck : leur décision le dit.
    private var reserveIDs: Set<String> = []
    /// Les dernières issues du deck dans la session, la plus récente à la fin.
    private var outcomes: [DeckOutcome] = []
    /// Les familles où la personne a dit « vu » pendant la session. Trois
    /// refus d'affilée dans l'une d'elles sont de la malchance : la réserve
    /// ne les saute pas.
    private var seenFamilies: Set<String> = []
    private var relanceUsed = false
    private var startGridOffered = false
    private var cardsSinceSheet = 0
    /// Le prochain lot demande un vivier neuf.
    private var freshNext = false
    /// Change à chaque bascule qui rend caduc un lot en route : format, mode,
    /// mosaïque. Un lot qui revient sous une autre génération est jeté.
    private var generation = 0

    init(client: any SwipeFeedFetching = BackendSwipeFeedClient()) {
        self.client = client
        self.queue = SwipeDecisionQueue(client: client)
    }

    var topCard: SwipeCard? { cards.first }

    /// Les deux cartes visibles sous celle du dessus.
    var backingCards: [SwipeCard] { Array(cards.dropFirst().prefix(2)) }

    /// Ce qui ne doit pas revenir dans une mosaïque ou une feuille : ce qui
    /// est rangé, et ce que le deck a déjà servi.
    var knownIDs: [String] { Array(libraryIDs) + servedIDs }

    // MARK: - Chargement

    func start() async {
        guard cards.isEmpty else {
            await refillIfNeeded()
            return
        }
        await loadMore()
    }

    func retry() async {
        errorMessage = nil
        isExhausted = false
        emptyBatchStreak = 0
        await loadMore()
    }

    /// Relance depuis zéro quand le deck s'est vidé : le backend a pu changer
    /// d'avis entre-temps (nouveaux ajouts en galerie, cooldowns expirés).
    func restart() async {
        servedIDs = []
        servedSet = []
        emptyBatchStreak = 0
        isExhausted = false
        errorMessage = nil
        await loadMore()
    }

    /// - Parameter ids: identités de cartes déjà rangées (`movie-603`,
    ///   `tv-1399` dès qu'une saison de la série est rangée).
    func syncLibrary(_ ids: Set<String>) {
        libraryIDs = ids
        // Une carte peut avoir été classée ailleurs pendant que le deck est
        // ouvert : on la retire plutôt que de la faire trancher deux fois.
        let stale = cards.filter { ids.contains($0.id) && $0.id != heldSwipe?.card.id }
        guard !stale.isEmpty else { return }
        cards.removeAll { card in stale.contains(where: { $0.id == card.id }) }
    }

    private func refillIfNeeded() async {
        guard cards.count <= Self.refillThreshold, !isLoading, !isExhausted else { return }
        await loadMore()
    }

    /// Le format avant le premier chargement, sans rien charger : l'onglet
    /// s'ouvre directement sur le dernier format choisi.
    func prepare(format: MediaFormat) {
        guard cards.isEmpty, !isLoading else { return }
        self.format = format
    }

    /// L'interrupteur a basculé : le deck repart de zéro sur l'autre profil.
    /// La décision en main part d'abord, elle appartient au lot qu'on quitte.
    /// Un chargement encore en route pour l'ancien format est jeté à son
    /// retour, et le nouveau part derrière lui.
    func setFormat(_ newFormat: MediaFormat) async {
        guard newFormat != format else { return }
        commitHeldSwipe()
        format = newFormat
        // Les paliers comptent un seul format : dix films puis trois séries
        // ne font pas « 13 séries ajoutées ».
        addedThisSession = 0
        cards = []
        servedIDs = []
        servedSet = []
        emptyBatchStreak = 0
        isExhausted = false
        errorMessage = nil
        resetGuards()
        generation &+= 1
        await loadMore()
    }

    private func loadMore() async {
        guard !isLoading else { return }
        isLoading = true
        let requested = format
        let requestedGeneration = generation
        let wantsFreshPool = freshNext

        do {
            // Ce qui n'est pas encore arrivé au serveur part avec la demande :
            // la décision en main, et la file.
            var pending = await queue.undelivered()
            if let heldSwipe { pending.append(heldSwipe) }
            let batch = try await client.fetchFeed(
                excludedIDs: servedIDs,
                format: requested,
                pending: requested == .film ? pending : [],
                mode: mode,
                fresh: wantsFreshPool
            )
            guard requested == format, requestedGeneration == generation else {
                // L'interrupteur, le mode ou une mosaïque a changé la donne
                // pendant l'attente : ce lot n'est plus le bon.
                isLoading = false
                await loadMore()
                return
            }
            defer { isLoading = false }
            if wantsFreshPool { freshNext = false }
            let fresh = batch.cards.filter {
                !servedSet.contains($0.id) && !libraryIDs.contains($0.id)
            }

            cards.append(contentsOf: fresh)
            servedIDs.append(contentsOf: fresh.map(\.id))
            servedSet.formUnion(fresh.map(\.id))
            // La réserve est servie, elle aussi : le serveur ne doit pas la
            // reproposer dans le lot suivant.
            reserve = batch.reserve.filter {
                !servedSet.contains($0.id) && !libraryIDs.contains($0.id)
            }
            servedIDs.append(contentsOf: reserve.map(\.id))
            servedSet.formUnion(reserve.map(\.id))
            errorMessage = nil

            // Un lot vide isolé peut n'être qu'un creux de l'algo ; deux
            // d'affilée veulent dire qu'il n'y a réellement plus rien à servir.
            emptyBatchStreak = fresh.isEmpty ? emptyBatchStreak + 1 : 0
            isExhausted = batch.exhausted || emptyBatchStreak >= 2

            // La mosaïque de départ : une fois par session au plus, et le
            // serveur ne la demande plus une fois faite ou passée.
            if batch.needsStartGrid, requested == .film, !startGridOffered, gridRequest == nil {
                startGridOffered = true
                gridRequest = .start
            }

            prefetchUpcoming()
        } catch {
            isLoading = false
            if error is CancellationError { return }
            guard requested == format, requestedGeneration == generation else {
                await loadMore()
                return
            }
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    private func prefetchUpcoming() {
        PosterImageCache.shared.prefetch(
            cards.prefix(Self.prefetchDepth).map(\.posterURL)
        )
    }

    // MARK: - Décisions

    func swipe(_ direction: SwipeDirection, loved: Bool = false) {
        guard let card = cards.first else { return }
        cards.removeFirst()

        commitHeldSwipe()
        heldSwipe = PendingSwipe(
            card: card,
            decision: direction.decision,
            loved: loved,
            via: reserveIDs.contains(card.id) ? .reserve : .deck
        )
        canUndo = true

        if direction.decision == .seen {
            addedThisSession += 1
            if sessionMilestonesEnabled, Self.milestones.contains(addedThisSession) {
                celebratedMilestone = addedThisSession
            }
        }

        if format == .film, !card.isSeries {
            applyGuards(after: card, decision: direction.decision)
            offerSheetIfAny(after: card, decision: direction.decision)
        }

        prefetchUpcoming()
        Task { await refillIfNeeded() }
    }

    /// La carte rangée « vu » qui n'est pas encore partie au serveur : la
    /// galerie ne la compte pas encore, l'écran si.
    var heldSeenCard: SwipeCard? {
        guard let held = heldSwipe, held.decision == .seen else { return nil }
        return held.card
    }

    func undo() {
        guard let held = heldSwipe else { return }
        heldSwipe = nil
        canUndo = false
        cards.insert(held.card, at: 0)

        if held.decision == .seen {
            addedThisSession = max(0, addedThisSession - 1)
        }
        // La décision annulée ne compte plus pour les garde-fous.
        if outcomes.last?.cardID == held.card.id {
            outcomes.removeLast()
        }
    }

    /// Envoie tout ce qui reste en attente — à appeler quand l'onglet est
    /// quitté, sans quoi la dernière décision resterait en main.
    func flushPending() async {
        commitHeldSwipe()
        await queue.flush()
    }

    private func commitHeldSwipe() {
        guard let held = heldSwipe else { return }
        heldSwipe = nil
        canUndo = false
        Task { await queue.enqueue(held) }
    }

    // MARK: - Les garde-fous

    /// Ce que le deck fait d'une série de refus, du plus léger au plus fort :
    ///
    /// 1. Deux refus d'affilée : une carte de réserve se place derrière la
    ///    carte suivante. Au troisième refus, la personne retombe sur un film
    ///    qu'elle a de bonnes chances de connaître.
    /// 2. Moins de 45 % de « vu » sur dix cartes : les cartes en attente
    ///    partent, et le lot suivant ne sert plus que ce qui a de bonnes
    ///    chances d'être vu. On en sort au-dessus de 55 %.
    /// 3. Trois « vu » ou moins sur quinze cartes : la mosaïque de relance,
    ///    une fois par session.
    ///
    /// Les seuils sont posés à l'estime ; le journal du serveur dira s'ils
    /// tiennent.
    private func applyGuards(after card: SwipeCard, decision: SwipeDecision) {
        // Un « à voir » n'est pas une carte perdue : il compte comme un « vu ».
        let seen = decision != .skipped
        outcomes.append(DeckOutcome(cardID: card.id, seen: seen, families: card.families))
        if outcomes.count > Self.relanceWindow { outcomes.removeFirst() }
        if seen { seenFamilies.formUnion(card.families) }

        let lastFifteen = outcomes.suffix(Self.relanceWindow)
        if !relanceUsed, lastFifteen.count == Self.relanceWindow,
           lastFifteen.filter(\.seen).count <= Self.relanceMaxSeen {
            relanceUsed = true
            gridRequest = .relance
            return
        }

        if let rolling = rollingYield {
            if mode == .normal, rolling < Self.recentrageBelow {
                switchMode(to: .recentrage)
                return
            }
            if mode == .recentrage, rolling >= Self.recentrageExitAt {
                // Pas de coupe en sortie : les cartes recentrées en attente
                // sont de bonnes cartes, elles restent.
                mode = .normal
            }
        }

        let streak = outcomes.suffix(Self.streakBeforeReserve)
        if streak.count == Self.streakBeforeReserve, streak.allSatisfy({ !$0.seen }) {
            placeReserveCard()
        }
    }

    /// Part de « vu » sur les dix dernières cartes, `nil` avant dix cartes.
    private var rollingYield: Double? {
        guard outcomes.count >= 10 else { return nil }
        let last = outcomes.suffix(10)
        return Double(last.filter(\.seen).count) / 10
    }

    /// Place une carte de réserve derrière la carte suivante.
    ///
    /// La carte suivante est déjà dessinée sous celle du dessus, en pleine
    /// opacité : la remplacer ferait changer un film sous les yeux. La réserve
    /// prend donc la place d'après.
    ///
    /// Elle saute les familles qu'on vient de refuser, sauf celles où la
    /// personne a déjà dit « vu » pendant la session.
    private func placeReserveCard() {
        let upcoming = cards.prefix(2)
        guard !upcoming.contains(where: { reserveIDs.contains($0.id) }) else { return }
        let refused = Set(outcomes.suffix(3).filter { !$0.seen }.flatMap(\.families))
            .subtracting(seenFamilies)
        guard let index = reserve.firstIndex(where: { candidate in
            (candidate.pSeen ?? 0) >= Self.reserveMinPSeen
                && refused.isDisjoint(with: candidate.families)
                && !libraryIDs.contains(candidate.id)
                && !cards.contains(where: { $0.id == candidate.id })
        }) else { return }
        let card = reserve.remove(at: index)
        reserveIDs.insert(card.id)
        cards.insert(card, at: min(1, cards.count))
        prefetchUpcoming()
    }

    /// Change de mode et redemande un lot. Les deux cartes déjà visibles
    /// restent ; les autres repartent, et pourront revenir plus tard.
    private func switchMode(to newMode: DeckMode) {
        mode = newMode
        dropQueuedCards(keeping: 2)
        generation &+= 1
        Task { await loadMore() }
    }

    /// Retire les cartes en attente au-delà des premières, et les rend au
    /// serveur : elles n'ont pas été vues, elles peuvent revenir.
    private func dropQueuedCards(keeping kept: Int) {
        let dropped = cards.dropFirst(kept).map(\.id)
        guard !dropped.isEmpty else { return }
        cards = Array(cards.prefix(kept))
        let droppedSet = Set(dropped)
        servedIDs.removeAll { droppedSet.contains($0) }
        servedSet.subtract(droppedSet)
    }

    private func resetGuards() {
        outcomes = []
        seenFamilies = []
        reserve = []
        reserveIDs = []
        mode = .normal
        cardsSinceSheet = 0
        pendingSheet = nil
    }

    // MARK: - Les mosaïques

    /// Une mosaïque vient de se refermer. Elle a beaucoup appris au serveur :
    /// le deck repart d'un vivier neuf, en gardant la carte du dessus.
    ///
    /// - Parameter seenFamilies: familles des affiches touchées.
    func gridDidFinish(seenFamilies families: Set<String>) {
        seenFamilies.formUnion(families)
        outcomes = []
        mode = .normal
        freshNext = true
        dropQueuedCards(keeping: 1)
        generation &+= 1
        Task { await loadMore() }
    }

    // MARK: - Les feuilles

    /// Après un « vu », toutes les dix cartes au plus, la feuille des autres
    /// films du réalisateur ou des films proches. Pas après un film de saga :
    /// la feuille de saga passe devant.
    private func offerSheetIfAny(after card: SwipeCard, decision: SwipeDecision) {
        cardsSinceSheet += 1
        guard decision == .seen, !card.hasSagaToOffer,
              cardsSinceSheet >= Self.sheetSpacing else { return }
        cardsSinceSheet = 0
        let excluded = knownIDs + cards.map(\.id)
        let origin = card
        Task {
            guard let offer = try? await client.fetchSheet(after: origin.tmdbId, excludedIDs: excluded),
                  pendingSheet == nil else { return }
            pendingSheet = PendingDeckSheet(
                offer: offer,
                originID: origin.mediaItem.id,
                originTitle: origin.title
            )
        }
    }
}

/// Une issue du deck, telle que les garde-fous la retiennent.
private struct DeckOutcome {
    let cardID: String
    let seen: Bool
    let families: [String]
}
