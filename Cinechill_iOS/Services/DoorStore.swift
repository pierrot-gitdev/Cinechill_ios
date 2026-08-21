//
//  DoorStore.swift
//  Cinechill_iOS
//

import Foundation

/// L'état de la porte, tenu pour toute l'application.
///
/// Il vit à la racine et non dans l'onglet CinéMatch, pour une raison
/// précise : **un artéfact se gagne ailleurs qu'à l'endroit où il s'affiche**.
/// On balaie une carte dans Découvrir, on pose un cœur depuis la galerie, on
/// range un film dans la watchlist — et c'est à cet instant-là qu'il faut le
/// dire, pas à la prochaine visite de l'onglet.
///
/// C'est aussi lui qui décide de ce qui se fête : la porte, elle, ne fait que
/// se peindre sur ce qu'il raconte.
@Observable
@MainActor
final class DoorStore {
    /// Les artéfacts déjà fêtés, d'un lancement à l'autre. Absente, la clé veut
    /// dire « jamais mesuré » : la première réponse du serveur prend alors
    /// l'existant pour acquis sans le fêter, sinon un compte déjà riche
    /// ouvrirait sur une rafale de célébrations.
    private static let celebratedKey = "cinematch.doorCelebratedKeys"

    private let client: any RecommendationFetching

    private(set) var door: DoorState
    /// Le serveur a-t-il déjà raconté cette porte ? Tant que non, on n'affiche
    /// qu'un état plausible tiré du cache, et rien ne se fête.
    private(set) var hasMeasured = false
    /// L'artéfact tout juste gagné, à célébrer puis à remettre à `nil`.
    private(set) var celebration: DoorArtifactKey?

    private var isRefreshing = false
    private var isBootstrapping = false
    private var didBootstrap = false

    /// Plafond de rappels du rattrapage. Le serveur borne chaque passe dans le
    /// temps ; une galerie ordinaire tient en une seule.
    private static let maximumCatchUpPasses = 12

    init(client: any RecommendationFetching = BackendRecommendationClient()) {
        self.client = client
        self.door = DoorState.cached ?? .initial
    }

    /// La mise à niveau de l'existant, une fois par ouverture de l'app.
    ///
    /// **L'ordre compte, et c'est tout l'objet de cette méthode.** Le rattrapage
    /// fait remonter d'un coup les positions de la galerie et les « Je l'ai
    /// adoré » déjà dits : sans lui d'abord, la mesure suivante lirait tout ça
    /// comme des artéfacts tout juste gagnés et l'écran partirait en cascade
    /// d'annonces. Ce que le rattrapage remonte est un dû, pas un exploit — on
    /// pose donc l'état de référence **après** lui, en silence.
    func bootstrap() async {
        guard !didBootstrap else { return }
        didBootstrap = true
        isBootstrapping = true
        defer { isBootstrapping = false }

        for _ in 0 ..< Self.maximumCatchUpPasses {
            guard let done = try? await client.backfillGallery() else { break }
            if done { break }
        }
        await measure(announcing: false)
    }

    /// Remesure la porte. Ne lève jamais : une porte qu'on n'a pas pu remesurer
    /// reste celle qu'on connaissait, ce qui vaut mieux qu'un écran vide.
    func refresh() async {
        // Rien ne s'annonce tant que l'existant n'a pas fini de remonter.
        guard !isBootstrapping else { return }
        await measure(announcing: true)
    }

    private func measure(announcing: Bool) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        guard let profile = try? await client.fetchTasteProfile(),
              let fresh = profile.door else { return }
        door = fresh
        DoorState.cache(fresh)
        hasMeasured = true

        guard announcing else {
            sealBaseline()
            return
        }
        pickCelebration()
    }

    /// Prend l'état courant pour acquis, sans rien fêter. C'est le point de
    /// départ à partir duquel un gain devient un gain.
    private func sealBaseline() {
        let lit = door.artifacts.filter(\.done).compactMap(\.artifactKey)
        UserDefaults.standard.set(
            lit.map(\.rawValue).joined(separator: ","), forKey: Self.celebratedKey
        )
    }

    /// La célébration vue, on passe à la suivante s'il y en a une : deux
    /// artéfacts gagnés d'un coup se fêtent l'un après l'autre, jamais
    /// ensemble.
    func dismissCelebration() {
        celebration = nil
        // Deux artéfacts gagnés du même geste s'annoncent l'un après l'autre,
        // avec un temps entre les deux : enchaînés dans la même image, ils se
        // lisent comme un clignotement plutôt que comme deux gains.
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            self?.pickCelebration()
        }
    }

    /// Le premier artéfact allumé qu'on n'a pas encore fêté.
    private func pickCelebration() {
        guard celebration == nil else { return }
        let lit = door.artifacts.filter(\.done).compactMap(\.artifactKey)
        let defaults = UserDefaults.standard

        guard let stored = defaults.string(forKey: Self.celebratedKey) else {
            defaults.set(lit.map(\.rawValue).joined(separator: ","), forKey: Self.celebratedKey)
            return
        }

        var seen = Set(stored.split(separator: ",").map(String.init))
        guard let fresh = lit.first(where: { !seen.contains($0.rawValue) }) else { return }
        seen.insert(fresh.rawValue)
        defaults.set(seen.sorted().joined(separator: ","), forKey: Self.celebratedKey)
        celebration = fresh
    }
}
