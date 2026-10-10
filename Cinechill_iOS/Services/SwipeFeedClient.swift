//
//  SwipeFeedClient.swift
//  Cinechill_iOS
//

import Foundation
import FirebaseAuth

enum SwipeFeedClientError: LocalizedError {
    case missingBaseURL
    case invalidURL
    case notAuthenticated
    case transport(message: String)
    case httpStatus(code: Int, message: String?)
    case decoding(message: String)

    var errorDescription: String? {
        switch self {
        case .missingBaseURL:
            return String(localized: "URL backend absente. Définis BACKEND_BASE_HOST dans Project.xcconfig.", bundle: .app)
        case .invalidURL:
            return String(localized: "URL backend invalide.", bundle: .app)
        case .notAuthenticated:
            return String(localized: "Tu dois être connecté·e pour découvrir des films.", bundle: .app)
        case .transport(let message):
            return String(localized: "Erreur réseau : \(message)", bundle: .app)
        case .httpStatus(let code, let message):
            if let message, !message.isEmpty {
                return String(localized: "Erreur serveur (HTTP \(code)) : \(message)", bundle: .app)
            }
            return String(localized: "Erreur serveur (HTTP \(code)).", bundle: .app)
        case .decoding(let message):
            return String(localized: "Impossible de lire la réponse du serveur. \(message)", bundle: .app)
        }
    }
}

nonisolated struct SwipeFeedBatch: Sendable {
    let cards: [SwipeCard]
    /// Des cartes sûres, gardées de côté : l'app en pioche une quand la
    /// personne vient de refuser plusieurs films d'affilée.
    var reserve: [SwipeCard] = []
    /// Le backend n'a plus rien à proposer : tout est classé ou en cooldown.
    let exhausted: Bool
    /// La mosaïque de départ n'a pas encore été faite (ni passée).
    var needsStartGrid = false
}

/// Ce que le deck demande au serveur pour le lot suivant.
nonisolated enum DeckMode: String, Sendable {
    case normal
    /// Le rendement est tombé : le serveur ne sert plus que ce que la
    /// personne a de bonnes chances d'avoir vu.
    case recentrage
}

/// Les étapes des mosaïques « lesquels as-tu vus ? ».
nonisolated enum ProbeGridStage: String, Sendable, CaseIterable {
    case start1, start2, start3, relance1, relance2
}

/// La feuille à proposer après un « vu » : les autres films du réalisateur,
/// ou des films proches.
nonisolated struct DeckSheetOffer: Sendable, Hashable {
    enum Kind: String, Sendable, Hashable {
        case director
        case vein
    }

    let kind: Kind
    /// Le nom du réalisateur, pour la feuille du réalisateur.
    let name: String?
    let cards: [SwipeCard]
}

protocol SwipeFeedFetching: Sendable {
    /// - Parameters:
    ///   - excludedIDs: identités de cartes déjà servies dans la session
    ///     courante (`movie-603`, `tv-1399`), pour que deux lots consécutifs ne
    ///     se recouvrent pas.
    ///   - pending: décisions pas encore arrivées au serveur. Le lot en tient
    ///     compte : ce sont souvent elles qui ont fait demander un recentrage.
    ///   - fresh: refaire le vivier, après une mosaïque qui vient de beaucoup
    ///     apprendre au serveur.
    func fetchFeed(
        excludedIDs: [String],
        format: MediaFormat,
        pending: [PendingSwipe],
        mode: DeckMode,
        fresh: Bool
    ) async throws -> SwipeFeedBatch
    /// - Parameter startGridDone: la mosaïque de départ est faite ou passée ;
    ///   elle ne se rouvrira plus.
    func record(_ swipes: [PendingSwipe], startGridDone: Bool) async throws
    /// Les neuf affiches d'une mosaïque, ou les résultats d'une recherche.
    func fetchProbeGrid(stage: ProbeGridStage, query: String?, excludedIDs: [String]) async throws -> [SwipeCard]
    /// La feuille à proposer après un « vu », s'il y en a une.
    func fetchSheet(after tmdbID: Int, excludedIDs: [String]) async throws -> DeckSheetOffer?
}

