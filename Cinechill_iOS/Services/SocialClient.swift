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
    /// Plus de trente recommandations dans la journée : le serveur s'arrête là.
    case dailyLimit
    case suggestionNotFound
    /// Plus de vingt signalements dans la journée. Le serveur renvoie le même
    /// `daily_limit` que pour les recommandations : `report` le traduit, pour
    /// que le message parle de signalements et non de films envoyés.
    case reportLimit
    case server(code: String)
    case transport(message: String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            // Pas d'écriture inclusive au point médian : la tournure à
            // l'impératif évite d'accorder.
            return String(localized: "Connecte-toi pour continuer.", bundle: .app)
        case .missingBaseURL:
            return String(localized: "Configuration serveur manquante.", bundle: .app)
        case .handleTaken:
            return String(localized: "Ce pseudo est déjà pris.", bundle: .app)
        case .handleChangeLimit:
            return String(localized: "Tu as déjà changé de pseudo une fois.", bundle: .app)
        case .invalidHandle:
            return String(localized: "3 à 20 caractères : lettres, chiffres, point, tiret ou tiret bas.", bundle: .app)
        case .ownProfileMissing:
            return String(localized: "Choisis d'abord un pseudo.", bundle: .app)
        case .targetNotFound:
            return String(localized: "Ce profil n'est pas accessible.", bundle: .app)
        case .notFollowing:
            return String(localized: "Tu ne suis plus cette personne.", bundle: .app)
        case .notInGallery:
            return String(localized: "Tu ne peux recommander qu'un film que tu as vu.", bundle: .app)
        case .targetAlreadySeen:
            return String(localized: "Cette personne a déjà vu ce film.", bundle: .app)
        case .alreadySuggested:
            return String(localized: "Tu lui as déjà recommandé ce film.", bundle: .app)
        case .dailyLimit:
            return String(localized: "Tu as envoyé beaucoup de recommandations aujourd'hui. Réessaie demain.", bundle: .app)
        case .suggestionNotFound:
            return String(localized: "Cette recommandation n'existe plus.", bundle: .app)
        case .reportLimit:
            return String(localized: "Tu as fait beaucoup de signalements aujourd'hui. Réessaie demain.", bundle: .app)
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
        case "daily_limit": .dailyLimit
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
    /// Écrit le nom public et ses préfixes de recherche. Exige un pseudo.
    func setPublicName(_ name: String) async throws
    func followSuggestions() async throws -> FollowSuggestionsPage
    /// Retire un profil des propositions, pour de bon.
    func dismissFollowSuggestion(uid: String) async throws
    /// Bloque un profil. Le serveur défait les abonnements dans les deux sens
    /// et supprime les recommandations en attente entre les deux comptes.
    /// Idempotent.
    func block(uid: String) async throws
    /// Ne rétablit aucun abonnement.
    func unblock(uid: String) async throws
    /// Les comptes que j'ai bloqués. Un compte supprimé n'y figure plus.
    func blockedUsers() async throws -> [PublicProfile]
    func report(uid: String, reason: ReportReason, note: String?, context: ReportContext?) async throws
}

/// Pourquoi on signale un profil. Les valeurs brutes sont celles qu'attend
/// `reportUser` : les renommer casserait le contrat.
nonisolated enum ReportReason: String, CaseIterable, Identifiable, Sendable {
    case spam
    case offensive
    case impersonation
    case other

    var id: String { rawValue }
}

