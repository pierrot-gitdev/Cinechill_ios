//
//  OnboardingTour.swift
//  Cinechill_iOS
//

import Foundation
import SwiftUI
import FirebaseAuth
import FirebaseFirestore

/// L'onboarding : cinq écrans plein écran, à la manière de Duolingo, avant
/// d'entrer dans l'application.
///
/// L'ordre est celui d'une promesse qu'on tient : ce que l'app fait pour toi
/// (le film du soir), ce que CinéMatch choisit, ce qu'il lui faut d'abord
/// (100 films vus), les plateformes qu'on lui donne, puis les quatre gestes de
/// Découvrir, montrés sans qu'on ait à les faire. « À toi de jouer » ferme le
/// parcours **sur Découvrir**, là où la galerie se remplit.
///
/// Une barre de progression en haut, un seul bouton en bas, toujours à la
/// même place : on avance d'un écran à l'autre sans chercher où appuyer. On
/// peut revenir en arrière, pas sauter : le parcours tient en une minute.
///
/// Le nom du type est celui de l'ancienne visite guidée, et ses clés de
/// persistance aussi : un compte qui a déjà fini l'ancienne visite
/// (`tourDone`) ne voit pas celle-ci.
@Observable
@MainActor
final class OnboardingTour {

    enum Step: Int, CaseIterable {
        case welcome = 0
        case cinematch
        case tastes
        case platforms
        case gestures

        /// Le cran de la barre de progression : l'accueil n'en a pas, les
        /// quatre écrans suivants la remplissent.
        var progress: Double { Double(rawValue) / Double(Step.allCases.count - 1) }
    }

    /// L'écran courant, ou `nil` quand l'onboarding n'est pas affiché.
    private(set) var step: Step?
    /// Le sens du dernier changement d'écran : la page suivante arrive par la
    /// droite, la précédente par la gauche.
    private(set) var movedForward = true

    var isRunning: Bool { step != nil }

    /// La version du parcours. Une visite de l'ancienne version restée en
    /// cours reprend au début : ses numéros d'étape ne veulent plus rien dire.
    private static let version = 2

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
    /// une galerie vide parce que le compte est neuf, et l'onboarding se
    /// montrerait à quelqu'un qui utilise l'app depuis six mois.
    func startIfNeeded(galleryCount: Int, watchlistCount: Int) async {
        guard step == nil, let uid = Auth.auth().currentUser?.uid else { return }
        self.uid = uid

        // Le local d'abord, et sans attendre : c'est le cas courant — une
        // application rouverte en plein onboarding.
        if let local = loadLocal(uid: uid) {
            guard !local.done, !local.isExpired else { return }
            show(local.resumePoint)
            return
        }

        // Rien en local mais une bibliothèque déjà garnie : le compte n'est pas
        // neuf (réinstallation, second appareil). On ne demande même pas au
        // serveur.
        guard galleryCount == 0, watchlistCount == 0 else { return }

        if let remote = await fetchRemote(uid: uid) {
            saveLocal(remote, uid: uid)
            guard !remote.done, !remote.isExpired else { return }
            show(remote.resumePoint)
            return
        }

        show(.welcome)
    }

    private func show(_ step: Step) {
        movedForward = true
        self.step = step
        persist()
    }

    // MARK: - Navigation

    func next() {
        guard let current = step else { return }
        guard let following = Step(rawValue: current.rawValue + 1) else {
            finish()
            return
        }
        movedForward = true
        step = following
        persist()
    }

    func back() {
        guard let current = step, let previous = Step(rawValue: current.rawValue - 1) else { return }
        movedForward = false
        step = previous
        persist()
    }

    /// « À toi de jouer » : l'onboarding est terminé et ne reviendra pas.
    ///
    /// La planche des gestes de Découvrir est marquée comme vue : le dernier
    /// écran vient de les montrer tous les quatre, et la retrouver à l'arrivée
    /// sur l'onglet ferait doublon.
    func finish() {
        guard step != nil else { return }
        step = nil
        defaults.set(true, forKey: "swipe.guideSeen")
        guard let uid else { return }
        let record = Record(done: true, step: 0, startedAt: .now, version: Self.version)
        saveLocal(record, uid: uid)
        // Écriture immédiate : un onboarding terminé qui repart au lancement
        // suivant est le pire des défauts.
        Task { await Self.writeRemote(record, uid: uid) }
    }

    // MARK: - Persistance

    /// L'état tenu d'un lancement à l'autre.
    private struct Record {
        var done: Bool
        var step: Int
        var startedAt: Date
        var version: Int

        /// Au-delà, un onboarding jamais repris ne revient plus : retrouvé une
        /// semaine après l'inscription, il ne présente plus rien, il interrompt.
        var isExpired: Bool { Date.now.timeIntervalSince(startedAt) > 7 * 24 * 3600 }

        /// Une valeur qu'on ne sait plus lire vaut reprise au début, jamais
        /// absence d'onboarding.
        var resumePoint: Step {
            guard version == OnboardingTour.version else { return .welcome }
            return Step(rawValue: step) ?? .welcome
        }
    }

    private func key(for uid: String) -> String { "onboarding.tour.\(uid)" }

    private func loadLocal(uid: String) -> Record? {
        guard let raw = defaults.dictionary(forKey: key(for: uid)) else { return nil }
        return Record(
            done: raw["done"] as? Bool ?? false,
            step: raw["step"] as? Int ?? 0,
            startedAt: raw["startedAt"] as? Date ?? .now,
            version: raw["version"] as? Int ?? 1
        )
    }

    private func saveLocal(_ record: Record, uid: String) {
        defaults.set([
            "done": record.done,
            "step": record.step,
            "startedAt": record.startedAt,
            "version": record.version,
        ], forKey: key(for: uid))
    }

    private func persist() {
        guard let uid, let step else { return }
        let existing = loadLocal(uid: uid)
        let record = Record(
            done: false,
            step: step.rawValue,
            startedAt: existing?.startedAt ?? .now,
            version: Self.version
        )
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
            startedAt: (data["startedAt"] as? Timestamp)?.dateValue() ?? .now,
            version: data["tourVersion"] as? Int ?? 1
        )
    }

    /// L'échec est silencieux, et c'est voulu : le journal local reste la source
    /// de vérité de la session en cours.
    private static func writeRemote(_ record: Record, uid: String) async {
        try? await Firestore.firestore()
            .collection("users").document(uid)
            .collection("preferences").document("onboarding")
            .setData([
                "tourDone": record.done,
                "tourStep": record.step,
                "tourVersion": record.version,
                "startedAt": Timestamp(date: record.startedAt),
            ], merge: true)
    }
}
