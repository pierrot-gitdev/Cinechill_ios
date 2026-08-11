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
            return String(localized: "URL backend absente. Définis BACKEND_BASE_HOST dans Project.xcconfig.", bundle: .app)
        case .invalidURL:
            return String(localized: "URL backend invalide.", bundle: .app)
        case .unsupportedMediaType:
            return String(localized: "Le backend popular supporte uniquement les films.", bundle: .app)
        case .transport(let message):
            return String(localized: "Erreur réseau backend popular : \(message)", bundle: .app)
        case .httpStatus(let code, let message):
            if let message, !message.isEmpty {
                return String(localized: "Backend popular (HTTP \(code)) : \(message)", bundle: .app)
            }
            return String(localized: "Erreur backend popular (HTTP \(code)).", bundle: .app)
        case .decoding(let message):
            return String(localized: "Impossible de lire la réponse backend. \(message)", bundle: .app)
        }
    }
}

protocol HomeMetadataFetching: Sendable {
    func movieGenres() async throws -> [TMDBGenre]
    func movieProviders() async throws -> [TMDBWatchProvider]
}

struct BackendPopularClient: PopularPageFetching, HomeMetadataFetching, Sendable {
    private let cache: DiskCache

    // Le suffixe de version isole ce cache de celui d'avant le correctif du
    // filtre plateformes (location/achat exclus) : sans lui, les réponses déjà
    // sur disque continueraient de servir l'ancien résultat jusqu'à leur
    // expiration naturelle, jusqu'à 6 h après le déploiement du correctif.
    init(cache: DiskCache = DiskCache(name: "api_v2")) {
        self.cache = cache
    }

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
        // La langue voyage dans un en-tête, pas dans l'URL : sans elle dans
        // la clé, le cache resservirait les genres français à qui vient de
        // passer l'app en anglais.
        let key = "\(AppLanguage.current.tmdbTag)|\(url.absoluteString)"

        if let cached = await cache.read(for: key), !cached.isExpired,
           let decoded = try? JSONDecoder().decode(T.self, from: cached.data) {
            return decoded
        }

        do {
            let data = try await networkFetch(from: url)
            await cache.store(data, for: key)
            return try decode(T.self, from: data, url: url)
        } catch {
            if let stale = await cache.read(for: key),
               let decoded = try? JSONDecoder().decode(T.self, from: stale.data) {
                return decoded
            }
            throw error
        }
    }

    private func networkFetch(from url: URL) async throws -> Data {
        var request = await URLRequest(backend: url)
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
            if error is CancellationError { throw error }
            throw BackendPopularClientError.transport(message: error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw BackendPopularClientError.httpStatus(code: -1, message: nil)
        }
        guard (200...299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8)
            throw BackendPopularClientError.httpStatus(code: http.statusCode, message: msg)
        }
        return data
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data, url: URL) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            let body = String(data: data, encoding: .utf8) ?? "<body non lisible>"
            throw BackendPopularClientError.decoding(message: "URL: \(url.absoluteString) · Réponse: \(body)")
        }
    }
}
