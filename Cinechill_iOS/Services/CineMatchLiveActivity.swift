//
//  CineMatchLiveActivity.swift
//  Cinechill_iOS
//

import ActivityKit
import Foundation
import UIKit

/// Démarre et retire l'activité en direct « en cours » d'un film lancé depuis
/// CinéMatch. Le dessin vit dans l'extension `CinechillWidgets`.
///
/// L'app ne reçoit aucun signal quand le film se termine : rien ne tourne en
/// arrière-plan pendant qu'on regarde Netflix. L'activité porte donc une date
/// de péremption, la durée du film plus une marge ; passé cette date elle cesse
/// d'affirmer « en cours », et l'app la retire au prochain retour au premier
/// plan. Au pire, iOS la retire de lui-même après huit heures.
enum CineMatchLiveActivity {
    /// La marge laissée après la durée annoncée : une pause, un générique
    /// regardé jusqu'au bout. Au-delà, « en cours » deviendrait une supposition.
    private static let margin: TimeInterval = 20 * 60

    /// Quand la durée est inconnue, on tient la durée d'un film moyen.
    private static let fallbackMinutes = 120

    /// Côté réduit de l'affiche déposée pour l'extension, en pixels : 60 pt de
    /// large sur l'écran verrouillé, à l'échelle 3. Une activité dont les
    /// images dépassent sa taille d'affichage peut ne jamais apparaître.
    private nonisolated static let posterPixelWidth: CGFloat = 180

    /// À appeler **avant** d'ouvrir la plateforme : iOS refuse de démarrer une
    /// activité depuis une app qui n'est plus au premier plan.
    static func start(film: CineMatchFilm, details: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        // Un seul film en cours à la fois : relancer en remplace un autre.
        let previous = Activity<CineMatchActivityAttributes>.activities
        Task {
            for activity in previous {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }

        let attributes = CineMatchActivityAttributes(
            tmdbID: film.id,
            title: film.item.title,
            details: details,
            playingLabel: String(localized: "En cours", bundle: .app),
            staleLabel: String(localized: "Ce soir", bundle: .app)
        )
        let minutes = film.runtimeMinutes.flatMap { $0 > 0 ? $0 : nil } ?? fallbackMinutes
        let staleDate = Date().addingTimeInterval(TimeInterval(minutes * 60) + margin)

        let activity: Activity<CineMatchActivityAttributes>
        do {
            activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: .init(posterFileName: nil), staleDate: staleDate),
                pushType: nil
            )
        } catch {
            return
        }

        guard let posterURL = film.item.posterURL else { return }
        // L'app part en arrière-plan dès que la plateforme s'ouvre ; ce délai
        // de grâce laisse à l'affiche le temps d'arriver.
        let grace = UIApplication.shared.beginBackgroundTask()
        Task {
            if let name = await storePoster(from: posterURL, tmdbID: film.id) {
                await activity.update(ActivityContent(
                    state: .init(posterFileName: name),
                    staleDate: staleDate
                ))
            }
            UIApplication.shared.endBackgroundTask(grace)
        }
    }

    /// Retire les activités périmées et les affiches qu'elles laissent. Appelé
    /// à chaque retour au premier plan : c'est le seul moment où l'app reprend
    /// la main après le film.
    static func endFinished() {
        let now = Date()
        let activities = Activity<CineMatchActivityAttributes>.activities
        let finished = activities.filter { ($0.content.staleDate ?? .distantFuture) <= now }
        let kept = Set(activities
            .filter { ($0.content.staleDate ?? .distantFuture) > now }
            .compactMap(\.content.state.posterFileName))

        Task {
            for activity in finished {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            await removePosters(keeping: kept)
        }
    }

    // MARK: - L'affiche

    /// Réduit l'affiche et la dépose dans le conteneur partagé. Elle est
    /// presque toujours déjà en cache : la carte du film vient d'être affichée.
    @concurrent
    private nonisolated static func storePoster(from url: URL, tmdbID: Int) async -> String? {
        guard let image = await PosterImageCache.shared.image(for: url),
              image.size.width > 0,
              let directory = CineMatchActivityStore.directory else { return nil }

        let width = posterPixelWidth
        let size = CGSize(width: width, height: (width * image.size.height / image.size.width).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let reduced = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let data = reduced.jpegData(compressionQuality: 0.8) else { return nil }

        let name = "poster-\(tmdbID).jpg"
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: directory.appendingPathComponent(name), options: .atomic)
            return name
        } catch {
            return nil
        }
    }

    @concurrent
    private nonisolated static func removePosters(keeping kept: Set<String>) async {
        guard let directory = CineMatchActivityStore.directory,
              let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path)
        else { return }
        for name in names where !kept.contains(name) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }
}
