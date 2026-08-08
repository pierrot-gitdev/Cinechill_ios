//
//  SocialStore.swift
//  Cinechill_iOS
//

import Combine
import Foundation
import FirebaseAuth
import FirebaseFirestore

/// L'état partagé du Hall : mon profil public, qui je suis, et ce qu'on m'a
/// recommandé.
///
/// Séparé de `LibraryStore` à dessein — celui-ci gère déjà galerie, watchlist,
/// préférences et suppression de compte ; y verser le social en aurait fait un
/// cinquième rôle. Les deux stores ne se connaissent pas : ce qui les relie,
/// c'est Firestore, pas une dépendance Swift.
@MainActor
final class SocialStore: ObservableObject {
    /// Mon profil public. `nil` tant qu'aucun pseudo n'a été choisi — c'est ce
    /// qui déclenche l'invitation à en prendre un.
    @Published private(set) var myProfile: PublicProfile?
    /// Les uid que je suis. Un `Set` parce que la seule question posée partout
    /// dans l'app est « est-ce que je suis cette personne ? ».
    @Published private(set) var followingUIDs: Set<String> = []
    @Published private(set) var suggestions: [Suggestion] = []
    /// Les abonnés récents, source des notifications « X vous suit ».
    @Published private(set) var recentFollowers: [PublicProfile] = []
    @Published private(set) var hasLoadedProfileOnce = false
    @Published private(set) var errorMessage: String?

    private let client: any SocialServicing

    private var authHandle: AuthStateDidChangeListenerHandle?
    private var profileListener: ListenerRegistration?
    private var followingListener: ListenerRegistration?
    private var suggestionsListener: ListenerRegistration?
    private var followersListener: ListenerRegistration?
    private var hasStarted = false
    /// Lu à chaque snapshot plutôt que capturé à la création du listener :
    /// sans ça, les abonnés acquittés réapparaîtraient au snapshot suivant.
    private var followersSeenAt: Date = .distantPast

    /// Les abonnés apparus depuis cette date sont considérés comme « récents »
    /// et alimentent le centre de notifications.
    private static let followerNoticeWindow: TimeInterval = 30 * 24 * 3600

    init(client: any SocialServicing = SocialClient()) {
        self.client = client
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        observeAuthState()
    }

    deinit {
        // `deinit` n'est pas isolé au MainActor : on ne touche qu'aux
        // registrations, qui sont sûres à libérer depuis n'importe quel fil.
        if let authHandle {
            Auth.auth().removeStateDidChangeListener(authHandle)
        }
        profileListener?.remove()
        followingListener?.remove()
        suggestionsListener?.remove()
        followersListener?.remove()
    }

    // MARK: - Lecture

    func isFollowing(_ uid: String) -> Bool { followingUIDs.contains(uid) }

    var myUID: String? { Auth.auth().currentUser?.uid }

    /// Le nombre de pastilles à afficher sur la cloche. Les abonnés récents y
    /// comptent autant que les recommandations : les deux appellent une action.
    var unreadCount: Int { suggestions.count + recentFollowers.count }

    // MARK: - Écriture

    func claimHandle(_ handle: String) async throws {
        try await client.claimHandle(handle)
    }

    /// Revendication initiale, à l'inscription : le pseudo et le nom en un seul
    /// geste.
    ///
    /// Ne passe pas par `syncDisplayName`, qui exige `myProfile != nil` : le
    /// profil vient d'être créé côté serveur, mais l'écouteur Firestore n'a pas
    /// encore eu le temps de le remonter. Attendre cet aller-retour ferait
    /// perdre le nom une fois sur deux — c'est une course, pas un cas rare.
    ///
    /// Le nom est écrit après le pseudo et son échec n'est pas propagé : un
    /// compte sans nom d'affichage reste utilisable, et se répare dans les
    /// réglages. Un compte sans pseudo, non — c'est pourquoi lui seul peut
    /// faire échouer l'inscription.
    func claimHandle(_ handle: String, displayName: String) async throws {
        try await client.claimHandle(handle)

        guard let uid = myUID else { return }
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        try? await db.collection("publicProfiles").document(uid).setData([
            "displayName": trimmed,
            "displayNameNormalized": Self.normalize(trimmed),
        ], merge: true)
    }

