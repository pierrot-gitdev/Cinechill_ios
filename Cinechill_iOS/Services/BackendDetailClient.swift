import Foundation

enum BackendDetailClientError: LocalizedError {
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
            return "URL backend détail invalide."
        case .unsupportedMediaType:
            return "Le backend détail supporte uniquement les films."
        case .httpStatus(let code, let message):
            if let message, !message.isEmpty {
                return "Backend détail (HTTP \(code)) : \(message)"
            }
            return "Erreur backend détail (HTTP \(code))."
        case .decoding:
            return "Impossible de lire la réponse backend détail."
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

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw BackendDetailClientError.httpStatus(code: -1, message: nil)
        }
        guard (200 ... 299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8)
            throw BackendDetailClientError.httpStatus(code: http.statusCode, message: msg)
        }

        let decoder = JSONDecoder()
        guard let decoded = try? decoder.decode(TMDBDetailResponse.self, from: data) else {
            throw BackendDetailClientError.decoding
        }
        return decoded
    }
}

