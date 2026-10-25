//
//  SwipeDecisionQueue.swift
//  Cinechill_iOS
//

import Foundation
import Network

/// Accumule les décisions de swipe et les envoie par paquets.
///
/// Un utilisateur swipe bien plus vite qu'un aller-retour réseau. Envoyer une
/// requête par carte ferait saccader le deck et multiplierait les écritures
/// Firestore ; on regroupe donc par petits lots, avec un envoi immédiat dès
/// qu'assez de décisions se sont accumulées. En cas d'échec le lot est remis en
/// tête de file plutôt que perdu : un « vu » qui disparaît, c'est un film que
/// l'utilisateur croit avoir ajouté à sa galerie et qu'il ne retrouvera pas.
///
/// La file vit aussi sur le disque. Gardée en mémoire seule, elle mourait avec
/// l'app : dix « vu » balayés dans le métro, l'app tuée en arrière-plan, et
/// les dix films n'arrivaient jamais, toast « Ajouté à ta galerie » compris.
/// Chaque décision porte le compte qui l'a prise : elle ne part qu'avec lui,
/// jamais dans la galerie de celui qui se connecte ensuite.
actor SwipeDecisionQueue {
    private static let flushThreshold = 3
    private static let debounce = Duration.milliseconds(1500)
    /// Au-delà, la file attend un signal : une décision de plus, le retour
    /// au premier plan, le retour du réseau.
    private static let maxRetries = 8
    private static let maxBackoffSeconds = 60
    /// Ce que `recordSwipes` lit par appel. Le serveur tronque le reste sans
    /// erreur : on ne lui envoie donc jamais plus.
    private static let batchLimit = 40

    nonisolated struct Entry: Codable, Sendable {
        var id = UUID()
        let account: String
        let swipe: PendingSwipe
    }

    private let client: any SwipeFeedFetching
    private let accountID: @Sendable () -> String?
    private var pending: [Entry]
    /// Le paquet en cours d'envoi : parti, mais pas encore arrivé.
    private var sending: [Entry] = []
    private var flushTask: Task<Void, Never>?
    private var isFlushing = false
    private var consecutiveFailures = 0
    private let pathMonitor = NWPathMonitor()
    private var pathMonitorStarted = false

    init(
        client: any SwipeFeedFetching,
        accountID: @escaping @Sendable () -> String? = BackendSwipeFeedClient.currentAccountID
    ) {
        self.client = client
        self.accountID = accountID
        self.pending = Self.load()
    }

    deinit {
        pathMonitor.cancel()
    }

    func enqueue(_ swipe: PendingSwipe) {
        startPathMonitorIfNeeded()
        guard let account = accountID() else { return }
        pending.append(Entry(account: account, swipe: swipe))
        save()
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
        guard let account = accountID() else { return [] }
        return (sending + pending).filter { $0.account == account }.map(\.swipe)
    }

    /// Vide la file sans attendre le debounce — à appeler quand le deck
    /// disparaît, au retour au premier plan, ou pour reprendre après une
    /// série d'échecs.
    func flush() async {
        startPathMonitorIfNeeded()
        flushTask?.cancel()
        flushTask = nil
        consecutiveFailures = 0
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
        guard !isFlushing, let account = accountID() else { return }
        let mine = pending.filter { $0.account == account }
        guard !mine.isEmpty else { return }

        isFlushing = true
        let batch = Array(mine.prefix(Self.batchLimit))
        let batchIDs = Set(batch.map(\.id))
        pending.removeAll { batchIDs.contains($0.id) }
        sending = batch

        do {
            try await client.record(batch.map(\.swipe))
            consecutiveFailures = 0
        } catch {
            pending.insert(contentsOf: batch, at: 0)
            consecutiveFailures += 1
        }

        sending = []
        isFlushing = false
        save()

        guard let current = accountID(), pending.contains(where: { $0.account == current }) else { return }
        if consecutiveFailures == 0 {
            // Des décisions sont arrivées pendant l'envoi, ou le paquet
            // dépassait ce que le serveur lit en un appel.
            scheduleFlush(after: .zero)
        } else if consecutiveFailures <= Self.maxRetries {
            let seconds = min(1 << (consecutiveFailures - 1), Self.maxBackoffSeconds)
            scheduleFlush(after: .seconds(seconds))
        }
    }

    // MARK: - Le réseau

    /// Une file bloquée par une série d'échecs repart d'elle-même quand le
    /// réseau revient, sans attendre que la personne swipe de nouveau.
    private func startPathMonitorIfNeeded() {
        guard !pathMonitorStarted else { return }
        pathMonitorStarted = true
        pathMonitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { await self?.networkReturned() }
        }
        pathMonitor.start(queue: DispatchQueue(label: "SwipeDecisionQueue.path"))
    }

    private func networkReturned() {
        guard consecutiveFailures > 0, !isFlushing else { return }
        consecutiveFailures = 0
        scheduleFlush(after: .zero)
    }

    // MARK: - Le disque

    private static var fileURL: URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("SwipeDecisionQueue.json")
    }

    private static func load() -> [Entry] {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
    }

    /// Le paquet en route est écrit avec le reste : une app tuée pendant
    /// l'envoi le renverra au prochain lancement plutôt que de le perdre :
    /// mieux vaut une décision reçue deux fois qu'un film qui n'arrive pas.
    private func save() {
        guard let url = Self.fileURL else { return }
        let all = sending + pending
        do {
            if all.isEmpty {
                try? FileManager.default.removeItem(at: url)
                return
            }
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try JSONEncoder().encode(all).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            // Une écriture ratée laisse la file en mémoire : elle part quand même
            // tant que l'app vit.
        }
    }
}
