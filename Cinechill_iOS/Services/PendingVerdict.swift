//
//  PendingVerdict.swift
//  Cinechill_iOS
//

import Foundation

/// L'avis du lendemain, demandé dans l'app (lot 1, 16 novembre 2026).
///
/// La notification de 19 h ne touchait que ceux qui l'avaient autorisée, et
/// ne partait pas pour une série. Ici, le film ou la série lancé depuis
/// CinéMatch est gardé sur l'appareil ; à la première ouverture de l'app à
/// partir du lendemain 5 h, on demande comment c'était, une seule fois. Une
/// réponse donnée entre-temps (par la notification, par la fiche) l'efface.
///
/// Rien de personnel ne sort de l'appareil : seuls l'identifiant, le titre et
/// l'affiche du film sont gardés, le temps d'une question.
nonisolated enum PendingVerdict {
    private static let key = "cinematch.pendingVerdict"
    /// Au-delà, la soirée est trop loin pour qu'on s'en souvienne.
    private static let maxAge: TimeInterval = 3 * 24 * 3600

    private struct Stored: Codable {
        let tmdbId: Int
        let mediaType: String
        let title: String
        let posterPath: String?
        let releaseDate: String?
        let launchedAt: Date
    }

    /// Un film ou une série vient d'être lancé depuis CinéMatch. Le dernier
    /// lancé remplace le précédent : on ne demande qu'un avis à la fois.
    static func save(_ item: MediaItem, at date: Date = .now) {
        let stored = Stored(
            tmdbId: item.tmdbId,
            mediaType: item.mediaType.rawValue,
            title: item.title,
            posterPath: item.posterPath,
            releaseDate: item.releaseDate,
            launchedAt: date
        )
        guard let data = try? JSONEncoder().encode(stored) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    /// L'avis a été donné ailleurs : on ne le redemande pas.
    static func clear(tmdbID: Int) {
        guard let stored = load(), stored.tmdbId == tmdbID else { return }
        UserDefaults.standard.removeObject(forKey: key)
    }

    /// Le titre dont l'avis est dû, retiré de la file : il ne sera demandé
    /// qu'une fois, même si la question est fermée sans réponse. `nil` avant
    /// le lendemain 5 h, ou trop longtemps après.
    static func takeDue(now: Date = .now, calendar: Calendar = .current) -> MediaItem? {
        guard let stored = load() else { return nil }
        let age = now.timeIntervalSince(stored.launchedAt)
        if age > maxAge || age < 0 {
            UserDefaults.standard.removeObject(forKey: key)
            return nil
        }
        // Le lendemain du lancement, 5 h : une séance tard le soir appartient
        // encore à la veille, comme pour la notification.
        let launchDay = calendar.startOfDay(for: stored.launchedAt.addingTimeInterval(-5 * 3600))
        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: launchDay),
              let due = calendar.date(byAdding: .hour, value: 5, to: nextDay),
              now >= due,
              let mediaType = MediaType(rawValue: stored.mediaType)
        else { return nil }
        UserDefaults.standard.removeObject(forKey: key)
        return MediaItem(
            tmdbId: stored.tmdbId,
            mediaType: mediaType,
            title: stored.title,
            posterPath: stored.posterPath,
            overview: nil,
            voteAverage: nil,
            voteCount: nil,
            genreIds: [],
            releaseDate: stored.releaseDate
        )
    }

    private static func load() -> Stored? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Stored.self, from: data)
    }
}
