import Combine
import Foundation
import FirebaseAuth
import FirebaseFirestore

final class LibraryStore: ObservableObject {
    /// Ce qu'un film peut devenir depuis une fiche : vu, à voir, ou rien.
    ///
    /// Dans le corps de la classe et non dans l'extension privée plus bas :
    /// `pendingStatusByItemID` et `pendingStatus(for:)` le donnent à lire au
    /// reste de l'app, et un type privé ne peut pas transparaître dans une
    /// déclaration qui ne l'est pas.
    enum MediaStatus: String {
        case toWatch, seen, none
    }

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
    /// Même rôle pour les préférences, et pour un besoin précis : l'accueil est préchargé
    /// pendant l'ouverture de l'app, avant que le moindre écran n'existe, et « populaire »
    /// dépend des plateformes déclarées. Sans ce signal, le préchargement partirait sur une
    /// liste vide et l'écran se corrigerait sous les yeux de l'utilisateur.
    @Published private(set) var hasLoadedPreferencesOnce = false
    /// Les films dont le statut est en cours d'écriture, et l'état visé par chacun.
    ///
    /// Marquer un film « vu » ne change rien localement : la requête part vers le backend, qui
    /// écrit dans Firestore, dont le listener revient enfin peupler `galleryItems`. Tant que
    /// cette boucle n'est pas bouclée, l'écran n'a strictement rien à montrer. C'est ce que
    /// cette table répare.
    ///
    /// L'attente ne prend d'ailleurs pas fin au retour de la requête mais à l'instant où les
    /// listeners l'ont répercutée : ce sont eux que l'écran affiche. Sans cette nuance,
    /// l'indicateur s'éteindrait deux ou trois dixièmes de seconde avant que le bouton ne
    /// bascule, ce qui se lit comme un raté.
    @Published private(set) var pendingStatusByItemID: [String: MediaStatus] = [:]
    /// Les coups de cœur en cours d'écriture, et l'état visé par chacun. Même
    /// mécanique que le statut : rien n'est montré comme acquis avant que le
    /// listener ne l'ait répercuté, mais l'attente reste lisible tuile par
    /// tuile.
    @Published private(set) var pendingLoveByItemID: [String: Bool] = [:]
    @Published private(set) var errorMessage: String?

    private var authStateHandle: AuthStateDidChangeListenerHandle?
    private var galleryListener: ListenerRegistration?
    private var watchlistListener: ListenerRegistration?
    private var preferencesListener: ListenerRegistration?
    private var profileListener: ListenerRegistration?
    private var hasStarted = false

    /// Date du dernier réveil de la fonction d'écriture. Google garde l'instance éveillée
    /// quelques minutes : la resolliciter à chaque fiche ouverte ne servirait à rien.
    private var lastStatusWarmUp: Date?
    private static let warmUpValidity: TimeInterval = 240

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

