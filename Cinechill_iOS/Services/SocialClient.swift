//
//  SocialClient.swift
//  Cinechill_iOS
//

import Foundation
import FirebaseAuth

/// Les erreurs du Hall, nommées d'après ce que le serveur refuse réellement.
///
/// Chacune porte son propre message : « une erreur est survenue » ne dit ni
/// ce qui s'est passé, ni quoi faire. Les codes viennent tels quels des
/// Cloud Functions, ce qui garde les deux côtés lisibles ensemble.
enum SocialError: LocalizedError, Equatable {
    case notAuthenticated
    case missingBaseURL
    case handleTaken
    case handleChangeLimit
    case invalidHandle
    case ownProfileMissing
    case targetNotFound
    case notFollowing
    case notInGallery
    /// Le destinataire a vu le film entre l'affichage de la liste et l'envoi.
    case targetAlreadySeen
    case alreadySuggested
    case suggestionNotFound
    case server(code: String)
    case transport(message: String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return String(localized: "Vous devez être connecté.", bundle: .app)
        case .missingBaseURL:
            return String(localized: "Configuration serveur manquante.", bundle: .app)
        case .handleTaken:
            return String(localized: "Ce pseudo est déjà pris.", bundle: .app)
        case .handleChangeLimit:
            return String(localized: "Vous avez déjà changé de pseudo une fois.", bundle: .app)
        case .invalidHandle:
            return String(localized: "3 à 20 caractères : lettres, chiffres, point, tiret ou tiret bas.", bundle: .app)
        case .ownProfileMissing:
            return String(localized: "Choisissez d'abord un pseudo.", bundle: .app)
        case .targetNotFound:
            return String(localized: "Ce profil n'existe plus.", bundle: .app)
        case .notFollowing:
            return String(localized: "Vous ne suivez plus cette personne.", bundle: .app)
        case .notInGallery:
            return String(localized: "Vous ne pouvez recommander qu'un film que vous avez vu.", bundle: .app)
        case .targetAlreadySeen:
            return String(localized: "Cette personne a déjà vu ce film.", bundle: .app)
        case .alreadySuggested:
            return String(localized: "Vous lui avez déjà recommandé ce film.", bundle: .app)
        case .suggestionNotFound:
            return String(localized: "Cette recommandation n'existe plus.", bundle: .app)
        case .server(let code):
            return String(localized: "Le serveur a refusé la demande (\(code)).", bundle: .app)
        case .transport(let message):
            return message
        }
    }

    /// Traduit le code renvoyé par la Cloud Function en cas typé.
    static func from(code: String) -> SocialError {
        switch code {
        case "handle_taken": .handleTaken
        case "handle_change_limit": .handleChangeLimit
        case "invalid_handle": .invalidHandle
        case "own_profile_missing": .ownProfileMissing
        case "target_not_found": .targetNotFound
        case "not_following": .notFollowing
        case "not_in_gallery": .notInGallery
        case "target_already_seen": .targetAlreadySeen
        case "already_suggested": .alreadySuggested
        case "suggestion_not_found": .suggestionNotFound
        default: .server(code: code)
        }
    }
}

/// Ce dont les écrans du Hall ont besoin du backend. Un protocole plutôt
/// qu'un type concret : les vues d'aperçu et les tests n'ont pas à parler
/// au réseau pour se dessiner.
protocol SocialServicing: Sendable {
    /// Dit si `handle` est libre, sans le réserver. N'exige pas d'être
    /// connecté : à l'inscription, ce contrôle a lieu avant que le compte
    /// n'existe. `claimHandle` reste seul à trancher pour de bon — un pseudo
    /// dit libre ici peut être pris entretemps par un autre compte.
    func handleAvailability(_ handle: String) async throws -> Bool
    func claimHandle(_ handle: String) async throws
    func follow(uid: String) async throws
    func unfollow(uid: String) async throws
    func suggestionTargets(itemId: String) async throws -> [SuggestionTarget]
    func sendSuggestion(to uid: String, item: MediaItem) async throws
    /// Renvoie `true` si le film avait été vu entretemps — la recommandation
    /// est alors close sans rien ajouter à la watchlist.
    func respond(to suggestionId: String, accept: Bool) async throws -> Bool
    func publicProfileDetail(uid: String) async throws -> PublicProfileDetail
}

