import Foundation

enum BackendPopularClientError: LocalizedError {
    case missingBaseURL
    case invalidURL
    case unsupportedMediaType
    case transport(message: String)
    case httpStatus(code: Int, message: String?)
    case decoding(message: String)

    var errorDescription: String? {
        switch self {
        case .missingBaseURL:
            return "URL backend absente. Définissez BACKEND_BASE_HOST dans Project.xcconfig."
        case .invalidURL:
            return "URL backend invalide."
        case .unsupportedMediaType:
            return "Le backend popular supporte uniquement les films."
        case .transport(let message):
            return "Erreur réseau backend popular : \(message)"
        case .httpStatus(let code, let message):
            if let message, !message.isEmpty {
                return "Backend popular (HTTP \(code)) : \(message)"
            }
            return "Erreur backend popular (HTTP \(code))."
        case .decoding(let message):
            return "Impossible de lire la réponse backend. \(message)"
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

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw BackendPopularClientError.transport(message: error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw BackendPopularClientError.httpStatus(code: -1, message: nil)
        }
        guard (200 ... 299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8)
            throw BackendPopularClientError.httpStatus(code: http.statusCode, message: msg)
        }

        let decoder = JSONDecoder()
        do {
            return try decoder.decode(TMDBPagedResults.self, from: data)
        } catch {
            let body = String(data: data, encoding: .utf8) ?? "<body non lisible>"
            throw BackendPopularClientError.decoding(message: "URL: \(url.absoluteString) · Réponse: \(body)")
        }
    }
}

