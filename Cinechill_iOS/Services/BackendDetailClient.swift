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
            return String(localized: "URL backend absente. Définissez BACKEND_BASE_HOST dans Project.xcconfig.", bundle: .app)
        case .invalidURL:
            return String(localized: "URL backend détail invalide.", bundle: .app)
        case .unsupportedMediaType:
            return String(localized: "Le backend détail supporte uniquement les films.", bundle: .app)
        case .transport(let message):
            return String(localized: "Erreur réseau backend détail : \(message)", bundle: .app)
        case .httpStatus(let code, let message):
            if let message, !message.isEmpty {
                return String(localized: "Backend détail (HTTP \(code)) : \(message)", bundle: .app)
            }
            return String(localized: "Erreur backend détail (HTTP \(code)).", bundle: .app)
        case .decoding(let message):
            return String(localized: "Impossible de lire la réponse backend détail. \(message)", bundle: .app)
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

        var request = URLRequest(backend: url)
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

