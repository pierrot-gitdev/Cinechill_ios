//
//  GalleryViewModel.swift
//  Cinechill_iOS
//

import Foundation
import SwiftUI

@Observable
@MainActor
final class GalleryViewModel {
    /// Hauteur d'affiche de la bande la plus fournie, et de la plus maigre.
    /// C'est cet écart qui fait que la mise en page *est* le graphique.
    private static let maxPosterHeight: CGFloat = 118
    private static let minPosterHeight: CGFloat = 54
    /// Adoucit la courbe : sans elle, une bande à deux films face à une bande
    /// à quarante deviendrait illisible.
    private static let volumeEasing: Double = 0.75
    /// Nombre de genres nommés dans la signature avant l'agrégat « autres ».
    private static let namedGenreCount = 5

    var axis: GalleryAxis = .era {
        didSet { rebuild() }
    }

    private(set) var bands: [GalleryBand] = []
    private(set) var signature = GallerySignature.empty

    private var entries: [GalleryEntry] = []
    private var genreNames: [Int: String] = [:]

    func update(entries: [GalleryEntry], genreNames: [Int: String]) {
        guard entries != self.entries || genreNames != self.genreNames else { return }
        self.entries = entries
        self.genreNames = genreNames
        rebuild()
    }

    /// La taille des affiches d'une bande, proportionnelle à son volume.
    func posterWidth(for band: GalleryBand) -> CGFloat {
        posterHeight(for: band) * 2 / 3
    }

    private func posterHeight(for band: GalleryBand) -> CGFloat {
        let maxCount = bands.map(\.count).max() ?? 0
        guard maxCount > 0 else { return Self.maxPosterHeight }
        let ratio = Double(band.count) / Double(maxCount)
        let eased = pow(ratio, Self.volumeEasing)
        return Self.minPosterHeight
            + (Self.maxPosterHeight - Self.minPosterHeight) * CGFloat(eased)
    }

    // MARK: - Construction

    private func rebuild() {
        bands = buildBands()
        signature = buildSignature()
    }

    private func buildBands() -> [GalleryBand] {
        guard !entries.isEmpty else { return [] }

        let raw: [GalleryBand]
        switch axis {
        case .era: raw = bandsByEra()
        case .genre: raw = bandsByGenre()
        case .added: raw = bandsByMonthAdded()
        case .rating: raw = bandsByRating()
        }

        // Seule la bande dominante est annotée — au-delà, l'annotation cesse
        // d'être une information pour devenir du bruit.
        guard let dominant = raw.max(by: { $0.count < $1.count }), raw.count > 1 else {
            return raw
        }
        return raw.map { band in
            guard band.id == dominant.id, let note = dominantNote else { return band }
            return GalleryBand(id: band.id, title: band.title, subtitle: note, entries: band.entries)
        }
    }

    private var dominantNote: String? {
        switch axis {
        case .era: String(localized: "votre décennie", bundle: .app)
        case .genre: String(localized: "votre terrain", bundle: .app)
        case .added: String(localized: "votre meilleur mois", bundle: .app)
        case .rating: nil
        }
    }

    private func bandsByEra() -> [GalleryBand] {
        var byDecade: [Int: [GalleryEntry]] = [:]
        var unknown: [GalleryEntry] = []

        for entry in entries {
            if let year = releaseYear(of: entry) {
                byDecade[year / 10 * 10, default: []].append(entry)
            } else {
                unknown.append(entry)
            }
        }

        var result: [GalleryBand] = []
        for decade in byDecade.keys.sorted(by: >) {
            let items: [GalleryEntry] = byDecade[decade] ?? []
            let sorted: [GalleryEntry] = items.sorted { lhs, rhs in
                let left: Int = releaseYear(of: lhs) ?? 0
                let right: Int = releaseYear(of: rhs) ?? 0
                return left > right
            }
            result.append(
                GalleryBand(id: "era-\(decade)", title: String(decade), subtitle: nil, entries: sorted)
            )
        }

        if !unknown.isEmpty {
            result.append(GalleryBand(id: "era-unknown", title: String(localized: "Sans date", bundle: .app), subtitle: nil, entries: unknown))
        }
        return result
    }

    private func bandsByGenre() -> [GalleryBand] {
        var byGenre: [Int: [GalleryEntry]] = [:]
        var unknown: [GalleryEntry] = []

        for entry in entries {
            if let genreID = primaryGenreID(of: entry) {
                byGenre[genreID, default: []].append(entry)
            } else {
                unknown.append(entry)
            }
        }

        var result: [GalleryBand] = []
        for (genreID, items) in byGenre {
            let title: String = genreNames[genreID] ?? String(localized: "Genre \(genreID)", bundle: .app)
            let sorted: [GalleryEntry] = items.sorted { $0.addedAt > $1.addedAt }
            result.append(
                GalleryBand(id: "genre-\(genreID)", title: title, subtitle: nil, entries: sorted)
            )
        }

        result.sort { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            return lhs.title < rhs.title
        }

        if !unknown.isEmpty {
            result.append(GalleryBand(id: "genre-none", title: String(localized: "Sans genre", bundle: .app), subtitle: nil, entries: unknown))
        }
        return result
    }

