import Foundation

enum APIEndpoints {
    static func popularMovies(page: Int) -> URL? {
        guard let baseURL = BackendConfiguration.baseURL else { return nil }
        return buildURL(baseURL: baseURL, functionName: "getpopularmovies", queryItems: [
            URLQueryItem(name: "page", value: String(page)),
        ])
    }

    static func movieDetails(id: Int) -> URL? {
        guard let baseURL = BackendConfiguration.baseURL else { return nil }
        return buildURL(baseURL: baseURL, functionName: "getmoviedetails", queryItems: [
            URLQueryItem(name: "id", value: String(id)),
        ])
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

