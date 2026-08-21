//
//  RecommendationClient.swift
//  Cinechill_iOS
//

import Foundation
import FirebaseAuth

enum RecommendationClientError: LocalizedError {
    case missingBaseURL
    case invalidURL
    case notAuthenticated
    case transport(message: String)
    case httpStatus(code: Int, message: String?)
    case decoding(message: String)

    /// Les erreurs que le serveur identifie par un code, dites en français.
    private static func knownServerMessage(in body: String?) -> String? {
        guard let body else { return nil }
        if body.contains("no_candidates_in_requested_genres") {
            return String(localized: "Aucun film de ce genre ne correspond au reste de tes critères. Essaie un autre genre, ou plus de temps devant toi.", bundle: .app)
        }
        if body.contains("no_candidates_in_requested_origins") {
            return String(localized: "Aucun film de ces pays ne correspond au reste de tes critères. Essaie d'ajouter un pays, ou de changer de genre.", bundle: .app)
        }
        if body.contains("no_candidates_within_runtime") {
            return String(localized: "Aucun film ne tient dans ta soirée avec ces critères. Allonge la soirée ou change un critère.", bundle: .app)
        }
        if body.contains("no_candidates") {
            return String(localized: "Aucun film ne correspond à ces critères pour le moment.", bundle: .app)
        }
        return nil
    }

    var errorDescription: String? {
        switch self {
        case .missingBaseURL:
            return String(localized: "URL backend absente. Définis BACKEND_BASE_HOST dans Project.xcconfig.", bundle: .app)
        case .invalidURL:
            return String(localized: "URL backend invalide.", bundle: .app)
        case .notAuthenticated:
            return String(localized: "Tu dois être connecté(e) pour obtenir des recommandations.", bundle: .app)
        case .transport(let message):
            return String(localized: "Erreur réseau CinéMatch : \(message)", bundle: .app)
        case .httpStatus(let code, let message):
            // Les cas que le serveur sait nommer sont traduits ici. Le reste
            // garde le corps brut : il ne s'adresse plus à l'utilisateur mais à
            // qui lira le rapport de bug, et le tronquer nous priverait du seul
            // indice disponible.
            if let known = Self.knownServerMessage(in: message) {
                return known
            }
            if let message, !message.isEmpty {
                return String(localized: "CinéMatch (HTTP \(code)) : \(message)", bundle: .app)
            }
            return String(localized: "Erreur CinéMatch (HTTP \(code)).", bundle: .app)
        case .decoding(let message):
            return String(localized: "Impossible de lire la réponse CinéMatch. \(message)", bundle: .app)
        }
    }
}

nonisolated struct CandidatePoolResponse: Sendable {
    let candidates: [CandidateRow]
    let notice: String?
}