    private func bandsByMonthAdded() -> [GalleryBand] {
        let calendar = Calendar.current
        // Clé `année × 100 + mois` : un entier se trie et se compare bien plus
        // simplement qu'un `DateComponents`, et l'ordre reste chronologique.
        var byMonth: [Int: [GalleryEntry]] = [:]

        for entry in entries {
            let components = calendar.dateComponents([.year, .month], from: entry.addedAt)
            let year: Int = components.year ?? 0
            let month: Int = components.month ?? 0
            byMonth[year * 100 + month, default: []].append(entry)
        }

        var result: [GalleryBand] = []
        for key in byMonth.keys.sorted(by: >) {
            let items: [GalleryEntry] = byMonth[key] ?? []
            let sorted: [GalleryEntry] = items.sorted { $0.addedAt > $1.addedAt }
            result.append(
                GalleryBand(
                    id: "added-\(key)",
                    title: Self.monthTitle(year: key / 100, month: key % 100),
                    subtitle: nil,
                    entries: sorted
                )
            )
        }
        return result
    }

    private func bandsByRating() -> [GalleryBand] {
        let buckets: [(id: String, title: String, range: Range<Double>)] = [
            ("rating-9", String(localized: "9 et plus", bundle: .app), 9 ..< 11),
            ("rating-8", "8 – 9", 8 ..< 9),
            ("rating-7", "7 – 8", 7 ..< 8),
            ("rating-6", "6 – 7", 6 ..< 7),
            ("rating-0", String(localized: "Moins de 6", bundle: .app), 0 ..< 6),
        ]

        var result = buckets.compactMap { bucket -> GalleryBand? in
            let items = entries.filter { entry in
                guard let rating = entry.voteAverage else { return false }
                return bucket.range.contains(rating)
            }
            guard !items.isEmpty else { return nil }
            return GalleryBand(
                id: bucket.id,
                title: bucket.title,
                subtitle: nil,
                entries: items.sorted { ($0.voteAverage ?? 0) > ($1.voteAverage ?? 0) }
            )
        }

        let unrated = entries.filter { $0.voteAverage == nil }
        if !unrated.isEmpty {
            result.append(GalleryBand(id: "rating-none", title: String(localized: "Non noté", bundle: .app), subtitle: nil, entries: unrated))
        }
        return result
    }

    // MARK: - Signature

    private func buildSignature() -> GallerySignature {
        guard !entries.isEmpty else { return .empty }

        let calendar = Calendar.current
        let now = Date()
        let addedThisMonth = entries.filter {
            calendar.isDate($0.addedAt, equalTo: now, toGranularity: .month)
        }.count

        // Les parts sont calculées sur le genre principal, pas sur tous les
        // genres : c'est la seule façon d'obtenir une barre qui somme à 100 %.
        var counts: [Int: Int] = [:]
        for entry in entries {
            guard let genreID = primaryGenreID(of: entry) else { continue }
            counts[genreID, default: 0] += 1
        }

        let total = Double(counts.values.reduce(0, +))
        guard total > 0 else {
            return GallerySignature(total: entries.count, addedThisMonth: addedThisMonth, shares: [])
        }

        let ranked = counts.sorted { lhs, rhs in
            lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
        }

        var shares = ranked.prefix(Self.namedGenreCount).enumerated().map { index, pair in
            GenreShare(
                id: pair.key,
                name: genreNames[pair.key] ?? String(localized: "Genre \(pair.key)", bundle: .app),
                share: Double(pair.value) / total,
                colorIndex: index
            )
        }

        let remainder = ranked.dropFirst(Self.namedGenreCount).map(\.value).reduce(0, +)
        if remainder > 0 {
            shares.append(
                GenreShare(id: -1, name: String(localized: "Autres", bundle: .app), share: Double(remainder) / total, colorIndex: -1)
            )
        }

        return GallerySignature(
            total: entries.count,
            addedThisMonth: addedThisMonth,
            shares: shares
        )
    }

    // MARK: - Helpers

    private func releaseYear(of entry: GalleryEntry) -> Int? {
        guard let releaseDate = entry.releaseDate, releaseDate.count >= 4 else { return nil }
        return Int(releaseDate.prefix(4))
    }

    /// Un film compte pour un seul genre — celui que TMDB liste en premier.
    /// Le compter dans chacun de ses genres gonflerait les totaux et rendrait
    /// la barre de parts fausse.
    private func primaryGenreID(of entry: GalleryEntry) -> Int? {
        entry.genreIds.first { genreNames[$0] != nil } ?? entry.genreIds.first
    }

    private static func monthTitle(year: Int, month: Int) -> String {
        var components = DateComponents()
        components.year = year
        components.month = month
        guard let date = Calendar.current.date(from: components) else { return "—" }

        // Le nom du mois suit la langue de l'appareil : « Août 2026 » ici,
        // « August 2026 » ailleurs — ce qu'un `fr_FR` gravé ne sait pas faire.
        return date
            .formatted(.dateTime.month(.wide).year())
            .capitalized(with: Locale.current)
    }
}