/// Ce qu'on regardait au moment du signalement, quand il part d'une
/// recommandation : la personne qui modère sait alors quoi ouvrir.
nonisolated struct ReportContext: Hashable, Sendable {
    var suggestionId: String?
    var itemId: String?

    var payload: [String: String] {
        var out: [String: String] = [:]
        if let suggestionId { out["suggestionId"] = suggestionId }
        if let itemId { out["itemId"] = itemId }
        return out
    }
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

    func setPublicName(_ name: String) async throws {
        _ = try await post(to: APIEndpoints.setPublicName(), body: ["displayName": name])
    }

    func followSuggestions() async throws -> FollowSuggestionsPage {
        let data = try await post(to: APIEndpoints.followSuggestions(), body: [:])
        return try JSONDecoder().decode(FollowSuggestionsDTO.self, from: data).page
    }

    func dismissFollowSuggestion(uid: String) async throws {
        _ = try await post(to: APIEndpoints.dismissFollowSuggestion(), body: ["targetUid": uid])
    }

    // MARK: - Blocage et signalement

    func block(uid: String) async throws {
        _ = try await post(to: APIEndpoints.blockUser(), body: ["targetUid": uid])
    }

    func unblock(uid: String) async throws {
        _ = try await post(to: APIEndpoints.unblockUser(), body: ["targetUid": uid])
    }

    func blockedUsers() async throws -> [PublicProfile] {
        let data = try await post(to: APIEndpoints.blockedUsers(), body: [:])
        return try JSONDecoder().decode(BlockedUsersDTO.self, from: data).profiles
    }

    func report(uid: String, reason: ReportReason, note: String?, context: ReportContext?) async throws {
        var body: [String: Any] = ["targetUid": uid, "reason": reason.rawValue]
        if let note, !note.isEmpty { body["note"] = note }
        if let payload = context?.payload, !payload.isEmpty { body["context"] = payload }
        do {
            _ = try await post(to: APIEndpoints.reportUser(), body: body)
        } catch SocialError.dailyLimit {
            throw SocialError.reportLimit
        }
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
            // Le message d'URLSession suit la langue de l'iPhone et parle
            // réseau (« The request timed out ») : on dit quoi faire.
            throw SocialError.transport(message: String(localized: "On n'arrive pas à joindre le serveur. Vérifie ta connexion internet.", bundle: .app))
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
                displayName: PublicProfile.nameOrHandle(displayName, handle),
                avatarURL: PublicProfile.trustedAvatarURL(avatarURL),
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

private nonisolated struct FollowSuggestionsDTO: Decodable {
    let followingCount: Int?
    let suggestions: [Row]

    nonisolated struct Row: Decodable {
        let uid: String
        let handle: String?
        let displayName: String?
        let avatarURL: String?
        let galleryCount: Int?
        let followerCount: Int?
        let followingCount: Int?
        let followsYou: Bool?
        let mutualCount: Int?
        let mutualName: String?
        let commonCount: Int?
    }

    var page: FollowSuggestionsPage {
        FollowSuggestionsPage(
            followingCount: followingCount ?? 0,
            // Un profil sans pseudo n'est pas affichable : mieux vaut une carte
            // de moins qu'une carte blanche.
            suggestions: suggestions.compactMap { row in
                guard let handle = row.handle, !handle.isEmpty else { return nil }
                return FollowSuggestion(
                    profile: PublicProfile(
                        id: row.uid,
                        handle: handle,
                        displayName: PublicProfile.nameOrHandle(row.displayName, handle),
                        avatarURL: PublicProfile.trustedAvatarURL(row.avatarURL),
                        badgeSignature: nil,
                        followerCount: row.followerCount ?? 0,
                        followingCount: row.followingCount ?? 0,
                        galleryCount: row.galleryCount ?? 0
                    ),
                    followsYou: row.followsYou ?? false,
                    mutualCount: row.mutualCount ?? 0,
                    mutualName: row.mutualName,
                    commonCount: row.commonCount ?? 0
                )
            }
        )
    }
}

private nonisolated struct BlockedUsersDTO: Decodable {
    let users: [Row]

    nonisolated struct Row: Decodable {
        let uid: String
        let handle: String?
        let displayName: String?
        let avatarURL: String?
    }

    /// Un compte sans pseudo reste dans la liste, contrairement aux profils à
    /// suivre : c'est le seul endroit d'où le débloquer.
    var profiles: [PublicProfile] {
        users.map { row in
            PublicProfile(
                id: row.uid,
                handle: row.handle ?? "",
                displayName: PublicProfile.nameOrHandle(row.displayName, row.handle),
                avatarURL: PublicProfile.trustedAvatarURL(row.avatarURL),
                badgeSignature: nil,
                followerCount: 0,
                followingCount: 0,
                galleryCount: 0
            )
        }
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
            displayName: PublicProfile.nameOrHandle(displayName, handle),
            avatarURL: PublicProfile.trustedAvatarURL(avatarURL),
            alreadySeen: alreadySeen,
            alreadySuggested: alreadySuggested,
            // `toISOString()` côté serveur écrit les millisecondes, que le
            // format par défaut refuse : la date tombait toujours à `nil`.
            suggestedAt: suggestedAt.flatMap {
                let parser = ISO8601DateFormatter()
                parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                return parser.date(from: $0) ?? ISO8601DateFormatter().date(from: $0)
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
