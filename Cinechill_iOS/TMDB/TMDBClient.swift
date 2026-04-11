//
//  TMDBClient.swift
//  Cinechill_iOS
//

import Foundation

enum TMDBClientError: LocalizedError {
    case missingAPIKey
    case invalidURL
    case httpStatus(code: Int, message: String?)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return """
            Clé TMDB absente dans l’app. Ouvrez Secrets.xcconfig (racine du projet, à côté de Project.xcconfig), définissez TMDB_API_KEY = votre_cle (sans guillemets), puis Clean Build Folder et rebuild. En Debug vous pouvez aussi passer TMDB_API_KEY dans le schéma Run → Environment Variables.
            """
        case .invalidURL:
            return "URL TMDB invalide."
        case .httpStatus(let code, let message):
            if let message, !message.isEmpty {
                return "TMDB (HTTP \(code)) : \(message)"
            }
            return "Erreur réseau TMDB (HTTP \(code))."
        case .decoding:
            return "Impossible de lire la réponse TMDB."
        }
    }
}

private struct TMDBErrorJSON: Decodable {
    let statusCode: Int?
    let statusMessage: String?

    enum CodingKeys: String, CodingKey {
        case statusCode = "status_code"
        case statusMessage = "status_message"
    }
}

struct TMDBClient: Sendable {
    private static let baseURL = "https://api.themoviedb.org/3"

    let apiKey: String
    let language: String
    let region: String

    init(
        apiKey: String,
        language: String = "fr-FR",
        region: String = "FR"
    ) {
        self.apiKey = apiKey
        self.language = language
        self.region = region
    }

    /// TMDB : `region` est supporté pour `/movie/popular`, pas pour `/tv/popular` (paramètre ignoré ou source d’erreurs selon les versions).
    func popularPage(mediaType: MediaType, page: Int) async throws -> TMDBPagedResults {
        var components = URLComponents(string: "\(Self.baseURL)/\(mediaType.apiPath)/popular")!
        var items: [URLQueryItem] = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "language", value: language),
            URLQueryItem(name: "page", value: String(page)),
        ]
        if mediaType == .movie {
            items.append(URLQueryItem(name: "region", value: region))
        }
        components.queryItems = items
        guard let url = components.url else { throw TMDBClientError.invalidURL }
        return try await fetch(url)
    }

    func itemDetails(id: Int, mediaType: MediaType) async throws -> TMDBDetailResponse {
        var components = URLComponents(string: "\(Self.baseURL)/\(mediaType.apiPath)/\(id)")!
        components.queryItems = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "language", value: language),
            URLQueryItem(name: "append_to_response", value: "credits,videos,images"),
        ]
        guard let url = components.url else { throw TMDBClientError.invalidURL }
        return try await fetch(url)
    }

    private func fetch<T: Decodable>(_ url: URL) async throws -> T {
        if apiKey.isEmpty { throw TMDBClientError.missingAPIKey }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TMDBClientError.httpStatus(code: -1, message: nil)
        }
        guard (200 ... 299).contains(http.statusCode) else {
            let msg = Self.parseTMDBErrorMessage(from: data)
            throw TMDBClientError.httpStatus(code: http.statusCode, message: msg)
        }

        do {
            let decoder = JSONDecoder()
            return try decoder.decode(T.self, from: data)
        } catch {
            throw TMDBClientError.decoding(error)
        }
    }

    private static func parseTMDBErrorMessage(from data: Data) -> String? {
        guard !data.isEmpty,
              let parsed = try? JSONDecoder().decode(TMDBErrorJSON.self, from: data),
              let text = parsed.statusMessage,
              !text.isEmpty
        else { return nil }
        return text
    }
}

