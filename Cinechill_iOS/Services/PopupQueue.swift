//
//  PopupQueue.swift
//  Cinechill_iOS
//

import Foundation
import Observation

/// Le guichet des fenêtres : une seule à la fois, dans un ordre fixe.
///
/// Découvrir pouvait empiler un badge, une étape de la Porte, un palier, une
/// feuille de saga et une planche de coups de cœur sur un même geste, chacune
/// présentée de son côté et vérifiant à la main deux ou trois des autres. Les
/// badges et la Porte, annoncés depuis le conteneur des onglets, ne savaient
/// rien de Découvrir : ils se posaient par-dessus ses feuilles.
///
/// Chaque fenêtre demande désormais son tour ici et ne s'affiche que quand
/// `current` la nomme. Trois règles tiennent l'écran :
///
/// - **Une à la fois**, avec un temps de respiration entre deux : la suivante
///   n'arrive pas dans le mouvement de celle qui part.
/// - **La plus importante d'abord** quand plusieurs attendent : l'ordre de
///   `Kind`.
/// - **Ce qui ne vaut qu'à l'instant se perd** plutôt que d'attendre : une
///   feuille de saga proposée trois fenêtres plus tard ne se rattache plus au
///   film qui l'a ouverte. Et une fenêtre facultative ne suit jamais de près
///   une autre : on ne harcèle pas.
@Observable
@MainActor
final class PopupQueue {
    /// Les fenêtres, de la plus prioritaire à la moins prioritaire.
    enum Kind: Int, Comparable, CaseIterable {
        /// La mosaïque de départ : la suite de l'onboarding.
        case startGrid
        /// La planche des gestes, à la première venue sur Découvrir.
        case guide
        /// Une étape de la Porte de CinéMatch gagnée.
        case door
        /// Un badge ou une distinction.
        case badge
        /// « N films sur 100 » : le palier de la galerie.
        case goal
        /// La feuille de saga, ou « dans la même veine », après un « vu ».
        case saga
        /// La mosaïque de relance, quand le deck ne trouve plus rien.
        case relanceGrid
        /// La demande d'autorisation des notifications.
        case notificationPrompt
        /// La planche « lesquels as-tu adorés ? ».
        case loveGrid
        /// Le palier de la session (10, 25 films ce soir).
        case sessionMilestone

        static func < (lhs: Kind, rhs: Kind) -> Bool { lhs.rawValue < rhs.rawValue }

        /// Ne vaut qu'à l'instant du geste qui l'a demandée : perdue plutôt
        /// que différée quand l'écran est pris.
        var isMomentary: Bool {
            switch self {
            case .saga, .sessionMilestone, .loveGrid: true
            default: false
            }
        }

        /// Facultative : ne suit jamais de près une autre fenêtre.
        var isOptional: Bool {
            switch self {
            case .loveGrid, .sessionMilestone, .notificationPrompt: true
            default: false
            }
        }
    }

    /// La fenêtre affichée.
    private(set) var current: Kind?
    private var waiting: Set<Kind> = []
    private var lastClosedAt: Date = .distantPast
    private var promoteTask: Task<Void, Never>?

    /// La respiration entre deux fenêtres.
    private static let pause: Duration = .milliseconds(350)
    /// Une fenêtre facultative attend au moins ce délai après la précédente.
    private static let optionalGap: TimeInterval = 20

    var isBusy: Bool { current != nil || !waiting.isEmpty }

    /// Demande le tour de `kind`.
    ///
    /// - Returns: vrai si la fenêtre s'affiche tout de suite ou plus tard, faux
    ///   si elle est écartée : l'appelant oublie alors sa demande.
    @discardableResult
    func request(_ kind: Kind) -> Bool {
        // Une fenêtre momentanée déjà à l'écran ne se remplace pas : la
        // nouvelle feuille prenait sa place, la fermeture de la première
        // libérait le guichet, et la suivante ne pouvait plus se présenter.
        if current == kind { return !kind.isMomentary }
        if waiting.contains(kind) { return true }
        if kind.isOptional, Date.now.timeIntervalSince(lastClosedAt) < Self.optionalGap {
            return false
        }
        guard current == nil, promoteTask == nil else {
            if kind.isMomentary { return false }
            waiting.insert(kind)
            return true
        }
        current = kind
        return true
    }

    /// La fenêtre `kind` s'est fermée : la suivante prend son tour après la
    /// respiration.
    func finish(_ kind: Kind) {
        waiting.remove(kind)
        guard current == kind else { return }
        current = nil
        lastClosedAt = .now
        promoteNext()
    }

    /// Retire une demande qui n'a plus d'objet (l'offre a expiré).
    func withdraw(_ kind: Kind) {
        waiting.remove(kind)
        if current == kind { finish(kind) }
    }

    private func promoteNext() {
        guard !waiting.isEmpty, promoteTask == nil else { return }
        promoteTask = Task { [weak self] in
            try? await Task.sleep(for: Self.pause)
            guard let self else { return }
            self.promoteTask = nil
            guard self.current == nil, let next = self.waiting.min() else { return }
            self.waiting.remove(next)
            self.current = next
        }
    }
}