extension SwipeFeedFetching {
    func record(_ swipes: [PendingSwipe]) async throws {
        try await record(swipes, startGridDone: false)
    }
}

nonisolated struct BackendSwipeFeedClient: SwipeFeedFetching, Sendable {
    func fetchFeed(
        excludedIDs: [String],
        format: MediaFormat,
        pending: [PendingSwipe],
        mode: DeckMode,
        fresh: Bool
    ) async throws -> SwipeFeedBatch {
        let (films, series) = Self.split(excludedIDs)
        let data = try await post(to: APIEndpoints.swipeFeed(), body: [
            "excludeIds": films,
            "excludeTvIds": series,
            // L'interrupteur Films · Séries : le serveur sert un lot de l'un
            // ou de l'autre, jamais des deux. Sans lui, des films seuls — ce
            // que les versions antérieures savent lire.
            "format": format == .series ? "tv" : "movie",
            "pending": pending.suffix(40).map(\.jsonPayload),
            "mode": mode.rawValue,
            "fresh": fresh,
        ])
        let decoded = try decode(SwipeFeedResponseDTO.self, from: data)
        return SwipeFeedBatch(
            cards: decoded.cards.map(\.swipeCard),
            reserve: (decoded.reserve ?? []).map(\.swipeCard),
            exhausted: decoded.exhausted ?? false,
            needsStartGrid: decoded.startGrid ?? false
        )
    }

    func record(_ swipes: [PendingSwipe], startGridDone: Bool) async throws {
        guard !swipes.isEmpty || startGridDone else { return }
        var body: [String: Any] = ["decisions": swipes.map(\.jsonPayload)]
        if startGridDone { body["startGridDone"] = true }
        _ = try await post(to: APIEndpoints.recordSwipes(), body: body)
    }

    func fetchProbeGrid(stage: ProbeGridStage, query: String?, excludedIDs: [String]) async throws -> [SwipeCard] {
        let (films, _) = Self.split(excludedIDs)
        var body: [String: Any] = ["stage": stage.rawValue, "excludeIds": films]
        if let query, !query.isEmpty { body["query"] = query }
        let data = try await post(to: APIEndpoints.probeGrid(), body: body)
        return try decode(SwipeFeedResponseDTO.self, from: data).cards.map(\.swipeCard)
    }

    func fetchSheet(after tmdbID: Int, excludedIDs: [String]) async throws -> DeckSheetOffer? {
        let (films, _) = Self.split(excludedIDs)
        let data = try await post(to: APIEndpoints.deckSheet(), body: [
            "tmdbId": tmdbID,
            "excludeIds": films,
        ])
        let decoded = try decode(DeckSheetDTO.self, from: data)
        guard let raw = decoded.kind, let kind = DeckSheetOffer.Kind(rawValue: raw),
              !decoded.cards.isEmpty else { return nil }
        return DeckSheetOffer(kind: kind, name: decoded.name, cards: decoded.cards.map(\.swipeCard))
    }

    /// Les identités de cartes, en deux listes d'identifiants TMDB : le
    /// serveur tient deux ensembles, parce que la série 1399 et le film 1399
    /// n'ont rien à voir. Le backend recharge la galerie à chaque appel :
    /// au-delà de quelques centaines d'ids la requête grossit pour rien, les
    /// plus récents suffisent à éviter les doublons de session.
    private static func split(_ ids: [String]) -> (films: [Int], series: [Int]) {
        let recent = ids.suffix(300)
        return (
            recent.compactMap { $0.hasPrefix("movie-") ? Int($0.dropFirst(6)) : nil },
            recent.compactMap { $0.hasPrefix("tv-") ? Int($0.dropFirst(3)) : nil }
        )
    }

    // MARK: - Wire helpers

    private func post(to url: URL?, body: [String: Any]) async throws -> Data {
        guard BackendConfiguration.baseURL != nil else {
            throw SwipeFeedClientError.missingBaseURL
        }
        guard let url else {
            throw SwipeFeedClientError.invalidURL
        }
        guard let user = Auth.auth().currentUser else {
            throw SwipeFeedClientError.notAuthenticated
        }
        let token = try await user.getIDToken()

        var request = await URLRequest(backend: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            if let urlError = error as? URLError, urlError.code == .cancelled {
                throw CancellationError()
            }
            if error is CancellationError { throw error }
            throw SwipeFeedClientError.transport(message: error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw SwipeFeedClientError.httpStatus(code: -1, message: nil)
        }
        guard (200...299).contains(http.statusCode) else {
            throw SwipeFeedClientError.httpStatus(
                code: http.statusCode,
                message: String(data: data, encoding: .utf8)
            )
        }
        return data
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            let body = String(data: data, encoding: .utf8) ?? "<body non lisible>"
            throw SwipeFeedClientError.decoding(message: "\(error) · Réponse: \(body)")
        }
    }
}

