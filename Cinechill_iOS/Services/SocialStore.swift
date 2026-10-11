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
    /// Les abonnés récents, source des notifications « X te suit ».
    @Published private(set) var recentFollowers: [PublicProfile] = []
    @Published private(set) var hasLoadedProfileOnce = false
    @Published private(set) var errorMessage: String?

    /// Les profils à suivre, tels que chargés. Un profil suivi entretemps y
    /// reste, en « Suivi » : sa carte ne doit pas partir sous le doigt. Il
    /// disparaît au chargement suivant, que le serveur filtre.
    @Published private(set) var followSuggestions: [FollowSuggestion] = []
    @Published private(set) var followSuggestionsPhase: FollowSuggestionsPhase = .idle
    /// Le nombre de personnes suivies au moment du chargement : la place de
    /// la rangée sur l'accueil en dépend, et ne doit pas bouger ensuite.
    @Published private(set) var followingCountAtLoad = 0
    /// La rangée de l'accueil : présente seulement si le chargement a rendu
    /// trois profils au moins, et en tête tant qu'on suit peu de monde ou que
    /// quelqu'un nous suit sans retour. Décidé au chargement, pour qu'un suivi
    /// ou une carte retirée ne déplace jamais la rangée sous le doigt.
    @Published private(set) var followSuggestionsOnHome = false
    @Published private(set) var followSuggestionsLeadHome = false
    /// Les suivis et les retraits en cours d'écriture, pour que chaque bouton
    /// tourne seul, où qu'il soit affiché : une même personne peut l'être à la
    /// fois sur l'accueil et dans la recherche.
    @Published private(set) var followsInFlight: Set<String> = []
    @Published private(set) var dismissalsInFlight: Set<String> = []
    /// Les profils que j'ai bloqués, tels que `users/{uid}/blocks` les tient.
    /// Un `Set` pour la même raison que `followingUIDs` : la question posée
    /// partout est « ce profil est-il bloqué ? ».
    @Published private(set) var blockedUIDs: Set<String> = []
    /// Les blocages et déblocages en cours d'écriture, pour que le bouton
    /// tourne où qu'il soit : profil, notifications, liste des bloqués.
    @Published private(set) var blocksInFlight: Set<String> = []

    private let client: any SocialServicing

    private var authHandle: AuthStateDidChangeListenerHandle?
    private var profileListener: ListenerRegistration?
    private var followingListener: ListenerRegistration?
    private var suggestionsListener: ListenerRegistration?
    private var followersListener: ListenerRegistration?
    private var blocksListener: ListenerRegistration?
    private var hasStarted = false
    /// Lu à chaque snapshot plutôt que capturé à la création du listener :
    /// sans ça, les abonnés acquittés réapparaîtraient au snapshot suivant.
    private var followersSeenAt: Date = .distantPast
    private var followSuggestionsLoadedAt: Date?
    /// Vrai quand mon profil porte déjà ses préfixes de recherche. Un profil
    /// créé avant leur arrivée ne les a pas : le prochain passage par
    /// `syncDisplayName` les fait écrire, sans attendre le rattrapage.
    private var myProfileIsSearchIndexed = true

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
        blocksListener?.remove()
    }

    // MARK: - Lecture

    func isFollowing(_ uid: String) -> Bool { followingUIDs.contains(uid) }

    func isBlocked(_ uid: String) -> Bool { blockedUIDs.contains(uid) }

    var myUID: String? { Auth.auth().currentUser?.uid }

    /// Le nombre de pastilles à afficher sur la cloche. Les abonnés récents y
    /// comptent autant que les recommandations : les deux appellent une action.
    var unreadCount: Int { suggestions.count + recentFollowers.count }

    // MARK: - Écriture

    /// Voir `SocialServicing.handleAvailability` — pas d'authentification
    /// requise, contrairement à tout le reste de ce store.
    func handleAvailability(_ handle: String) async throws -> Bool {
        try await client.handleAvailability(handle)
    }

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

        let trimmed = Self.publicName(displayName)
        guard !trimmed.isEmpty else { return }

        try? await client.setPublicName(trimmed)
    }

    /// Le nom public, tel que les règles Firestore l'acceptent : sans blancs
    /// autour, et pas plus de 60 caractères Unicode. On coupe entre deux
    /// caractères affichés, pour ne jamais laisser un emoji à moitié.
    nonisolated static func publicName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var kept = ""
        var scalars = 0
        for character in trimmed {
            scalars += character.unicodeScalars.count
            guard scalars <= 60 else { break }
            kept.append(character)
        }
        return kept
    }

    /// Garde `publicProfiles.displayName` en phase avec le nom déclaré dans
    /// les réglages — sans ça, la recherche par prénom/nom trouverait un nom
    /// périmé, et le profil affiché à vos abonnés ne serait plus le vôtre.
    ///
    /// Par le serveur : c'est lui qui calcule les préfixes de recherche du
    /// nom, et le client n'a pas le droit de les écrire (n'importe qui
    /// pourrait sinon apparaître quand on cherche le nom d'un autre). Sans
    /// effet si aucun pseudo n'a encore été choisi : rien à synchroniser avant
    /// qu'un profil public existe. Le nom inchangé ne repart pas.
    func syncDisplayName(_ name: String) async {
        guard let profile = myProfile else { return }
        let trimmed = Self.publicName(name)
        guard !trimmed.isEmpty,
              trimmed != profile.displayName || !myProfileIsSearchIndexed
        else { return }
        do {
            try await client.setPublicName(trimmed)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Bascule le suivi, une fois le serveur d'accord.
    ///
    /// Plus de mise à jour optimiste (règle du 11 août 2026) : le bouton
    /// montre son attente, et l'état ne change qu'une fois le suivi écrit.
    /// L'écouteur de `following` le confirmera de toute façon ; le poser ici
    /// évite seulement d'attendre son aller-retour.
    func toggleFollow(uid: String) async throws {
        if followingUIDs.contains(uid) {
            try await client.unfollow(uid: uid)
            followingUIDs.remove(uid)
        } else {
            try await client.follow(uid: uid)
            followingUIDs.insert(uid)
        }
    }

    /// Suit ou ne suit plus, en tenant le bouton occupé le temps de l'écriture.
    /// Rend `false` si l'écriture a échoué : à l'appelant de le dire. Un
    /// second toucher pendant l'écriture n'est pas un échec, il est ignoré.
    @discardableResult
    func toggleFollowTracked(uid: String) async -> Bool {
        guard !followsInFlight.contains(uid) else { return true }
        followsInFlight.insert(uid)
        defer { followsInFlight.remove(uid) }
        do {
            try await toggleFollow(uid: uid)
            return true
        } catch {
            return false
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

    /// La recherche de profils, par n'importe quel mot du nom ou du pseudo.
    ///
    /// Trois requêtes à un seul champ, en parallèle, fusionnées :
    /// - `searchPrefixes`, que le serveur remplit de tous les débuts de mots du
    ///   nom et du pseudo : c'est elle qui trouve Léa Martin quand on tape
    ///   « martin ». Firestore n'interroge qu'un mot à la fois ; les mots
    ///   suivants filtrent ensuite côté client ;
    /// - le préfixe du pseudo et celui du nom entier, comme avant : un profil
    ///   que le rattrapage n'a pas encore touché reste trouvable par là.
    ///
    /// Firestore indexe chaque champ pris seul : rien à déclarer, et c'est ce
    /// qui interdit un `OR` entre champs. Le `\u{f8ff}` est la borne haute
    /// d'un préfixe. Un profil trouvé par deux voies ne compte qu'une fois.
    /// Un caractère suffit : le `@` de la recherche y mène.
    func searchProfiles(matching query: String, limit: Int = 25) async throws -> [PublicProfile] {
        let needle = Self.normalize(query)
        let words = Self.searchWords(needle)
        // Le premier mot tel que tapé, normalisé comme le serveur : pas depuis
        // `needle`, dont le repli a déjà changé « ø » en « o ».
        guard !words.isEmpty, let typedFirst = Self.searchWords(query).first else { return [] }
        let me = myUID

        async let byWord = wordQuery(Self.serverPrefix(typedFirst), limit: limit)
        async let byHandle = prefixQuery(field: "handleNormalized", needle: needle, limit: limit)
        async let byName = prefixQuery(field: "displayNameNormalized", needle: needle, limit: limit)

        let wordHits = try await byWord
        let handleHits = try await byHandle
        let nameHits = try await byName

        var seen = Set<String>()
        var results: [PublicProfile] = []
        // Les correspondances du pseudo d'abord : on tape le plus souvent le
        // pseudo de quelqu'un qu'on connaît. La recherche lit Firestore sans
        // passer par le serveur : c'est donc ici qu'on écarte les profils que
        // j'ai bloqués. Ceux qui m'ont bloqué restent dans les résultats (leurs
        // blocages ne se lisent pas d'ici), mais le serveur refuse ensuite de
        // montrer leur profil ou de les suivre.
        for profile in handleHits + wordHits + nameHits
        where profile.id != me && !blockedUIDs.contains(profile.id) {
            guard Self.matchesEveryWord(profile, words: words) else { continue }
            guard seen.insert(profile.id).inserted else { continue }
            results.append(profile)
        }
        return Array(results.prefix(limit))
    }

    /// Le mot tel que le serveur l'a rangé dans `searchPrefixes` : même
    /// normalisation que `normalizeSearchText` (décomposition, accents
    /// combinants retirés, minuscules), et vingt points de code au plus, là où
    /// s'arrêtent les préfixes stockés. Le repli de `normalize` irait plus
    /// loin (« ø » devient « o ») et ne trouverait alors rien. Le filtre des
    /// mots suivants fait le reste.
    private static func serverPrefix(_ word: String) -> String {
        let stripped = word.decomposedStringWithCanonicalMapping.unicodeScalars
            .filter { !(0x300...0x36F).contains($0.value) }
        let lowered = String(String.UnicodeScalarView(stripped)).lowercased()
        return String(String.UnicodeScalarView(lowered.unicodeScalars.prefix(20)))
    }

    /// Les mots d'une saisie ou d'un nom, coupés comme le serveur les coupe.
    nonisolated static func searchWords(_ normalized: String) -> [String] {
        normalized
            .split(whereSeparator: { $0.isWhitespace || "-'’._".contains($0) })
            .map(String.init)
    }

    /// Chaque mot tapé doit commencer un mot du nom ou du pseudo : « lea mar »
    /// trouve Léa Martin, pas Léa Dumont.
    private static func matchesEveryWord(_ profile: PublicProfile, words: [String]) -> Bool {
        let handle = normalize(profile.handle)
        let haystack = searchWords(normalize(profile.displayName)) + searchWords(handle) + [handle]
        return words.allSatisfy { word in haystack.contains { $0.hasPrefix(word) } }
    }

    private func wordQuery(_ word: String, limit: Int) async throws -> [PublicProfile] {
        do {
            let snapshot = try await db.collection("publicProfiles")
                .whereField("searchPrefixes", arrayContains: word)
                .limit(to: limit)
                .getDocuments()
            return snapshot.documents.compactMap { PublicProfile(id: $0.documentID, data: $0.data()) }
        } catch {
            throw Self.readFailure(error)
        }
    }

    private func prefixQuery(field: String, needle: String, limit: Int) async throws -> [PublicProfile] {
        do {
            let snapshot = try await db.collection("publicProfiles")
                .whereField(field, isGreaterThanOrEqualTo: needle)
                .whereField(field, isLessThan: needle + "\u{f8ff}")
                .limit(to: limit)
                .getDocuments()
            return snapshot.documents.compactMap { PublicProfile(id: $0.documentID, data: $0.data()) }
        } catch {
            throw Self.readFailure(error)
        }
    }

    // MARK: - Profils à suivre

    /// Charge les profils à suivre. Sans `force`, un chargement de moins d'une
    /// heure suffit : l'accueil et la recherche le partagent, et le serveur
    /// garde de toute façon son calcul douze heures.
    func loadFollowSuggestions(force: Bool = false) async {
        if case .loading = followSuggestionsPhase { return }
        if !force, let loadedAt = followSuggestionsLoadedAt,
           Date().timeIntervalSince(loadedAt) < 3600 {
            return
        }
        followSuggestionsPhase = .loading
        do {
            let page: FollowSuggestionsPage
            #if DEBUG
            if let fixture = DebugFixtures.followSuggestions {
                page = fixture
            } else {
                page = try await client.followSuggestions()
            }
            #else
            page = try await client.followSuggestions()
            #endif
            let me = myUID
            // Le serveur filtre déjà les blocages ; un blocage posé pendant le
            // chargement ne doit pas faire revenir la carte.
            followSuggestions = page.suggestions.filter { $0.id != me && !blockedUIDs.contains($0.id) }
            followingCountAtLoad = page.followingCount
            followSuggestionsOnHome = followSuggestions.count >= Self.homeRowMinimum
            followSuggestionsLeadHome = page.followingCount < Self.fewFollowings
                || followSuggestions.contains(where: \.followsYou)
            followSuggestionsLoadedAt = Date()
            followSuggestionsPhase = .loaded
        } catch is CancellationError {
            followSuggestionsPhase = followSuggestionsLoadedAt == nil ? .idle : .loaded
        } catch {
            // Ce qui était déjà affiché reste : une erreur ne vide pas une
            // rangée qui marchait.
            followSuggestionsPhase = .failed(Self.message(for: error))
        }
    }

    /// Retire un profil des propositions, une fois le serveur d'accord.
    /// Rend `false` si l'écriture a échoué : la carte reste alors en place.
    @discardableResult
    func dismissFollowSuggestion(uid: String) async -> Bool {
        guard !dismissalsInFlight.contains(uid) else { return true }
        dismissalsInFlight.insert(uid)
        defer { dismissalsInFlight.remove(uid) }
        do {
            #if DEBUG
            if DebugFixtures.followSuggestions == nil {
                try await client.dismissFollowSuggestion(uid: uid)
            }
            #else
            try await client.dismissFollowSuggestion(uid: uid)
            #endif
            followSuggestions.removeAll { $0.id == uid }
            return true
        } catch {
            return false
        }
    }

    // MARK: - Blocage et signalement

    /// Bloque un profil, une fois le serveur d'accord.
    ///
    /// Pas de mise à jour optimiste (règle du 11 août 2026) : l'appelant montre
    /// l'attente par `blocksInFlight`, et rien ne bouge avant la réponse. Le
    /// serveur a alors défait les abonnements et supprimé les recommandations
    /// dans les deux sens ; les écouteurs le confirmeront, on le pose ici pour
    /// que la personne quitte tout de suite les listes affichées.
    func block(uid: String) async throws {
        guard !blocksInFlight.contains(uid) else { return }
        blocksInFlight.insert(uid)
        defer { blocksInFlight.remove(uid) }
        try await client.block(uid: uid)
        blockedUIDs.insert(uid)
        forget(uid)
    }

    /// Débloque. Aucun abonnement ne revient : il faudra se suivre à nouveau.
    func unblock(uid: String) async throws {
        guard !blocksInFlight.contains(uid) else { return }
        blocksInFlight.insert(uid)
        defer { blocksInFlight.remove(uid) }
        #if DEBUG
        // La liste de démonstration n'existe pas côté serveur.
        if DebugFixtures.blockedUsers == nil {
            try await client.unblock(uid: uid)
        }
        #else
        try await client.unblock(uid: uid)
        #endif
        blockedUIDs.remove(uid)
    }

    /// Les comptes bloqués, avec leur profil public, pour la liste des réglages.
    func blockedAccounts() async throws -> [PublicProfile] {
        #if DEBUG
        if let fixture = DebugFixtures.blockedUsers {
            return fixture
        }
        #endif
        return try await client.blockedUsers()
    }

    func report(uid: String, reason: ReportReason, note: String?, context: ReportContext?) async throws {
        try await client.report(uid: uid, reason: reason, note: note, context: context)
    }

    /// Retire un profil bloqué de tout ce que le Hall affiche déjà.
    private func forget(_ uid: String) {
        followingUIDs.remove(uid)
        suggestions.removeAll { $0.fromUid == uid }
        recentFollowers.removeAll { $0.id == uid }
        followSuggestions.removeAll { $0.id == uid }
    }

    /// Moins de trois cartes ne font pas une rangée : rien plutôt qu'un vide.
    private static let homeRowMinimum = 3
    /// En dessous, on suit trop peu de monde pour que l'accueil le taise.
    private static let fewFollowings = 5

    private static func message(for error: any Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    func profile(uid: String) async throws -> PublicProfile? {
        do {
            let snapshot = try await db.collection("publicProfiles").document(uid).getDocument()
            guard let data = snapshot.data() else { return nil }
            return PublicProfile(id: snapshot.documentID, data: data)
        } catch {
            throw Self.readFailure(error)
        }
    }

    /// Les profils d'une liste d'abonnés/abonnements.
    ///
    /// Les sous-collections `following`/`followers` ne portent qu'une date : le
    /// profil affichable vit dans `publicProfiles`. On les recharge par paquets
    /// de dix, la limite d'un `in` Firestore. Un paquet en échec fait échouer
    /// l'ensemble : une liste amputée sans le dire mentirait autant qu'une
    /// liste vide.
    func profiles(uids: [String]) async throws -> [PublicProfile] {
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
                throw Self.readFailure(error)
            }
        }
        return out
    }

    func followingUIDs(of uid: String) async throws -> [String] {
        try await linkedUIDs(of: uid, collection: "following")
    }

    func followerUIDs(of uid: String) async throws -> [String] {
        try await linkedUIDs(of: uid, collection: "followers")
    }

    private func linkedUIDs(of uid: String, collection: String) async throws -> [String] {
        do {
            let snapshot = try await db.collection("users").document(uid)
                .collection(collection).getDocuments()
            return snapshot.documents.map(\.documentID)
        } catch {
            throw Self.readFailure(error)
        }
    }

    /// Ce que remonte une lecture Firestore ratée. Ces lectures rendaient `[]`
    /// en cas d'échec, et l'écran affichait alors « Tu ne suis personne » à
    /// quelqu'un qui n'avait simplement pas de réseau. L'erreur brute de
    /// Firestore est en anglais technique : on la remplace par la phrase des
    /// autres appels réseau du Hall. L'annulation reste une annulation, pour
    /// que l'appelant la taise.
    private static func readFailure(_ error: any Error) -> any Error {
        if error is CancellationError { return error }
        return SocialError.transport(
            message: String(localized: "On n'arrive pas à joindre le serveur. Vérifie ta connexion internet.", bundle: .app)
        )
    }

    // MARK: - Listeners

    private var db: Firestore { Firestore.firestore() }

    private static func followersSeenKey(_ uid: String) -> String {
        "cinechill_followers_seen_\(uid)"
    }

    /// Minuscules et sans accents : « lea » doit trouver « Léa ».
    nonisolated static func normalize(_ raw: String) -> String {
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
                self.followSuggestions = []
                self.followSuggestionsPhase = .idle
                self.followSuggestionsLoadedAt = nil
                self.followingCountAtLoad = 0
                self.followSuggestionsOnHome = false
                self.followSuggestionsLeadHome = false
                self.blockedUIDs = []
                self.blocksInFlight = []

                guard let uid = user?.uid else { return }
                self.startProfileListener(uid: uid)
                self.startFollowingListener(uid: uid)
                self.startSuggestionsListener(uid: uid)
                self.startFollowersListener(uid: uid)
                self.startBlocksListener(uid: uid)
            }
        }
    }

    private func teardownListeners() {
        profileListener?.remove()
        followingListener?.remove()
        suggestionsListener?.remove()
        followersListener?.remove()
        blocksListener?.remove()
        profileListener = nil
        followingListener = nil
        suggestionsListener = nil
        followersListener = nil
        blocksListener = nil
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
                        self.myProfileIsSearchIndexed = data["searchPrefixes"] is [Any]
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
                        // Le serveur les supprime au blocage ; un instantané
                        // parti avant ne doit pas les faire revenir.
                        .filter { !self.blockedUIDs.contains($0.fromUid) }
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
                        .filter { !self.blockedUIDs.contains($0) }

                    guard !fresh.isEmpty else {
                        self.recentFollowers = []
                        return
                    }
                    // Un échec garde les abonnés déjà affichés : le prochain
                    // snapshot réessaiera, et vider la liste ferait croire
                    // qu'ils sont partis.
                    do {
                        // Relu après l'attente : un blocage a pu tomber pendant.
                        self.recentFollowers = try await self.profiles(uids: fresh)
                            .filter { !self.blockedUIDs.contains($0.id) }
                    } catch {
                        self.errorMessage = error.localizedDescription
                    }
                }
            }
    }

    /// Lisible par son seul propriétaire. Une erreur garde l'état connu : la
    /// vider ferait réapparaître un bouton « Suivre » sur un profil bloqué.
    private func startBlocksListener(uid: String) {
        blocksListener = db.collection("users").document(uid)
            .collection("blocks")
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor [weak self] in
                    guard let self, error == nil, let snapshot else { return }
                    let blocked = Set(snapshot.documents.map(\.documentID))
                    self.blockedUIDs = blocked
                    for uid in blocked { self.forget(uid) }
                }
            }
    }
}

/// Où en est le chargement des profils à suivre.
enum FollowSuggestionsPhase: Equatable {
    case idle
    case loading
    case loaded
    case failed(String)
}
