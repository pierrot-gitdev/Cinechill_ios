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
        case .movie: "Films"
        case .tv: "Séries"
        }
    }

    var singularLabel: String {
        switch self {
        case .movie: "Film"
        case .tv: "Série"
        }
    }

    var apiPath: String { rawValue }
}