/// Les trois appels du moteur de préférence actif (voir la spec "moteur de préférence actif") —
/// remplacent l'ancien `fetchRecommendations` unique. Le pool circule dans les deux sens en JSON
/// brut plutôt que d'être re-dérivé côté serveur, pour que le client puisse le réduire localement
/// entre chaque appel sans repayer un aller-retour réseau par question.
protocol RecommendationFetching: Sendable {
    func fetchCandidatePool(trunk: QuestionnaireAnswers) async throws -> CandidatePoolResponse
    func enrichCandidates(_ candidates: [CandidateRow]) async throws -> [EnrichedCandidateRow]
    func finalizeRecommendations(
        answers: QuestionnaireAnswers, belief: BeliefState, candidates: [EnrichedCandidateRow]
    ) async throws -> [RecommendationResult]
    /// Le trait, tel que la bibliothèque le raconte. Ne lève jamais pour une
    /// bibliothèque vide : elle renvoie simplement un profil plat.
    func fetchTasteProfile() async throws -> TasteProfile
    /// Une correction posée sur la Fiche. `value` à `nil` la retire et rend l'axe
    /// à l'inférence.
    func setTasteCorrection(axis: Axis, value: Double?) async throws
    /// Le film qu'on est allé lancer parmi les trois proposés.
    func recordLaunch(tmdbID: Int) async throws
    /// Ce qu'il a laissé, à la question posée au retour.
    func recordVerdict(tmdbID: Int, verdict: FilmVerdict) async throws
    /// « Aucun des trois ne me tente » — l'échec du trio devient un signal
    /// au lieu de s'évaporer avec la séance.
    func recordRejection(tmdbIDs: [Int]) async throws
    /// « Ce n'est pas lui » — le refus du verdict, à la granularité du film.
    func recordPass(tmdbID: Int) async throws
    /// Les films de la Galerie, positionnés : la matière des duels entre
    /// films vus. Ne lève jamais pour une galerie pauvre — elle est courte.
    func fetchGalleryAxes() async throws -> [CandidateRow]
    /// Un duel tranché entre deux films vus : il s'écrit dans le graphe de
    /// préférence persistant, côté serveur.
    func recordFilmDuel(winnerID: Int, loserID: Int) async throws
    /// La passe de rattrapage : elle positionne les films déjà en galerie et
    /// transforme les « Je l'ai adoré » passés en coups de cœur. Rend `true`
    /// quand il ne reste plus rien à traiter.
    func backfillGallery() async throws -> Bool
}