    /// Garde `publicProfiles.displayName` en phase avec le nom déclaré dans
    /// les réglages — sans ça, la recherche par prénom/nom trouverait un nom
    /// périmé, et le profil affiché à vos abonnés ne serait plus le vôtre.
    ///
    /// Écriture directe (les règles Firestore l'autorisent pour ces deux
    /// champs, pas pour les compteurs) : pas besoin d'une Cloud Function pour
    /// une donnée purement déclarative. Sans effet si aucun pseudo n'a encore
    /// été choisi — rien à synchroniser avant qu'un profil public existe.
    func syncDisplayName(_ name: String) async {
        guard let uid = myUID, myProfile != nil else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try await db.collection("publicProfiles").document(uid).setData([
                "displayName": trimmed,
                "displayNameNormalized": Self.normalize(trimmed),
            ], merge: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Bascule le suivi. Optimiste : l'état local change d'abord, et n'est
    /// rétabli qu'en cas d'échec — un bouton de suivi qui attend le réseau
    /// donne l'impression d'être cassé.
    func toggleFollow(uid: String) async throws {
        let wasFollowing = followingUIDs.contains(uid)
        if wasFollowing {
            followingUIDs.remove(uid)
        } else {
            followingUIDs.insert(uid)
        }
        do {
            if wasFollowing {
                try await client.unfollow(uid: uid)
            } else {
                try await client.follow(uid: uid)
            }
        } catch {
            if wasFollowing {
                followingUIDs.insert(uid)
            } else {
                followingUIDs.remove(uid)
            }
            throw error
        }
    }

    func suggestionTargets(itemId: String) async throws -> [SuggestionTarget] {
        try await client.suggestionTargets(itemId: itemId)
    }

    /// Le profil public enrichi (ADN cinéphile, aperçu de galerie). Passe par
    /// le client injecté comme tout le reste : une vue qui instancierait son
    /// propre `SocialClient` court-circuiterait l'abstraction.
    func profileDetail(uid: String) async throws -> PublicProfileDetail {
        try await client.publicProfileDetail(uid: uid)
    }

    func sendSuggestion(to uid: String, item: MediaItem) async throws {
        try await client.sendSuggestion(to: uid, item: item)
    }

    @discardableResult
    func respond(to suggestionId: String, accept: Bool) async throws -> Bool {
        // Retrait immédiat : le listener confirmera, mais la ligne ne doit pas
        // rester sous le doigt le temps d'un aller-retour.
        let previous = suggestions
        suggestions.removeAll { $0.id == suggestionId }
        do {
            return try await client.respond(to: suggestionId, accept: accept)
        } catch {
            suggestions = previous
            throw error
        }
    }

    /// Marque les abonnés courants comme vus — ils quittent la cloche sans
    /// action de l'utilisateur, contrairement aux recommandations qu'il faut
    /// accepter ou refuser.
    func acknowledgeFollowers() {
        guard let uid = myUID, !recentFollowers.isEmpty else { return }
        let now = Date()
        followersSeenAt = now
        UserDefaults.standard.set(now, forKey: Self.followersSeenKey(uid))
        recentFollowers = []
    }

    // MARK: - Recherche

    /// Recherche par préfixe, sur le pseudo **et** sur le prénom/nom — deux
    /// requêtes à un seul champ, exécutées en parallèle et fusionnées.
    ///
    /// Firestore indexe automatiquement chaque champ pris seul : il n'y a
    /// rien à déclarer dans `firestore.indexes.json`, et c'est précisément
    /// ce qui interdit une requête `OR` entre deux champs — d'où les deux
    /// requêtes plutôt qu'une. Le `\u{f8ff}` est la borne haute d'un préfixe,
    /// la convention Firestore pour ça. Un même profil trouvé par les deux
    /// voies (pseudo *et* nom contiennent la saisie) ne compte qu'une fois.
    func searchProfiles(matching query: String, limit: Int = 25) async -> [PublicProfile] {
        let needle = Self.normalize(query)
        guard needle.count >= 2 else { return [] }
        let me = myUID

        async let byHandle = prefixQuery(field: "handleNormalized", needle: needle, limit: limit)
        async let byName = prefixQuery(field: "displayNameNormalized", needle: needle, limit: limit)

        var seen = Set<String>()
        var results: [PublicProfile] = []
        for profile in await byHandle + (await byName) where profile.id != me {
            guard seen.insert(profile.id).inserted else { continue }
            results.append(profile)
        }
        return Array(results.prefix(limit))
    }

    private func prefixQuery(field: String, needle: String, limit: Int) async -> [PublicProfile] {
        do {
            let snapshot = try await db.collection("publicProfiles")
                .whereField(field, isGreaterThanOrEqualTo: needle)
                .whereField(field, isLessThan: needle + "\u{f8ff}")
                .limit(to: limit)
                .getDocuments()
            return snapshot.documents.compactMap { PublicProfile(id: $0.documentID, data: $0.data()) }
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }

    /// Quelques profils à proposer quand le champ de recherche est vide — un
    /// écran nu renverrait l'utilisateur à sa propre absence d'idée.
    func suggestedProfiles(limit: Int = 12) async -> [PublicProfile] {
        do {
            let snapshot = try await db.collection("publicProfiles")
                .order(by: "galleryCount", descending: true)
                .limit(to: limit)
                .getDocuments()
            let me = myUID
            return snapshot.documents
                .compactMap { PublicProfile(id: $0.documentID, data: $0.data()) }
                .filter { $0.id != me }
        } catch {
            // Sans index composite ce tri peut échouer : l'écran doit rester
            // utilisable, la recherche par frappe fonctionne de toute façon.
            return []
        }
    }

    func profile(uid: String) async -> PublicProfile? {
        do {
            let snapshot = try await db.collection("publicProfiles").document(uid).getDocument()
            guard let data = snapshot.data() else { return nil }
            return PublicProfile(id: snapshot.documentID, data: data)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Les profils d'une liste d'abonnés/abonnements.
    ///
    /// Les sous-collections `following`/`followers` ne portent qu'une date : le
    /// profil affichable vit dans `publicProfiles`. On les recharge par paquets
    /// de dix, la limite d'un `in` Firestore.
    func profiles(uids: [String]) async -> [PublicProfile] {
        guard !uids.isEmpty else { return [] }
        var out: [PublicProfile] = []
        for chunk in uids.chunked(into: 10) {
            do {
                let snapshot = try await db.collection("publicProfiles")
                    .whereField(FieldPath.documentID(), in: chunk)
                    .getDocuments()
                out += snapshot.documents.compactMap {
                    PublicProfile(id: $0.documentID, data: $0.data())
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        return out
    }

    func followingUIDs(of uid: String) async -> [String] {
        await linkedUIDs(of: uid, collection: "following")
    }

    func followerUIDs(of uid: String) async -> [String] {
        await linkedUIDs(of: uid, collection: "followers")
    }

    private func linkedUIDs(of uid: String, collection: String) async -> [String] {
        do {
            let snapshot = try await db.collection("users").document(uid)
                .collection(collection).getDocuments()
            return snapshot.documents.map(\.documentID)
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }

    // MARK: - Listeners

    private var db: Firestore { Firestore.firestore() }

    private static func followersSeenKey(_ uid: String) -> String {
        "cinechill_followers_seen_\(uid)"
    }

    /// Minuscules et sans accents : « lea » doit trouver « Léa ».
    static func normalize(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
            .lowercased()
    }

    private func observeAuthState() {
        authHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.teardownListeners()
                self.myProfile = nil
                self.followingUIDs = []
                self.suggestions = []
                self.recentFollowers = []
                self.hasLoadedProfileOnce = false

                guard let uid = user?.uid else { return }
                self.startProfileListener(uid: uid)
                self.startFollowingListener(uid: uid)
                self.startSuggestionsListener(uid: uid)
                self.startFollowersListener(uid: uid)
            }
        }
    }

    private func teardownListeners() {
        profileListener?.remove()
        followingListener?.remove()
        suggestionsListener?.remove()
        followersListener?.remove()
        profileListener = nil
        followingListener = nil
        suggestionsListener = nil
        followersListener = nil
    }

    private func startProfileListener(uid: String) {
        profileListener = db.collection("publicProfiles").document(uid)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let error {
                        self.errorMessage = error.localizedDescription
                        self.hasLoadedProfileOnce = true
                        return
                    }
                    if let data = snapshot?.data(), snapshot?.exists == true {
                        self.myProfile = PublicProfile(id: uid, data: data)
                    } else {
                        self.myProfile = nil
                    }
                    self.hasLoadedProfileOnce = true
                }
            }
    }

    private func startFollowingListener(uid: String) {
        followingListener = db.collection("users").document(uid)
            .collection("following")
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let error {
                        self.errorMessage = error.localizedDescription
                        return
                    }
                    self.followingUIDs = Set(snapshot?.documents.map(\.documentID) ?? [])
                }
            }
    }

    private func startSuggestionsListener(uid: String) {
        suggestionsListener = db.collection("users").document(uid)
            .collection("suggestions")
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let error {
                        self.errorMessage = error.localizedDescription
                        return
                    }
                    let docs = snapshot?.documents ?? []
                    self.suggestions = docs
                        .compactMap { doc in
                            var data = doc.data()
                            // Firestore rend un `Timestamp` ; le modèle veut
                            // une `Date` — converti ici plutôt que d'importer
                            // FirebaseFirestore jusque dans les modèles.
                            if let stamp = data["createdAt"] as? Timestamp {
                                data["createdAt"] = stamp.dateValue()
                            }
                            return Suggestion(id: doc.documentID, data: data)
                        }
                        .sorted { $0.createdAt > $1.createdAt }
                }
            }
    }

    private func startFollowersListener(uid: String) {
        followersSeenAt = UserDefaults.standard
            .object(forKey: Self.followersSeenKey(uid)) as? Date ?? .distantPast

        followersListener = db.collection("users").document(uid)
            .collection("followers")
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let error {
                        self.errorMessage = error.localizedDescription
                        return
                    }
                    let cutoff = max(
                        self.followersSeenAt,
                        Date().addingTimeInterval(-Self.followerNoticeWindow)
                    )
                    let fresh = (snapshot?.documents ?? []).filter { doc in
                        guard let since = doc.get("since") as? Timestamp else { return false }
                        return since.dateValue() > cutoff
                    }.map(\.documentID)

                    guard !fresh.isEmpty else {
                        self.recentFollowers = []
                        return
                    }
                    self.recentFollowers = await self.profiles(uids: fresh)
                }
            }
    }
}
