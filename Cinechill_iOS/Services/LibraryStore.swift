import Combine
import Foundation
import FirebaseAuth
import FirebaseFirestore

final class LibraryStore: ObservableObject {
    @Published private(set) var galleryItems: [GalleryEntry] = []
    @Published private(set) var watchlistItems: [WatchlistEntry] = []
    @Published private(set) var preferredPlatformIDs: Set<String> = []
    @Published private(set) var shouldInitializePreferredPlatforms = false
    @Published private(set) var errorMessage: String?

    private var authStateHandle: AuthStateDidChangeListenerHandle?
    private var galleryListener: ListenerRegistration?
    private var watchlistListener: ListenerRegistration?
    private var preferencesListener: ListenerRegistration?
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
    }

    func isInGallery(_ item: MediaItem) -> Bool {
        galleryItems.contains { $0.id == item.id }
    }

    func isInWatchlist(_ item: MediaItem) -> Bool {
        watchlistItems.contains { $0.id == item.id }
    }

    func addToGallery(_ item: MediaItem) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let entry = GalleryEntry(item: item)
        db.collection("users")
            .document(uid)
            .collection("gallery")
            .document(entry.id)
            .setData(galleryData(from: entry)) { [weak self] error in
                guard let error else { return }
                DispatchQueue.main.async {
                    self?.errorMessage = error.localizedDescription
                }
            }
    }

    func addToWatchlist(_ item: MediaItem) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let entry = WatchlistEntry(item: item)
        db.collection("users")
            .document(uid)
            .collection("watchlist")
            .document(entry.id)
            .setData(watchlistData(from: entry)) { [weak self] error in
                guard let error else { return }
                DispatchQueue.main.async {
                    self?.errorMessage = error.localizedDescription
                }
            }
    }

    func removeFromGallery(_ item: MediaItem) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        db.collection("users")
            .document(uid)
            .collection("gallery")
            .document(item.id)
            .delete { [weak self] error in
                guard let error else { return }
                DispatchQueue.main.async {
                    self?.errorMessage = error.localizedDescription
                }
            }
    }

    func removeFromWatchlist(_ item: MediaItem) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        db.collection("users")
            .document(uid)
            .collection("watchlist")
            .document(item.id)
            .delete { [weak self] error in
                guard let error else { return }
                DispatchQueue.main.async {
                    self?.errorMessage = error.localizedDescription
                }
            }
    }

    func setPreferredPlatforms(_ ids: Set<String>) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        shouldInitializePreferredPlatforms = false
        db.collection("users")
            .document(uid)
            .collection("preferences")
            .document("home")
            .setData(["preferredPlatformIDs": Array(ids).sorted()]) { [weak self] error in
                guard let error else { return }
                DispatchQueue.main.async {
                    self?.errorMessage = error.localizedDescription
                }
            }
    }

    func initializePreferredPlatformsIfNeeded(with allPlatformIDs: Set<String>) {
        guard shouldInitializePreferredPlatforms, !allPlatformIDs.isEmpty else { return }
        preferredPlatformIDs = allPlatformIDs
        setPreferredPlatforms(allPlatformIDs)
    }
}

private extension LibraryStore {
    var db: Firestore { Firestore.firestore() }

    func observeAuthState() {
        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.galleryListener?.remove()
                self.watchlistListener?.remove()
                self.preferencesListener?.remove()
                self.galleryItems = []
                self.watchlistItems = []
                self.preferredPlatformIDs = []
                self.shouldInitializePreferredPlatforms = false

                guard let uid = user?.uid else { return }
                self.startGalleryListener(uid: uid)
                self.startWatchlistListener(uid: uid)
                self.startPreferencesListener(uid: uid)
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
                    guard let snapshot else {
                        self.preferredPlatformIDs = []
                        self.shouldInitializePreferredPlatforms = true
                        return
                    }
                    if !snapshot.exists {
                        self.preferredPlatformIDs = []
                        self.shouldInitializePreferredPlatforms = true
                        return
                    }
                    let ids = snapshot.data()?["preferredPlatformIDs"] as? [String] ?? []
                    self.preferredPlatformIDs = Set(ids)
                    self.shouldInitializePreferredPlatforms = false
                }
            }
    }

    func galleryData(from entry: GalleryEntry) -> [String: Any] {
        [
            "id": entry.id,
            "tmdbId": entry.tmdbId,
            "mediaType": entry.mediaType.rawValue,
            "title": entry.title,
            "posterPath": entry.posterPath as Any,
            "overview": entry.overview as Any,
            "voteAverage": entry.voteAverage as Any,
            "genreIds": entry.genreIds,
            "releaseDate": entry.releaseDate as Any,
            "addedAt": Timestamp(date: entry.addedAt)
        ]
    }

    func watchlistData(from entry: WatchlistEntry) -> [String: Any] {
        [
            "id": entry.id,
            "tmdbId": entry.tmdbId,
            "mediaType": entry.mediaType.rawValue,
            "title": entry.title,
            "posterPath": entry.posterPath as Any,
            "overview": entry.overview as Any,
            "voteAverage": entry.voteAverage as Any,
            "genreIds": entry.genreIds,
            "releaseDate": entry.releaseDate as Any,
            "addedAt": Timestamp(date: entry.addedAt)
        ]
    }

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
            addedAt: addedAt
        )
    }
}

