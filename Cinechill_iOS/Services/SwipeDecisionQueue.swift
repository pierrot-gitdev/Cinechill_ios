//
//  SwipeDecisionQueue.swift
//  Cinechill_iOS
//

import Foundation

/// Accumule les décisions de swipe et les envoie par paquets.
///
/// Un utilisateur swipe bien plus vite qu'un aller-retour réseau. Envoyer une
/// requête par carte ferait saccader le deck et multiplierait les écritures
/// Firestore ; on regroupe donc par petits lots, avec un envoi immédiat dès
/// qu'assez de décisions se sont accumulées. En cas d'échec le lot est remis en
/// tête de file plutôt que perdu : un « vu » qui disparaît, c'est un film que
/// l'utilisateur croit avoir ajouté à sa galerie et qu'il ne retrouvera pas.
actor SwipeDecisionQueue {
    private static let flushThreshold = 3
    private static let debounce = Duration.milliseconds(1500)
    private static let maxRetries = 4

    private let client: any SwipeFeedFetching
    private var pending: [PendingSwipe] = []
    /// Le paquet en cours d'envoi : parti, mais pas encore arrivé.
    private var sending: [PendingSwipe] = []
    private var flushTask: Task<Void, Never>?
    private var isFlushing = false
    private var consecutiveFailures = 0

    init(client: any SwipeFeedFetching) {
        self.client = client
    }

    func enqueue(_ swipe: PendingSwipe) {
        pending.append(swipe)
        // Un « vu » part tout de suite : c'est lui qui remplit la galerie, et
        // c'est sur la galerie écrite que se décident badges et distinctions.
        // Attendre le debounce reculait d'autant leur félicitation, qui
        // tombait alors sur une carte sans rapport. Les autres décisions
        // restent groupées.
        let urgent = swipe.decision == .seen || pending.count >= Self.flushThreshold
        scheduleFlush(after: urgent ? .zero : Self.debounce)
    }

    /// Ce que le serveur n'a peut-être pas encore reçu : le paquet en route
    /// et ce qui attend derrière lui. Le deck le joint à sa demande de lot,
    /// pour que les refus des dernières secondes comptent tout de suite.
    func undelivered() -> [PendingSwipe] {
        sending + pending
    }

    /// Vide la file sans attendre le debounce — à appeler quand le deck
    /// disparaît, pour ne rien laisser en suspens.
    func flush() async {
        flushTask?.cancel()
        flushTask = nil
        await performFlush()
    }

    private func scheduleFlush(after delay: Duration) {
        flushTask?.cancel()
        flushTask = Task { [weak self] in
            if delay > .zero {
                try? await Task.sleep(for: delay)
            }
            guard !Task.isCancelled else { return }
            await self?.performFlush()
        }
    }

    private func performFlush() async {
        guard !isFlushing, !pending.isEmpty else { return }
        isFlushing = true
        let batch = pending
        pending = []
        sending = batch

        do {
            try await client.record(batch)
            consecutiveFailures = 0
        } catch {
            pending.insert(contentsOf: batch, at: 0)
            consecutiveFailures += 1
        }

        sending = []
        isFlushing = false

        guard !pending.isEmpty else { return }
        if consecutiveFailures == 0 {
            // Des décisions sont arrivées pendant l'envoi.
            scheduleFlush(after: .zero)
        } else if consecutiveFailures <= Self.maxRetries {
            scheduleFlush(after: .seconds(1 << (consecutiveFailures - 1)))
        }
    }
}
