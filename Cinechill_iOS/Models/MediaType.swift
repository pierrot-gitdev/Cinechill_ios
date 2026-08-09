//
//  MediaType.swift
//  Cinechill_iOS
//

import Foundation

enum MediaType: String, Codable, CaseIterable, Identifiable {
    case movie
    case tv

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .movie: String(localized: "Films", bundle: .app)
        case .tv: String(localized: "Séries", bundle: .app)
        }
    }

    var singularLabel: String {
        switch self {
        case .movie: String(localized: "Film", bundle: .app)
        case .tv: String(localized: "Série", bundle: .app)
        }
    }

    var apiPath: String { rawValue }
}
