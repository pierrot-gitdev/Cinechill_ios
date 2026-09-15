//
//  OnboardingTour.swift
//  Cinechill_iOS
//

import Foundation
import SwiftUI
import FirebaseAuth
import FirebaseFirestore

/// La prise en main — « Le Cartouche ».
///
/// L'application se présente elle-même. Elle passe d'un onglet à l'autre toute
/// seule, s'immobilise, et une plaque posée en bas de l'écran dit ce qu'on
/// regarde et à quoi ça sert. **On ne demande rien** : pas un geste, pas un
/// réglage, pas une saisie. On lit, on appuie sur « Suivant », et on peut sortir
/// à tout moment.
///
/// Sur un plan d'architecte, le cartouche est le bloc en bas de la planche qui
/// nomme le dessin. C'est exactement son rôle ici, et c'est le seul objet neuf
/// de toute la conception.
///
/// Trois décisions structurent cet objet :
///
/// - **Une étape, un écran, une idée.** Sept étapes dans l'ordre de la barre
///   d'onglets, de gauche à droite : apprendre le parcours, c'est déjà apprendre
///   où sont les choses. La lampe du Seuil s'en charge sans qu'on l'écrive.
///   CinéMatch en occupe deux, parce qu'il en porte deux depuis sa refonte :
///   ce qu'il fait (le salon), et comment on le débloque (la porte).
/// - **Rien ne s'avance tout seul.** Aucun minuteur. On ne lit pas tous à la
///   même vitesse, et se faire déplacer en cours de lecture est la pire chose
///   qu'une visite guidée puisse faire.
/// - **Deux boutons en tout.** « Suivant » et « Passer ». Pas de retour
///   arrière : sept explications de deux lignes ne se relisent pas, et un
///   troisième objet coûterait plus qu'il ne rendrait.
@Observable
@MainActor
final class OnboardingTour {

    // MARK: - Les sept étapes

    enum Step: Int, CaseIterable {
        case accueil = 0
        /// Le salon de CinéMatch, déverrouillé pour la visite : ce qu'on obtient.
        case cinematch
        /// La porte, telle qu'un compte neuf la trouve : ce qu'il faut pour
        /// l'obtenir. Même onglet que l'étape précédente.
        case porte
        case decouvrir
        case galerie
        case watchlist
        /// La sortie, jouée sur l'accueil : la barre récapitule, puis on entre.
        case sortie

        /// L'onglet où l'étape se joue. Voir `MainTabView` pour l'ordre :
        /// 0 Accueil · 1 CinéMatch · 2 Découvrir · 3 Galerie · 4 Watchlist.
        var tab: Int {
            switch self {
            case .accueil, .sortie: 0
            case .cinematch, .porte: 1
            case .decouvrir: 2
            case .galerie: 3
            case .watchlist: 4
            }
        }

        /// Le titre dit le **but**, jamais le nom de l'écran — celui-ci est déjà
        /// écrit dans le plafond, juste au-dessus.
        var title: String {
            switch self {
            case .accueil: String(localized: "L'accueil", bundle: .app)
            case .cinematch: String(localized: "Marre de perdre 30 min à trouver un film ?", bundle: .app)
            case .porte: String(localized: "CinéMatch se débloque", bundle: .app)
            case .decouvrir: String(localized: "Swipe pour remplir ta galerie de films", bundle: .app)
            case .galerie: String(localized: "Tous les films que tu as vus", bundle: .app)
            case .watchlist: String(localized: "La liste des films à regarder", bundle: .app)
            case .sortie: String(localized: "À toi de jouer", bundle: .app)
            }
        }

        /// Deux lignes maximum. Si l'explication n'y tient pas, c'est que
        /// l'étape porte deux idées et qu'il faut en retirer une.
        var detail: String {
            switch self {
            case .accueil:
                String(localized: "Découvre ici les films actuellement au cinéma, les plus populaires du moment ainsi que les suggestions Cinechill basées sur tes goûts.", bundle: .app)
            case .cinematch:
                String(localized: "Réponds à deux questions, compare quelques films que tu as vus, et CinéMatch te propose cinq films pour ce soir.", bundle: .app)
            case .porte:
                String(localized: "Il s'ouvre quand tu remplis quelques critères, comme ajouter des films vus à ta galerie.", bundle: .app)
            case .decouvrir:
                String(localized: "Indique les films que tu as vus et ajoute ceux que tu veux voir.", bundle: .app)
            case .galerie:
                String(localized: "Plus tu en ajoutes, mieux Cinechill connaît tes goûts.", bundle: .app)
            case .watchlist:
                String(localized: "Plus besoin de noter quelque part les films à voir : ils sont tous ici.", bundle: .app)
            case .sortie:
                String(localized: "Commence par ajouter les films que tu as vus : c'est la première étape pour débloquer CinéMatch.", bundle: .app)
            }
        }

