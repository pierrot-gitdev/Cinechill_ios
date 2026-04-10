import Foundation

enum BackendPopularClientError: LocalizedError {
    case missingBaseURL
    case invalidURL
    case unsupportedMediaType
    case httpStatus(code: Int, message: String?)
    case decoding

    var errorDescription: String? {
        switch self {
        case .missingBaseURL:
            return "URL backend absente. Définissez BACKEND_BASE_URL dans Secrets.xcconfig."
        case .invalidURL:
            return "URL backend invalide."
        case .unsupportedMediaType:
            return "Le backend popular supporte uniquement les films."
        case .httpStatus(let code, let message):
            if let message, !message.isEmpty {
                return "Backend popular (HTTP \(code)) : \(message)"
            }
            return "Erreur backend popular (HTTP \(code))."
        case .decoding:
            return "Impossible de lire la réponse backend."
        }
    }
}

struct BackendPopularClient: PopularPageFetching, Sendable {
    func popularPage(mediaType: MediaType, page: Int) async throws -> TMDBPagedResults {
        guard mediaType == .movie else {
            throw BackendPopularClientError.unsupportedMediaType
        }
        guard BackendConfiguration.baseURL != nil else {
            throw BackendPopularClientError.missingBaseURL
        }
        guard let url = APIEndpoints.popularMovies(page: page) else {
            throw BackendPopularClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw BackendPopularClientError.httpStatus(code: -1, message: nil)
        }
        guard (200 ... 299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8)
            throw BackendPopularClientError.httpStatus(code: http.statusCode, message: msg)
        }

        let decoder = JSONDecoder()
        guard let decoded = try? decoder.decode(TMDBPagedResults.self, from: data) else {
            throw BackendPopularClientError.decoding
        }
        return decoded
    }
}

