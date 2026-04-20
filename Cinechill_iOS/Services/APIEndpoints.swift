import Foundation

enum APIEndpoints {
    static func popularMovies(page: Int, genreID: Int? = nil, providerIDs: [Int] = []) -> URL? {
        guard let baseURL = BackendConfiguration.baseURL else { return nil }
        var items: [URLQueryItem] = [
            URLQueryItem(name: "page", value: String(page)),
        ]
        if let genreID {
            items.append(URLQueryItem(name: "genreId", value: String(genreID)))
        }
        if !providerIDs.isEmpty {
            items.append(URLQueryItem(name: "providerIds", value: providerIDs.map(String.init).joined(separator: ",")))
            items.append(URLQueryItem(name: "watchRegion", value: "FR"))
        }
        return buildURL(baseURL: baseURL, functionName: "getpopularmovies", queryItems: items)
    }

    static func movieDetails(id: Int) -> URL? {
        guard let baseURL = BackendConfiguration.baseURL else { return nil }
        return buildURL(baseURL: baseURL, functionName: "getmoviedetails", queryItems: [
            URLQueryItem(name: "id", value: String(id)),
        ])
    }

    static func movieGenres() -> URL? {
        guard let baseURL = BackendConfiguration.baseURL else { return nil }
        return buildURL(baseURL: baseURL, functionName: "getmoviegenres", queryItems: [])
    }

    static func movieProviders() -> URL? {
        guard let baseURL = BackendConfiguration.baseURL else { return nil }
        return buildURL(baseURL: baseURL, functionName: "getmovieproviders", queryItems: [
            URLQueryItem(name: "watchRegion", value: "FR"),
        ])
    }

    static func setMediaStatus() -> URL? {
        guard let baseURL = BackendConfiguration.baseURL else { return nil }
        return buildURL(baseURL: baseURL, functionName: "setmediastatus", queryItems: [])
    }

    private static func buildURL(baseURL: URL, functionName: String, queryItems: [URLQueryItem]) -> URL? {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }

        if let host = components.host, let dashIndex = host.firstIndex(of: "-") {
            let suffix = host[dashIndex...]
            components.host = functionName + suffix
        }

        components.path = "/"
        components.queryItems = queryItems
        return components.url
    }
}

