import Foundation

enum BackendDetailClientError: LocalizedError {
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
            return "URL backend détail invalide."
        case .unsupportedMediaType:
            return "Le backend détail supporte uniquement les films."
        case .transport(let message):
            return "Erreur réseau backend détail : \(message)"
        case .httpStatus(let code, let message):
            if let message, !message.isEmpty {
                return "Backend détail (HTTP \(code)) : \(message)"
            }
            return "Erreur backend détail (HTTP \(code))."
        case .decoding(let message):
            return "Impossible de lire la réponse backend détail. \(message)"
        }
    }
}

struct BackendDetailClient: Sendable {
    func itemDetails(id: Int, mediaType: MediaType) async throws -> TMDBDetailResponse {
        guard mediaType == .movie else {
            throw BackendDetailClientError.unsupportedMediaType
        }
        guard BackendConfiguration.baseURL != nil else {
            throw BackendDetailClientError.missingBaseURL
        }
        guard let url = APIEndpoints.movieDetails(id: id) else {
            throw BackendDetailClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw BackendDetailClientError.transport(message: error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw BackendDetailClientError.httpStatus(code: -1, message: nil)
        }
        guard (200 ... 299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8)
            throw BackendDetailClientError.httpStatus(code: http.statusCode, message: msg)
        }

        let decoder = JSONDecoder()
        do {
            return try decoder.decode(TMDBDetailResponse.self, from: data)
        } catch {
            let body = String(data: data, encoding: .utf8) ?? "<body non lisible>"
            throw BackendDetailClientError.decoding(message: "URL: \(url.absoluteString) · Réponse: \(body)")
        }
    }
}

