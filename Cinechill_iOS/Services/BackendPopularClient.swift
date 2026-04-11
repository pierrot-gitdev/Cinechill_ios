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

protocol HomeMetadataFetching: Sendable {
    func movieGenres() async throws -> [TMDBGenre]
    func movieProviders() async throws -> [TMDBWatchProvider]
}

struct BackendPopularClient: PopularPageFetching, HomeMetadataFetching, Sendable {
    func popularPage(
        mediaType: MediaType,
        page: Int,
        genreID: Int?,
        providerIDs: [Int]
    ) async throws -> TMDBPagedResults {
        guard mediaType == .movie else {
            throw BackendPopularClientError.unsupportedMediaType
        }
        guard BackendConfiguration.baseURL != nil else {
            throw BackendPopularClientError.missingBaseURL
        }
        guard let url = APIEndpoints.popularMovies(page: page, genreID: genreID, providerIDs: providerIDs) else {
            throw BackendPopularClientError.invalidURL
        }
        return try await fetch(TMDBPagedResults.self, from: url)
    }

    func movieGenres() async throws -> [TMDBGenre] {
        guard let url = APIEndpoints.movieGenres() else {
            throw BackendPopularClientError.invalidURL
        }
        let response = try await fetch(TMDBGenresResponse.self, from: url)
        return response.genres.sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
    }

    func movieProviders() async throws -> [TMDBWatchProvider] {
        guard let url = APIEndpoints.movieProviders() else {
            throw BackendPopularClientError.invalidURL
        }
        let response = try await fetch(TMDBWatchProvidersResponse.self, from: url)
        return response.results.sorted { lhs, rhs in
            let leftPriority = lhs.displayPriority ?? Int.max
            let rightPriority = rhs.displayPriority ?? Int.max
            if leftPriority != rightPriority {
                return leftPriority < rightPriority
            }
            return lhs.providerName.localizedCaseInsensitiveCompare(rhs.providerName) == .orderedAscending
        }
    }

    private func fetch<T: Decodable>(_ type: T.Type, from url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            if let urlError = error as? URLError, urlError.code == .cancelled {
                throw CancellationError()
            }
            if error is CancellationError {
                throw error
            }
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
            return try decoder.decode(T.self, from: data)
        } catch {
            let body = String(data: data, encoding: .utf8) ?? "<body non lisible>"
            throw BackendPopularClientError.decoding(message: "URL: \(url.absoluteString) · Réponse: \(body)")
        }
    }
}