nonisolated struct BackendRecommendationClient: RecommendationFetching, Sendable {
    func fetchCandidatePool(trunk: QuestionnaireAnswers) async throws -> CandidatePoolResponse {
        let data = try await post(to: APIEndpoints.candidatePool(), body: Self.requestBody(for: trunk))
        let decoded = try decode(CandidatePoolResponseDTO.self, from: data)
        return CandidatePoolResponse(
            candidates: decoded.candidates,
            notice: decoded.notice
        )
    }

    func enrichCandidates(_ candidates: [CandidateRow]) async throws -> [EnrichedCandidateRow] {
        guard !candidates.isEmpty else { return [] }
        let data = try await post(to: APIEndpoints.enrichCandidates(), body: [
            "candidates": candidates.map(\.jsonPayload),
        ])
        let decoded = try decode(EnrichCandidatesResponseDTO.self, from: data)
        return decoded.candidates
    }

    func fetchTasteProfile() async throws -> TasteProfile {
        let data = try await post(to: APIEndpoints.tasteProfile(), body: [:])
        let decoded = try decode(TasteProfileDTO.self, from: data)
        return decoded.profile
    }

    func setTasteCorrection(axis: Axis, value: Double?) async throws {
        _ = try await post(to: APIEndpoints.tasteCorrection(), body: [
            "axis": axis.rawValue,
            "value": value as Any,
        ])
    }

    func recordLaunch(tmdbID: Int) async throws {
        _ = try await post(to: APIEndpoints.sessionOutcome(), body: [
            "kind": "launch", "tmdbId": tmdbID,
        ])
    }

    func recordVerdict(tmdbID: Int, verdict: FilmVerdict) async throws {
        _ = try await post(to: APIEndpoints.sessionOutcome(), body: [
            "kind": "verdict", "tmdbId": tmdbID, "verdict": verdict.rawValue,
        ])
    }

    func recordRejection(tmdbIDs: [Int]) async throws {
        _ = try await post(to: APIEndpoints.sessionOutcome(), body: [
            "kind": "rejection", "tmdbIds": tmdbIDs,
        ])
    }

    func recordPass(tmdbID: Int) async throws {
        _ = try await post(to: APIEndpoints.sessionOutcome(), body: [
            "kind": "pass", "tmdbId": tmdbID,
        ])
    }

    func fetchGalleryAxes() async throws -> [CandidateRow] {
        let data = try await post(to: APIEndpoints.galleryAxes(), body: [:])
        let decoded = try decode(GalleryAxesResponseDTO.self, from: data)
        return decoded.candidates
    }

    func recordFilmDuel(winnerID: Int, loserID: Int) async throws {
        _ = try await post(to: APIEndpoints.filmDuel(), body: [
            "winnerTmdbId": winnerID, "loserTmdbId": loserID,
        ])
    }

    func backfillGallery() async throws -> Bool {
        let data = try await post(to: APIEndpoints.backfillGallery(), body: [:])
        return (try? decode(BackfillResponseDTO.self, from: data))?.done ?? true
    }

    /// Le partage du calcul : le client envoie ce qu'il croit savoir de la personne,
    /// le serveur reste seul à savoir où se situent les films. Une source de vérité par
    /// moitié, et aucune table d'axes à garder synchronisée entre les deux.
    func finalizeRecommendations(
        answers: QuestionnaireAnswers, belief: BeliefState, candidates: [EnrichedCandidateRow]
    ) async throws -> [RecommendationResult] {
        let data = try await post(to: APIEndpoints.finalizeRecommendations(), body: [
            "answers": Self.requestBody(for: answers),
            "belief": belief.jsonPayload,
            "candidates": candidates.map(\.jsonPayload),
        ])
        let decoded = try decode(FinalizeResponseDTO.self, from: data)
        return decoded.results.map(\.recommendationResult)
    }

    // MARK: - Wire helpers

    private func post(to url: URL?, body: [String: Any]) async throws -> Data {
        guard BackendConfiguration.baseURL != nil else {
            throw RecommendationClientError.missingBaseURL
        }
        guard let url else {
            throw RecommendationClientError.invalidURL
        }
        guard let user = Auth.auth().currentUser else {
            throw RecommendationClientError.notAuthenticated
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
            throw RecommendationClientError.transport(message: error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw RecommendationClientError.httpStatus(code: -1, message: nil)
        }
        guard (200...299).contains(http.statusCode) else {
            throw RecommendationClientError.httpStatus(code: http.statusCode, message: String(data: data, encoding: .utf8))
        }
        return data
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            let body = String(data: data, encoding: .utf8) ?? "<body non lisible>"
            throw RecommendationClientError.decoding(message: "\(error) · Réponse: \(body)")
        }
    }

    /// Contrat attendu côté backend — tout le mapping vers les paramètres TMDB
    /// (with_genres, with_watch_providers, mots-clés…) est fait côté Cloud Function.
    /// Réutilisé pour le socle (T1-T4, champs restants à leurs valeurs par défaut) comme pour
    /// l'ensemble des réponses collectées à la finalisation.
    static func requestBody(for answers: QuestionnaireAnswers) -> [String: Any] {
        [
            "contentFormat": answers.contentFormat?.rawValue as Any,
            "genres": answers.genres.map(\.rawValue).sorted(),
            "originCountries": answers.originCountries.map(\.rawValue).sorted(),
            "platformIds": answers.platformIDs.sorted(),
            "watchRegion": "FR",
            "audience": answers.audience?.rawValue as Any,
            "mood": answers.mood?.rawValue as Any,
            "origin": answers.origin.rawValue,
            "mindset": answers.mindset?.rawValue as Any,
            "dealbreaker": answers.dealbreaker?.rawValue as Any,
            "popularity": answers.popularity.rawValue,
            "cast": answers.cast.rawValue,
            "runtime": answers.runtime.rawValue,
            "era": answers.era.rawValue,
            "surpriseIntensity": answers.surpriseIntensity,
            "preferredGenreIds": Array(answers.preferredGenreIDs),
            "avoidedGenreIds": Array(answers.avoidedGenreIDs),
            // Les réponses de goût durable. Elles ne pèsent pas dans le score
            // du soir — la croyance les porte déjà — mais le serveur les range
            // dans l'historique pour que le trait s'en souvienne d'une séance
            // à l'autre. Sans ces lignes, elles s'évaporaient à la finalisation.
            "cognitiveMode": answers.cognitiveMode?.rawValue as Any,
            "storyOrigin": answers.storyOrigin?.rawValue as Any,
            "attachment": answers.attachment?.rawValue as Any,
            "creditsMoment": answers.creditsMoment?.rawValue as Any,
            "lastingTrace": answers.lastingTrace?.rawValue as Any,
        ]
    }
}

