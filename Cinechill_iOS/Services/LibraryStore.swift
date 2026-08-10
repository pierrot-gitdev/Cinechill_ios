import Combine
import Foundation
import FirebaseAuth
import FirebaseFirestore

final class LibraryStore: ObservableObject {
    @Published private(set) var galleryItems: [GalleryEntry] = []
    @Published private(set) var watchlistItems: [WatchlistEntry] = []
    /// Les plateformes que l'utilisateur a déclaré avoir chez lui.
    ///
    /// Vide ne veut pas dire « toutes » mais « pas encore déclaré » : chaque
    /// écran qui s'en sert doit alors cesser de filtrer plutôt que de tout
    /// exclure. C'est ce qui rend « Disponible chez vous » signifiant.
    @Published private(set) var preferredPlatformIDs: Set<String> = []
    /// Genres que l'utilisateur ne veut jamais voir proposés.
    @Published private(set) var bannedGenreIDs: Set<Int> = []
    /// Décennie de naissance déclarée — calibre le score « probablement vu ».
    @Published private(set) var birthDecade: Int?
    /// Le badge choisi comme signature du profil.
    @Published private(set) var displayedBadgeID: String?
    /// Passe à `true` dès la première réponse du listener Firestore, même si
    /// la galerie est vide. C'est le seul signal fiable pour distinguer « le
    /// premier chargement vient d'arriver » d'un vrai ajout de film — sans
    /// lui, la transition 0 → N du premier chargement se ferait passer pour
    /// un ajout massif aux yeux de tout ce qui célèbre la progression.
    @Published private(set) var hasLoadedGalleryOnce = false
    @Published private(set) var errorMessage: String?

    private var authStateHandle: AuthStateDidChangeListenerHandle?
    private var galleryListener: ListenerRegistration?
    private var watchlistListener: ListenerRegistration?
    private var preferencesListener: ListenerRegistration?
    private var profileListener: ListenerRegistration?
    private var hasStarted = false

    init() {
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        observeAuthState()
    }

    deinit {
        if let authStateHandle {
            Auth.auth().removeStateDidChangeListener(authStateHandle)
        }
        galleryListener?.remove()
        watchlistListener?.remove()
        preferencesListener?.remove()
        profileListener?.remove()
    }

    func isInGallery(_ item: MediaItem) -> Bool {
        galleryItems.contains { $0.id == item.id }
    }

    func isInWatchlist(_ item: MediaItem) -> Bool {
        watchlistItems.contains { $0.id == item.id }
    }

    func addToGallery(_ item: MediaItem) {
        setStatus(.seen, for: item)
    }

    func addToWatchlist(_ item: MediaItem) {
        setStatus(.toWatch, for: item)
    }

    func removeFromGallery(_ item: MediaItem) {
        setStatus(.none, for: item)
    }

    func removeFromWatchlist(_ item: MediaItem) {
        setStatus(.none, for: item)
    }