// MARK: - DTOs

private struct SwipeFeedResponseDTO: Decodable, Sendable {
    let cards: [SwipeCardDTO]
    let reserve: [SwipeCardDTO]?
    let exhausted: Bool?
    let startGrid: Bool?

    enum CodingKeys: String, CodingKey {
        case cards, reserve, exhausted
        case startGrid = "start_grid"
    }
}

private struct DeckSheetDTO: Decodable, Sendable {
    let kind: String?
    let name: String?
    let cards: [SwipeCardDTO]
}

private struct SwipeCardDTO: Decodable, Sendable {
    let id: Int
    let title: String?
    let overview: String?
    let posterPath: String?
    let voteAverage: Double?
    let voteCount: Int?
    let genreIds: [Int]?
    let releaseDate: String?
    let source: String?
    let collectionID: Int?
    let collectionTotal: Int?
    let mediaType: String?
    let seasonCount: Int?
    let originalLanguage: String?
    let pSeen: Double?
    let families: [String]?
    let kind: String?
    let lotID: String?
    let phase: String?
    let mode: String?
    let position: Int?

    enum CodingKeys: String, CodingKey {
        case id, title, overview, source, families, kind, phase, mode, position
        case mediaType = "media_type"
        case seasonCount = "season_count"
        case originalLanguage = "original_language"
        case pSeen = "p_seen"
        case lotID = "lot_id"
        case posterPath = "poster_path"
        case voteAverage = "vote_average"
        case voteCount = "vote_count"
        case genreIds = "genre_ids"
        case releaseDate = "release_date"
        case collectionID = "collection_id"
        case collectionTotal = "collection_total"
    }

    var swipeCard: SwipeCard {
        SwipeCard(
            tmdbId: id,
            title: title ?? String(localized: "Sans titre", bundle: .app),
            posterPath: posterPath,
            overview: overview,
            voteAverage: voteAverage,
            voteCount: voteCount,
            genreIds: genreIds ?? [],
            releaseDate: releaseDate,
            source: source,
            collectionID: collectionID,
            collectionCount: collectionTotal,
            mediaType: mediaType == MediaType.tv.rawValue ? .tv : .movie,
            seasonCount: seasonCount,
            originalLanguage: originalLanguage,
            // Les cartes de séries n'en portent pas : leur deck n'a pas de
            // modèle, et rien n'est à renvoyer.
            serving: lotID == nil ? nil : SwipeServing(
                pSeen: pSeen,
                families: families ?? [],
                kind: kind,
                lotID: lotID,
                phase: phase,
                mode: mode,
                position: position
            )
        )
    }
}