        var isLast: Bool { self == .sortie }
    }

    // MARK: - État

    /// L'étape courante, ou `nil` quand il n'y a pas de visite en cours.
    private(set) var step: Step?

    var isRunning: Bool { step != nil }

    /// Le préambule : la feuille des plateformes, demandée à un compte neuf avant
    /// la première étape. Rien n'est enregistré de la visite tant qu'elle est
    /// ouverte ; fermer l'app à ce moment la redemande au lancement suivant.
    private(set) var asksPlatforms = false
    /// La feuille a reçu sa réponse : la visite part quand elle a fini de se
    /// retirer, pas pendant, pour que les deux mouvements ne se superposent pas.
    private var platformsAnswered = false
    /// La dernière étape occupe la barre entière : les cinq onglets s'allument
    /// et la lampe les parcourt une dernière fois.
    var isClosing: Bool { step == .sortie }

    var progress: Double {
        guard let step else { return 1 }
        return Double(step.rawValue + 1) / Double(Step.allCases.count)
    }

    /// Le rang affiché, « 3 / 6 ».
    var counter: String {
        guard let step else { return "" }
        return "\(step.rawValue + 1) / \(Step.allCases.count)"
    }

    /// Demande de changement d'onglet. `MainTabView` observe le jeton plutôt que
    /// l'onglet : deux étapes se jouent sur l'accueil, et passer de la dernière
    /// à la première ne changerait donc pas la valeur.
    private(set) var tabRequest = 0
    private(set) var requestedTab = Step.accueil.tab

