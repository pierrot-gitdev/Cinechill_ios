//
//  TMDBConfiguration.swift
//  Cinechill_iOS
//
//  1) Secrets.xcconfig à la racine (à côté de Project.xcconfig) : TMDB_API_KEY = …
//  2) Build Settings de la cible → TMDB_API_KEY (User-Defined)
//  3) Debug : schéma Run → environnement TMDB_API_KEY
//

import Foundation

enum TMDBConfiguration {
    static var apiKey: String {
        #if DEBUG
        if let env = ProcessInfo.processInfo.environment["TMDB_API_KEY"],
           !env.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return env.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        #endif

        let raw =
            (Bundle.main.object(forInfoDictionaryKey: "TMDB_API_KEY") as? String)
            ?? (Bundle.main.infoDictionary?["TMDB_API_KEY"] as? String)
            ?? ""
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed == "$(TMDB_API_KEY)" {
            return ""
        }

        if trimmed.hasPrefix("\""), trimmed.hasSuffix("\""), trimmed.count >= 2 {
            return String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }

    static var client: TMDBClient {
        TMDBClient(apiKey: apiKey)
    }
}
