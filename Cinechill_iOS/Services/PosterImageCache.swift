//
//  PosterImageCache.swift
//  Cinechill_iOS
//

import SwiftUI
import UIKit

/// Cache mémoire d'affiches, avec préchargement.
///
/// `AsyncImage` ne sait pas précharger : chaque carte du deck partirait en
/// chargement au moment où elle devient visible, donc juste après un swipe —
/// exactement le moment où la fluidité compte le plus. Ici les affiches des
/// cartes suivantes sont téléchargées et décodées à l'avance, et la vue les
/// récupère de façon synchrone, sans une frame de placeholder.
final class PosterImageCache: @unchecked Sendable {
    static let shared = PosterImageCache()

    /// `NSCache` est thread-safe par contrat Apple — seul le suivi des
    /// téléchargements en cours a besoin d'une exclusion mutuelle, portée par
    /// un acteur plutôt qu'un `NSLock` : verrouiller à cheval sur un point de
    /// suspension `await` n'est pas permis en mode strict Swift 6.
    private let cache = NSCache<NSURL, UIImage>()
    private let inFlight = InFlightURLs()

    private init() {
        cache.countLimit = 120
    }

    /// Affiche déjà en cache, ou `nil`. Synchrone : c'est ce qui permet
    /// d'afficher la carte suivante sans transition.
    func cached(_ url: URL?) -> UIImage? {
        guard let url else { return nil }
        return cache.object(forKey: url as NSURL)
    }

    func image(for url: URL) async -> UIImage? {
        if let hit = cache.object(forKey: url as NSURL) { return hit }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = UIImage(data: data) else { return nil }
            cache.setObject(image, forKey: url as NSURL)
            return image
        } catch {
            return nil
        }
    }

    /// Précharge en tâche de fond, sans doublonner les téléchargements déjà en
    /// cours — le deck redemande les mêmes URLs à chaque swipe.
    func prefetch(_ urls: [URL?]) {
        for case let url? in urls {
            guard cache.object(forKey: url as NSURL) == nil else { continue }

            Task.detached(priority: .utility) { [weak self] in
                guard let self, await self.inFlight.begin(url) else { return }
                _ = await self.image(for: url)
                await self.inFlight.end(url)
            }
        }
    }
}

/// Suivi async-safe des URLs en cours de téléchargement.
private actor InFlightURLs {
    private var urls: Set<URL> = []

    func begin(_ url: URL) -> Bool {
        guard !urls.contains(url) else { return false }
        urls.insert(url)
        return true
    }

    func end(_ url: URL) {
        urls.remove(url)
    }
}

/// Affiche une image du `PosterImageCache`, en la prenant en cache dès l'init
/// pour éviter tout clignotement au changement de carte.
struct PosterImageView: View {
    private let url: URL?
    @State private var image: UIImage?

    init(url: URL?) {
        self.url = url
        _image = State(initialValue: PosterImageCache.shared.cached(url))
    }

    var body: some View {
        // `Color.clear` prend la taille proposée et la garde ; l'affiche remplit
        // par-dessus et le débord est rogné. Sans ce sas, `scaledToFill` fait
        // *grandir la vue* au-delà de ce qu'on lui propose : la pile qui la
        // contient se dimensionne sur l'image, le rognage arrive sur un cadre
        // déjà gonflé et ne retient rien. Une affiche portrait ne débordait que
        // de quelques points en hauteur, mais une couverture paysage traversait
        // l'écran par-dessus la mise en page.
        Color.clear
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    placeholder
                }
            }
            .clipped()
            .task(id: url) {
                guard image == nil, let url else { return }
                let loaded = await PosterImageCache.shared.image(for: url)
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.2)) { image = loaded }
            }
    }

    /// Le cadre vide, en attendant l'affiche. Un aplat de nuit et l'icône de la
    /// famille : `secondarySystemBackground` et `film` étaient deux des derniers
    /// emprunts au système dans une application par ailleurs entièrement
    /// dessinée — et sur une carte de « Découvrir », qui se lit en plein écran,
    /// le rectangle gris clair du système sautait aux yeux.
    private var placeholder: some View {
        ZStack {
            Rectangle().fill(Ink.ground)
            CinechillHallIconView(.salle)
                .frame(width: 30, height: 30)
                .foregroundStyle(Ink.ink3.opacity(0.7))
        }
    }
}