    /// Attend la première réponse de Firestore sur les préférences, sans jamais bloquer plus
    /// que la durée donnée.
    ///
    /// L'attente est bornée parce que le préchargement doit démarrer même si le réseau ne
    /// répond pas : au pire on part sur une liste vide, et « populaire » se corrigera comme il
    /// le faisait déjà. La boucle est délibérément naïve — pas de pont Combine, pas de
    /// listener à défaire — puisqu'elle meurt avec la tâche qui l'a lancée.
    @MainActor
    func waitForPreferences(upTo limit: Duration) async {
        guard !hasLoadedPreferencesOnce else { return }
        let deadline = ContinuousClock.now.advanced(by: limit)
        while !hasLoadedPreferencesOnce, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(40))
        }
    }

    /// L'état visé pour ce film, si une écriture est en cours.
    func pendingStatus(for item: MediaItem) -> MediaStatus? {
        pendingStatusByItemID[item.id]
    }

    /// Réveille la fonction d'écriture avant qu'on en ait besoin.
    ///
    /// Les fonctions du backend dorment quand personne ne s'en sert, et il faut plusieurs
    /// secondes pour en réveiller une : conteneur, Node, chargement du module, initialisation
    /// de l'Admin SDK, récupération des clés de signature Google. C'est ce réveil, et non
    /// l'écriture elle-même, qui rend le premier « Vu » d'une session si lent.
    ///
    /// On choisit donc **quand** le payer plutôt que de payer une instance éveillée en
    /// permanence : à l'ouverture de l'app, pendant les cinq secondes où l'utilisateur regarde
    /// la salle s'éclairer, et à l'ouverture d'une fiche, qui est le meilleur signe qu'un
    /// « Vu » approche. Google garde ensuite l'instance éveillée quelques minutes.
    ///
    /// La requête est volontairement incomplète. Elle porte un vrai jeton, que la fonction
    /// vérifie — c'est la partie coûteuse du réveil, celle qu'on veut payer d'avance — mais
    /// aucun statut, si bien qu'elle est refusée avant d'atteindre la moindre écriture. Rien
    /// n'est modifié, et le refus n'est pas journalisé côté serveur.
    ///
    /// Échouer n'a aucune conséquence : au pire le premier « Vu » sera lent, comme avant.
    @MainActor
    func warmUpStatusEndpoint() async {
        if let last = lastStatusWarmUp, Date().timeIntervalSince(last) < Self.warmUpValidity {
            return
        }
        guard let url = APIEndpoints.setMediaStatus() else { return }
        guard let user = Auth.auth().currentUser else { return }
        // Marqué avant l'appel : deux fiches ouvertes coup sur coup ne doivent pas envoyer
        // deux réveils, et un réveil lent ne doit pas en autoriser un second entre-temps.
        lastStatusWarmUp = Date()

        guard let token = try? await user.getIDToken() else { return }

        var request = await URLRequest(backend: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = Data("{}".utf8)
        _ = try? await URLSession.shared.data(for: request)
    }

    func isInGallery(_ item: MediaItem) -> Bool {
        galleryItems.contains { $0.id == item.id }
    }

    /// Le coup de cœur tel que l'écran doit le montrer : ce que Firestore dit,
    /// sauf si une écriture est en route — auquel cas c'est elle qu'on écoute,
    /// sans quoi le cœur retomberait sous le doigt le temps de l'aller-retour.
    func isLoved(_ item: MediaItem) -> Bool {
        if let pending = pendingLoveByItemID[item.id] { return pending }
        return galleryItems.first { $0.id == item.id }?.isLoved == true
    }

    /// Combien de films portent un cœur — le compte de l'artéfact du Cœur.
    var lovedCount: Int {
        galleryItems.filter { entry in
            pendingLoveByItemID[entry.id] ?? entry.isLoved
        }.count
    }

    /// Pose ou retire un coup de cœur sur un film déjà en galerie.
    func setLove(_ item: MediaItem, loved: Bool) {
        guard isInGallery(item) else { return }
        pendingLoveByItemID[item.id] = loved

        Task { [weak self] in
            guard let self else { return }
            do {
                try await callSetGalleryLove(itemID: item.id, loved: loved)
                // Même filet de sécurité que le statut : si le document était
                // déjà dans l'état demandé, le listener ne repassera pas.
                try? await Task.sleep(for: .seconds(4))
                await MainActor.run { self.clearPendingLove(for: item.id, ifStill: loved) }
            } catch {
                await MainActor.run {
                    self.clearPendingLove(for: item.id, ifStill: loved)
                    self.errorMessage = error.localizedDescription
                }
            }
        }
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

        var request = await URLRequest(backend: url)
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
    func setStatus(_ status: MediaStatus, for item: MediaItem, extras: [String: Any] = [:]) {
        pendingStatusByItemID[item.id] = status

        Task { [weak self] in
            guard let self else { return }
            do {
                try await callSetMediaStatus(status: status, item: item, extras: extras)
                // Filet de sécurité. Normalement c'est le listener qui met fin à l'attente,
                // mais il ne se déclenche pas si le document était déjà dans l'état demandé :
                // l'indicateur tournerait alors sans fin pour une action pourtant réussie.
                try? await Task.sleep(for: .seconds(4))
                await MainActor.run { self.clearPendingStatus(for: item.id, ifStill: status) }
            } catch {
                await MainActor.run {
                    self.clearPendingStatus(for: item.id, ifStill: status)
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    /// Retire de l'attente tout ce que les listeners ont déjà répercuté.
    private func resolvePendingStatuses() {
        guard !pendingStatusByItemID.isEmpty else { return }
        pendingStatusByItemID = pendingStatusByItemID.filter { id, target in
            switch target {
            case .seen:
                return !galleryItems.contains { $0.id == id }
            case .toWatch:
                return !watchlistItems.contains { $0.id == id }
            case .none:
                return galleryItems.contains { $0.id == id }
                    || watchlistItems.contains { $0.id == id }
            }
        }
    }

    /// Même résolution pour les cœurs : l'attente prend fin quand Firestore
    /// raconte l'état demandé — ou quand le film a quitté la galerie, auquel
    /// cas il n'y a plus rien à attendre.
    private func resolvePendingLoves() {
        guard !pendingLoveByItemID.isEmpty else { return }
        pendingLoveByItemID = pendingLoveByItemID.filter { id, target in
            guard let entry = galleryItems.first(where: { $0.id == id }) else { return false }
            return entry.isLoved != target
        }
    }

    private func clearPendingLove(for id: String, ifStill target: Bool) {
        guard pendingLoveByItemID[id] == target else { return }
        pendingLoveByItemID.removeValue(forKey: id)
    }

    func callSetGalleryLove(itemID: String, loved: Bool) async throws {
        guard let url = APIEndpoints.setGalleryLove() else { return }
        guard let user = Auth.auth().currentUser else { return }
        let token = try await user.getIDToken()

        var request = await URLRequest(backend: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "itemId": itemID, "loved": loved,
        ])

        let (_, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
    }

    /// `ifStill` protège du cas où l'utilisateur a retouché le bouton entre-temps : le filet
    /// de sécurité de l'action précédente ne doit pas éteindre l'attente de la suivante.
    private func clearPendingStatus(for id: String, ifStill target: MediaStatus) {
        guard pendingStatusByItemID[id] == target else { return }
        pendingStatusByItemID.removeValue(forKey: id)
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

        var request = await URLRequest(backend: url)
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
                self.hasLoadedPreferencesOnce = false
                self.pendingStatusByItemID = [:]
                self.pendingLoveByItemID = [:]
                // La porte de CinéMatch est un état de compte, pas d'appareil :
                // changer d'utilisateur ne doit léguer ni la porte en cache, ni
                // le seuil déjà franchi, ni l'historique des célébrations.
                for key in ["cinematch.door", "cinematch.doorOpened", "cinematch.doorCelebratedKeys"] {
                    UserDefaults.standard.removeObject(forKey: key)
                }

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
                    self.resolvePendingStatuses()
                    self.resolvePendingLoves()
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
                    self.resolvePendingStatuses()
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
                        self.hasLoadedPreferencesOnce = true
                        return
                    }
                    let ids = snapshot.data()?["preferredPlatformIDs"] as? [String] ?? []
                    self.preferredPlatformIDs = Set(ids)
                    self.hasLoadedPreferencesOnce = true
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
            addedAt: addedAt,
            lovedAt: (data["lovedAt"] as? Timestamp)?.dateValue()
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