    private let defaults: UserDefaults
    private var uid: String?

    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults ?? .standard
    }

    // MARK: - Démarrage

    /// Décide s'il y a lieu de présenter l'application, et reprend là où on en
    /// était le cas échéant.
    ///
    /// À n'appeler qu'une fois la bibliothèque **réellement chargée** : une
    /// galerie encore vide parce que Firestore n'a pas répondu se confond avec
    /// une galerie vide parce que le compte est neuf, et l'application se
    /// mettrait à présenter ses écrans à quelqu'un qui les utilise depuis six
    /// mois.
    func startIfNeeded(galleryCount: Int, watchlistCount: Int) async {
        guard step == nil, !asksPlatforms, let uid = Auth.auth().currentUser?.uid else { return }

        self.uid = uid

        // Le local d'abord, et sans attendre : c'est le cas courant — une
        // application rouverte sur une visite en cours — et faire clignoter le
        // premier écran le temps d'un aller-retour pour retrouver ce qu'on a
        // déjà sous la main serait absurde.
        if let local = loadLocal(uid: uid) {
            guard !local.done, !local.isExpired else { return }
            resume(at: local.resumePoint)
            return
        }

        // Rien en local mais une bibliothèque déjà garnie : le compte n'est pas
        // neuf — réinstallation, second appareil. On ne demande même pas au
        // serveur.
        guard galleryCount == 0, watchlistCount == 0 else { return }

        // Bibliothèque vide et aucune trace ici : seul le serveur sait si la
        // visite a déjà eu lieu ailleurs. L'attente est courte — la connexion
        // Firestore est déjà chaude, puisque c'est la réponse de l'écoute de la
        // galerie qui nous a amenés ici.
        if let remote = await fetchRemote(uid: uid) {
            saveLocal(remote, uid: uid)
            guard !remote.done, !remote.isExpired else { return }
            resume(at: remote.resumePoint)
            return
        }

        // Compte neuf : les plateformes d'abord, la visite ensuite. Une visite
        // reprise en cours de route, elle, a déjà eu sa réponse.
        askPlatforms()
    }

    private func askPlatforms() {
        platformsAnswered = false
        asksPlatforms = true
    }

    /// « Continuer » ou « Je n'ai aucune plateforme » : la feuille se retire.
    /// Les plateformes sont déjà enregistrées, à chaque toucher.
    func answerPlatforms() {
        guard asksPlatforms else { return }
        Haptics.selection()
        platformsAnswered = true
        asksPlatforms = false
    }

    /// La feuille a fini de se retirer : la visite commence.
    func platformsSheetDidDismiss() {
        guard platformsAnswered, step == nil else { return }
        platformsAnswered = false
        resume(at: .accueil)
    }

    private func resume(at step: Step) {
        // L'application se réduit en vignette : le mouvement dit qu'on entre
        // en présentation, là où un saut ferait croire à un écran changé.
        withAnimation(.easeInOut(duration: 0.32)) { self.step = step }
        persist()
        requestTab(step.tab)
    }

    // MARK: - Les deux seules actions

    func next() {
        guard let current = step else { return }
        guard let following = Step(rawValue: current.rawValue + 1) else {
            // La visite s'achève sur « Commencer » : elle dépose sur Découvrir,
            // l'étape qui construit la galerie et fait tourner les suggestions.
            finish(navigatingTo: .decouvrir)
            return
        }
        Haptics.selection()
        withAnimation(Metrics.shift) { step = following }
        persist()
        requestTab(following.tab)
    }

    /// « Passer » : la visite est terminée, et **elle ne reviendra pas**. Rien
    /// ne la redemandera — ni une bannière, ni une ligne dans les réglages.
    /// Quelqu'un qui refuse une présentation la refuse pour de bon.
    func skip() {
        Haptics.selection()
        finish(navigatingTo: nil)
    }

    private func finish(navigatingTo destination: Step?) {
        guard step != nil else { return }
        withAnimation(.easeOut(duration: 0.3)) { step = nil }
        if let destination { requestTab(destination.tab) }
        guard let uid else { return }
        let record = Record(done: true, step: 0, startedAt: .now)
        saveLocal(record, uid: uid)
        // Écriture immédiate : le différé pourrait être annulé par la fermeture
        // de l'application, et une visite terminée qui repart au lancement
        // suivant est le pire des défauts.
        Task { await Self.writeRemote(record, uid: uid) }
    }

    private func requestTab(_ tab: Int) {
        requestedTab = tab
        tabRequest &+= 1
    }

    // MARK: - Persistance

    /// L'état tenu d'un lancement à l'autre. Deux champs et une date : c'est
    /// tout ce qu'une visite linéaire a besoin de se rappeler.
    private struct Record {
        var done: Bool
        var step: Int
        var startedAt: Date

        /// Au-delà, une visite jamais reprise ne revient plus. Le seuil est
        /// délibérément court : une présentation qu'on retrouve une semaine
        /// après s'être inscrit ne présente plus rien, elle interrompt.
        var isExpired: Bool { Date.now.timeIntervalSince(startedAt) > 7 * 24 * 3600 }

        /// Une valeur enregistrée qu'on ne sait plus lire vaut reprise au début —
        /// jamais absence de visite.
        var resumePoint: Step { Step(rawValue: step) ?? .accueil }
    }

    private func key(for uid: String) -> String { "onboarding.tour.\(uid)" }

    private func loadLocal(uid: String) -> Record? {
        guard let raw = defaults.dictionary(forKey: key(for: uid)) else { return nil }
        return Record(
            done: raw["done"] as? Bool ?? false,
            step: raw["step"] as? Int ?? 0,
            startedAt: raw["startedAt"] as? Date ?? .now
        )
    }

    private func saveLocal(_ record: Record, uid: String) {
        defaults.set([
            "done": record.done,
            "step": record.step,
            "startedAt": record.startedAt,
        ], forKey: key(for: uid))
    }

    private func persist() {
        guard let uid, let step else { return }
        let existing = loadLocal(uid: uid)
        let record = Record(done: false, step: step.rawValue, startedAt: existing?.startedAt ?? .now)
        saveLocal(record, uid: uid)
        Task { await Self.writeRemote(record, uid: uid) }
    }

    private func fetchRemote(uid: String) async -> Record? {
        let snapshot = try? await Firestore.firestore()
            .collection("users").document(uid)
            .collection("preferences").document("onboarding")
            .getDocument()
        guard let data = snapshot?.data(), snapshot?.exists == true else { return nil }
        return Record(
            done: data["tourDone"] as? Bool ?? false,
            step: data["tourStep"] as? Int ?? 0,
            startedAt: (data["startedAt"] as? Timestamp)?.dateValue() ?? .now
        )
    }

    /// L'échec est silencieux, et c'est voulu : le journal local reste la source
    /// de vérité de la session en cours. Une prise en main n'a aucune raison de
    /// signaler une panne réseau — surtout pas la sienne.
    private static func writeRemote(_ record: Record, uid: String) async {
        try? await Firestore.firestore()
            .collection("users").document(uid)
            .collection("preferences").document("onboarding")
            .setData([
                "tourDone": record.done,
                "tourStep": record.step,
                "startedAt": Timestamp(date: record.startedAt),
            ], merge: true)
    }
}
