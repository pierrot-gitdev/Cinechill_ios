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

@Observable
@MainActor
final class SwipeDeckViewModel {
    /// En-dessous de ce nombre de cartes restantes, on va chercher le lot
    /// suivant — assez tôt pour que l'utilisateur n'attende jamais.
    private static let refillThreshold = 8
    /// Affiches préchargées d'avance.
    private static let prefetchDepth = 5
    /// Paliers qui déclenchent une célébration, en nombre d'ajouts de session.
    static let milestones = [10, 25, 50, 100]

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

    init(client: any SwipeFeedFetching = BackendSwipeFeedClient()) {
        self.client = client
        self.queue = SwipeDecisionQueue(client: client)
    }

    var topCard: SwipeCard? { cards.first }

    /// Les deux cartes visibles sous celle du dessus.
    var backingCards: [SwipeCard] { Array(cards.dropFirst().prefix(2)) }

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
        await loadMore()
    }

    private func loadMore() async {
        guard !isLoading else { return }
        isLoading = true
        let requested = format

        do {
            let batch = try await client.fetchFeed(excludedIDs: servedIDs, format: requested)
            guard requested == format else {
                // L'interrupteur a bougé pendant l'attente : ce lot n'est plus
                // le bon, et celui du nouveau format n'est pas encore parti.
                isLoading = false
                await loadMore()
                return
            }
            defer { isLoading = false }
            let fresh = batch.cards.filter {
                !servedSet.contains($0.id) && !libraryIDs.contains($0.id)
            }

            cards.append(contentsOf: fresh)
            servedIDs.append(contentsOf: fresh.map(\.id))
            servedSet.formUnion(fresh.map(\.id))
            errorMessage = nil

            // Un lot vide isolé peut n'être qu'un creux de l'algo ; deux
            // d'affilée veulent dire qu'il n'y a réellement plus rien à servir.
            emptyBatchStreak = fresh.isEmpty ? emptyBatchStreak + 1 : 0
            isExhausted = batch.exhausted || emptyBatchStreak >= 2

            prefetchUpcoming()
        } catch {
            isLoading = false
            if error is CancellationError { return }
            guard requested == format else {
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
        heldSwipe = PendingSwipe(card: card, decision: direction.decision, loved: loved)
        canUndo = true

        if direction.decision == .seen {
            addedThisSession += 1
            if sessionMilestonesEnabled, Self.milestones.contains(addedThisSession) {
                celebratedMilestone = addedThisSession
            }
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
}