nonisolated struct SocialClient: SocialServicing, Sendable {
    func handleAvailability(_ handle: String) async throws -> Bool {
        guard let url = APIEndpoints.handleAvailable(handle: handle) else {
            throw SocialError.missingBaseURL
        }
        let data = try await get(from: url)
        return try JSONDecoder().decode(AvailabilityResponse.self, from: data).available
    }

    func claimHandle(_ handle: String) async throws {
        _ = try await post(to: APIEndpoints.claimHandle(), body: ["handle": handle])
    }

    func follow(uid: String) async throws {
        _ = try await post(to: APIEndpoints.followUser(), body: ["targetUid": uid])
    }

    func unfollow(uid: String) async throws {
        _ = try await post(to: APIEndpoints.unfollowUser(), body: ["targetUid": uid])
    }

    func suggestionTargets(itemId: String) async throws -> [SuggestionTarget] {
        let data = try await post(
            to: APIEndpoints.suggestionTargets(), body: ["itemId": itemId]
        )
        let decoded = try JSONDecoder().decode(TargetsResponse.self, from: data)
        return decoded.targets.map(\.target)
    }

    func sendSuggestion(to uid: String, item: MediaItem) async throws {
        _ = try await post(to: APIEndpoints.sendSuggestion(), body: [
            "targetUid": uid,
            "item": item.suggestionPayload,
        ])
    }

    func respond(to suggestionId: String, accept: Bool) async throws -> Bool {
        let data = try await post(to: APIEndpoints.respondToSuggestion(), body: [
            "suggestionId": suggestionId,
            "accept": accept,
        ])
        let decoded = try? JSONDecoder().decode(RespondResponse.self, from: data)
        return decoded?.alreadySeen ?? false
    }

    func publicProfileDetail(uid: String) async throws -> PublicProfileDetail {
        let data = try await post(
            to: APIEndpoints.publicProfile(), body: ["targetUid": uid]
        )
        return try JSONDecoder().decode(PublicProfileDetailDTO.self, from: data).detail
    }

    // MARK: - Transport

    /// Authentifiée : tout le Hall, à l'exception du contrôle de
    /// disponibilité, exige un compte déjà créé.
    @discardableResult
    private func post(to url: URL?, body: [String: Any]) async throws -> Data {
        guard BackendConfiguration.baseURL != nil else { throw SocialError.missingBaseURL }
        guard let url else { throw SocialError.missingBaseURL }
        guard let user = Auth.auth().currentUser else { throw SocialError.notAuthenticated }
        let token = try await user.getIDToken()

        var request = await URLRequest(backend: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await send(request)
    }

    /// Sans jeton : seul `handleAvailability` l'utilise, précisément parce
    /// qu'il doit répondre avant qu'un compte n'existe.
    private func get(from url: URL) async throws -> Data {
        guard BackendConfiguration.baseURL != nil else { throw SocialError.missingBaseURL }
        var request = await URLRequest(backend: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await send(request)
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            if error is CancellationError { throw error }
            if let urlError = error as? URLError, urlError.code == .cancelled {
                throw CancellationError()
            }
            throw SocialError.transport(message: error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw SocialError.transport(message: String(localized: "Réponse serveur illisible.", bundle: .app))
        }
        guard (200...299).contains(http.statusCode) else {
            // Le corps porte le code métier ; sans lui on ne peut rien dire de
            // plus précis que le statut HTTP.
            let payload = try? JSONDecoder().decode(ErrorResponse.self, from: data)
            throw SocialError.from(code: payload?.error ?? "http_\(http.statusCode)")
        }
        return data
    }
}

// MARK: - DTO

private nonisolated struct ErrorResponse: Decodable { let error: String }
private nonisolated struct AvailabilityResponse: Decodable { let available: Bool }
private nonisolated struct RespondResponse: Decodable { let alreadySeen: Bool? }
private nonisolated struct TargetsResponse: Decodable { let targets: [TargetDTO] }

private nonisolated struct PublicProfileDetailDTO: Decodable {
    let uid: String
    let handle: String?
    let displayName: String?
    let avatarURL: String?
    let badgeSignature: String?
    let followerCount: Int
    let followingCount: Int
    let galleryCount: Int
    let genres: [GenreShareDTO]
    let posters: [PosterDTO]

    nonisolated struct GenreShareDTO: Decodable {
        let id: Int
        let name: String
        let share: Double
    }

    nonisolated struct PosterDTO: Decodable {
        let posterPath: String?
        let title: String?
    }

    var detail: PublicProfileDetail {
        PublicProfileDetail(
            profile: PublicProfile(
                id: uid,
                handle: handle ?? "",
                displayName: displayName ?? handle ?? String(localized: "Sans nom", bundle: .app),
                avatarURL: avatarURL.flatMap(URL.init(string:)),
                badgeSignature: badgeSignature,
                followerCount: followerCount,
                followingCount: followingCount,
                galleryCount: galleryCount
            ),
            // `GenreShare` et sa palette viennent de la galerie : le même
            // graphique doit se lire pareil sur les deux écrans.
            genres: genres.enumerated().map { index, row in
                GenreShare(
                    id: row.id, name: row.name, share: row.share, colorIndex: index
                )
            },
            posters: posters.map {
                PublicPoster(posterPath: $0.posterPath, title: $0.title ?? "")
            }
        )
    }
}

private nonisolated struct TargetDTO: Decodable {
    let uid: String
    let handle: String?
    let displayName: String?
    let avatarURL: String?
    let alreadySeen: Bool
    let alreadySuggested: Bool
    let suggestedAt: String?

    var target: SuggestionTarget {
        SuggestionTarget(
            id: uid,
            handle: handle,
            displayName: displayName ?? handle ?? String(localized: "Sans nom", bundle: .app),
            avatarURL: avatarURL.flatMap(URL.init(string:)),
            alreadySeen: alreadySeen,
            alreadySuggested: alreadySuggested,
            suggestedAt: suggestedAt.flatMap {
                ISO8601DateFormatter().date(from: $0)
            }
        )
    }
}

extension MediaItem {
    /// Le format d'item attendu par `sendSuggestion`, identique à celui de
    /// `setMediaStatus` — un seul schéma de film sur toute la surface HTTP.
    var suggestionPayload: [String: Any] {
        [
            "id": id,
            "tmdbId": tmdbId,
            "mediaType": mediaType.rawValue,
            "title": title,
            "posterPath": posterPath as Any,
            "overview": overview as Any,
            "voteAverage": voteAverage as Any,
            "genreIds": genreIds,
            "releaseDate": releaseDate as Any,
        ]
    }
}