// MARK: - DTOs

/// `CandidateRow` se décode lui-même, champ manquant par champ manquant — il n'y a
/// donc plus de DTO intermédiaire à tenir à jour. C'est ce qui garantit que les axes
/// calculés par le serveur traversent la couche réseau au lieu d'être perdus par une
/// structure qui les ignore.
private struct CandidatePoolResponseDTO: Decodable, Sendable {
    let candidates: [CandidateRow]
    let notice: String?
}

private struct EnrichCandidatesResponseDTO: Decodable, Sendable {
    let candidates: [EnrichedCandidateRow]
}

private struct GalleryAxesResponseDTO: Decodable, Sendable {
    let candidates: [CandidateRow]
}

private struct BackfillResponseDTO: Decodable, Sendable {
    let done: Bool
}

private struct TasteProfileDTO: Decodable, Sendable {
    let mu: [String: Double]
    let tau: [String: Double]
    let galleryCount: Int
    let watchlistCount: Int
    let correctedAxes: [String]
    let verdictCount: Int?
    let pendingVerdict: PendingVerdictDTO?
    let door: DoorState?

    enum CodingKeys: String, CodingKey {
        case mu, tau, door
        case galleryCount = "gallery_count"
        case watchlistCount = "watchlist_count"
        case correctedAxes = "corrected_axes"
        case verdictCount = "verdict_count"
        case pendingVerdict = "pending_verdict"
    }

    var profile: TasteProfile {
        TasteProfile(
            mu: Dictionary(uniqueKeysWithValues: mu.compactMap { key, value in
                Axis(rawValue: key).map { ($0, value) }
            }),
            tau: Dictionary(uniqueKeysWithValues: tau.compactMap { key, value in
                Axis(rawValue: key).map { ($0, value) }
            }),
            galleryCount: galleryCount,
            watchlistCount: watchlistCount,
            correctedAxes: Set(correctedAxes.compactMap(Axis.init(rawValue:))),
            verdictCount: verdictCount ?? 0,
            pendingVerdict: pendingVerdict.map {
                PendingVerdict(tmdbID: $0.tmdbId, title: $0.title)
            },
            door: door
        )
    }
}

private struct PendingVerdictDTO: Decodable, Sendable {
    let tmdbId: Int
    let title: String?
}

private struct FinalizeResponseDTO: Decodable, Sendable {
    let results: [RecommendationRow]
}

private struct RecommendationRow: Decodable, Sendable {
    let id: Int
    let title: String
    let posterPath: String?
    let overview: String?
    let voteAverage: Double?
    let genreIds: [Int]?
    let releaseDate: String?
    let matchScore: Int
    let reasons: [String]
    let trailerKey: String?
    let providerIds: [Int]?

    enum CodingKeys: String, CodingKey {
        case id, title
        case posterPath = "poster_path"
        case overview
        case voteAverage = "vote_average"
        case genreIds = "genre_ids"
        case releaseDate = "release_date"
        case matchScore = "match_score"
        case reasons
        case trailerKey = "trailer_key"
        case providerIds = "provider_ids"
    }

    var recommendationResult: RecommendationResult {
        RecommendationResult(
            item: MediaItem(
                tmdbId: id,
                mediaType: .movie,
                title: title,
                posterPath: posterPath,
                overview: overview,
                voteAverage: voteAverage,
                // Le backend ne renvoie pas le nombre de votes sur ce contrat,
                // et le trio n'en a pas l'usage : c'est le mur de l'entrée qui
                // s'en sert, et il puise ailleurs.
                voteCount: nil,
                genreIds: genreIds ?? [],
                releaseDate: releaseDate
            ),
            matchScore: matchScore,
            reasons: reasons,
            trailerKey: trailerKey,
            providerIDs: providerIds ?? []
        )
    }
}