    func setPreferredPlatforms(_ ids: Set<String>) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        preferredPlatformIDs = ids
        writePreferences(uid: uid, document: "home", data: [
            "preferredPlatformIDs": Array(ids).sorted(),
        ])
    }

    func setBannedGenres(_ ids: Set<Int>) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        bannedGenreIDs = ids
        writePreferences(uid: uid, document: "profile", data: [
            "bannedGenreIds": Array(ids).sorted(),
        ])
    }

    func setBirthDecade(_ decade: Int?) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        birthDecade = decade
        writePreferences(uid: uid, document: "profile", data: [
            "birthDecade": decade as Any,
        ])
    }

    func setDisplayedBadge(_ badgeID: String?) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        displayedBadgeID = badgeID
        writePreferences(uid: uid, document: "profile", data: [
            "displayedBadgeId": badgeID as Any,
        ])
    }

    /// Variante enrichie pour la fiche film, seule à connaître le réalisateur
    /// et la saga — deux champs qu'aucune autre entrée ne peut renseigner et
    /// dont dépendent les badges « Signature » et « L'Intégrale ».
    func addToGallery(
        _ item: MediaItem,
        director: String?,
        collectionID: Int?,
        collectionTotal: Int?
    ) {
        setStatus(.seen, for: item, extras: [
            "director": director as Any,
            "collectionId": collectionID as Any,
            "collectionTotal": collectionTotal as Any,
        ])
    }

    // MARK: - Compte

    /// Nombre de films encore en cooldown après un swipe « pas vu ».
    /// Renvoie `nil` si la lecture échoue — l'information est indicative, elle
    /// ne doit jamais bloquer l'ouverture des réglages.
    func pendingSkipCount() async -> Int? {
        guard let uid = Auth.auth().currentUser?.uid else { return nil }
        let snapshot = try? await db.collection("users")
            .document(uid)
            .collection("swipeSkips")
            .whereField("resurfaceAt", isGreaterThan: Timestamp(date: Date()))
            .count
            .getAggregation(source: .server)
        return snapshot.map { Int(truncating: $0.count) }
    }

    func resetSwipeSkips() async throws -> Int {
        let data = try await callAccountFunction(APIEndpoints.resetSwipeSkips())
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (json?["deleted"] as? Int) ?? 0
    }

    /// Efface le compte côté serveur, puis termine la session locale. La
    /// déconnexion vient en dernier : sans jeton valide, l'appel échouerait.
    func deleteAccount() async throws {
        _ = try await callAccountFunction(APIEndpoints.deleteAccount())
        try? Auth.auth().signOut()
    }

    private func writePreferences(uid: String, document: String, data: [String: Any]) {
        db.collection("users")
            .document(uid)
            .collection("preferences")
            .document(document)
            .setData(data, merge: true) { [weak self] error in
                guard let error else { return }
                DispatchQueue.main.async {
                    self?.errorMessage = error.localizedDescription
                }
            }
    }

    private func callAccountFunction(_ url: URL?) async throws -> Data {
        guard let url else { throw URLError(.badURL) }
        guard let user = Auth.auth().currentUser else { throw URLError(.userAuthenticationRequired) }
        let token = try await user.getIDToken()

        var request = URLRequest(backend: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = Data("{}".utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}

private extension LibraryStore {
    enum MediaStatus: String {
        case toWatch, seen, none
    }

    func setStatus(_ status: MediaStatus, for item: MediaItem, extras: [String: Any] = [:]) {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await callSetMediaStatus(status: status, item: item, extras: extras)
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func callSetMediaStatus(
        status: MediaStatus, item: MediaItem, extras: [String: Any] = [:]
    ) async throws {
        guard let url = APIEndpoints.setMediaStatus() else { return }
        guard let user = Auth.auth().currentUser else { return }
        let token = try await user.getIDToken()

        var payload: [String: Any] = [
            "id": item.id,
            "tmdbId": item.tmdbId,
            "mediaType": item.mediaType.rawValue,
            "title": item.title,
            "posterPath": item.posterPath as Any,
            "overview": item.overview as Any,
            "voteAverage": item.voteAverage as Any,
            "genreIds": item.genreIds,
            "releaseDate": item.releaseDate as Any
        ]
        payload.merge(extras) { _, extra in extra }

        let body: [String: Any] = ["status": status.rawValue, "item": payload]

        var request = URLRequest(backend: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
    }

    var db: Firestore { Firestore.firestore() }

    func observeAuthState() {
        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.galleryListener?.remove()
                self.watchlistListener?.remove()
                self.preferencesListener?.remove()
                self.profileListener?.remove()
                self.galleryItems = []
                self.watchlistItems = []
                self.preferredPlatformIDs = []
                self.bannedGenreIDs = []
                self.birthDecade = nil
                self.displayedBadgeID = nil
                self.hasLoadedGalleryOnce = false

                guard let uid = user?.uid else { return }
                self.startGalleryListener(uid: uid)
                self.startWatchlistListener(uid: uid)
                self.startPreferencesListener(uid: uid)
                self.startProfileListener(uid: uid)
            }
        }
    }

    func startGalleryListener(uid: String) {
        galleryListener = db.collection("users")
            .document(uid)
            .collection("gallery")
            .addSnapshotListener { [weak self] snapshot, error in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if let error {
                        self.errorMessage = error.localizedDescription
                        return
                    }
                    let docs = snapshot?.documents ?? []
                    self.galleryItems = docs.compactMap { self.galleryEntry(from: $0.data()) }
                        .sorted(by: { $0.addedAt > $1.addedAt })
                    self.hasLoadedGalleryOnce = true
                }
            }
    }

    func startWatchlistListener(uid: String) {
        watchlistListener = db.collection("users")
            .document(uid)
            .collection("watchlist")
            .addSnapshotListener { [weak self] snapshot, error in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if let error {
                        self.errorMessage = error.localizedDescription
                        return
                    }
                    let docs = snapshot?.documents ?? []
                    self.watchlistItems = docs.compactMap { self.watchlistEntry(from: $0.data()) }
                        .sorted(by: { $0.addedAt > $1.addedAt })
                }
            }
    }

    func startPreferencesListener(uid: String) {
        preferencesListener = db.collection("users")
            .document(uid)
            .collection("preferences")
            .document("home")
            .addSnapshotListener { [weak self] snapshot, error in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if let error {
                        self.errorMessage = error.localizedDescription
                        return
                    }
                    // Absence de document = rien de déclaré. On ne pré-coche
                    // plus toutes les plateformes : « toutes » rendait le
                    // filtre de l'accueil inopérant et « Disponible chez vous »
                    // vide de sens.
                    guard let snapshot, snapshot.exists else {
                        self.preferredPlatformIDs = []
                        return
                    }
                    let ids = snapshot.data()?["preferredPlatformIDs"] as? [String] ?? []
                    self.preferredPlatformIDs = Set(ids)
                }
            }
    }

    func startProfileListener(uid: String) {
        profileListener = db.collection("users")
            .document(uid)
            .collection("preferences")
            .document("profile")
            .addSnapshotListener { [weak self] snapshot, error in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if let error {
                        self.errorMessage = error.localizedDescription
                        return
                    }
                    guard let data = snapshot?.data(), snapshot?.exists == true else {
                        self.bannedGenreIDs = []
                        self.birthDecade = nil
                        self.displayedBadgeID = nil
                        return
                    }
                    self.bannedGenreIDs = Set(data["bannedGenreIds"] as? [Int] ?? [])
                    self.birthDecade = data["birthDecade"] as? Int
                    self.displayedBadgeID = data["displayedBadgeId"] as? String
                }
            }
    }

    // Les encodeurs Swift → Firestore ont disparu avec l'écriture directe : tout
    // passe désormais par la fonction `setMediaStatus`, qui compose le document
    // côté serveur. Seuls les décodeurs restent, pour les écoutes temps réel.

    func galleryEntry(from data: [String: Any]) -> GalleryEntry? {
        guard
            let id = data["id"] as? String,
            let tmdbId = data["tmdbId"] as? Int,
            let mediaTypeRaw = data["mediaType"] as? String,
            let mediaType = MediaType(rawValue: mediaTypeRaw),
            let title = data["title"] as? String
        else {
            return nil
        }

        let addedAt: Date
        if let timestamp = data["addedAt"] as? Timestamp {
            addedAt = timestamp.dateValue()
        } else {
            addedAt = Date.distantPast
        }

        return GalleryEntry(
            id: id,
            tmdbId: tmdbId,
            mediaType: mediaType,
            title: title,
            posterPath: data["posterPath"] as? String,
            overview: data["overview"] as? String,
            voteAverage: data["voteAverage"] as? Double,
            genreIds: data["genreIds"] as? [Int] ?? [],
            releaseDate: data["releaseDate"] as? String,
            addedAt: addedAt
        )
    }

    func watchlistEntry(from data: [String: Any]) -> WatchlistEntry? {
        guard
            let id = data["id"] as? String,
            let tmdbId = data["tmdbId"] as? Int,
            let mediaTypeRaw = data["mediaType"] as? String,
            let mediaType = MediaType(rawValue: mediaTypeRaw),
            let title = data["title"] as? String
        else {
            return nil
        }

        let addedAt: Date
        if let timestamp = data["addedAt"] as? Timestamp {
            addedAt = timestamp.dateValue()
        } else {
            addedAt = Date.distantPast
        }

        return WatchlistEntry(
            id: id,
            tmdbId: tmdbId,
            mediaType: mediaType,
            title: title,
            posterPath: data["posterPath"] as? String,
            overview: data["overview"] as? String,
            voteAverage: data["voteAverage"] as? Double,
            genreIds: data["genreIds"] as? [Int] ?? [],
            releaseDate: data["releaseDate"] as? String,
            addedAt: addedAt,
            recommendedBy: recommenders(from: data["recommendedBy"])
        )
    }

    /// La provenance, écrite par `respondToSuggestion`. Absente sur toute
    /// entrée ajoutée par soi-même — c'est ce qui distingue la section
    /// « Recommandés par vos amis » du reste de la watchlist.
    func recommenders(from raw: Any?) -> [Recommender] {
        guard let rows = raw as? [[String: Any]] else { return [] }
        return rows.compactMap { row in
            guard let uid = row["uid"] as? String else { return nil }
            let at: Date
            if let stamp = row["at"] as? Timestamp {
                at = stamp.dateValue()
            } else {
                at = .distantPast
            }
            return Recommender(
                uid: uid,
                displayName: (row["displayName"] as? String) ?? "Quelqu'un",
                avatarURL: (row["avatarURL"] as? String).flatMap(URL.init(string:)),
                at: at
            )
        }
        .sorted { $0.at > $1.at }
    }
}

