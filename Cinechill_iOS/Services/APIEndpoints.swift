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

    static func candidatePool() -> URL? {
        guard let baseURL = BackendConfiguration.baseURL else { return nil }
        return buildURL(baseURL: baseURL, functionName: "getcandidatepool", queryItems: [])
    }

    static func enrichCandidates() -> URL? {
        guard let baseURL = BackendConfiguration.baseURL else { return nil }
        return buildURL(baseURL: baseURL, functionName: "enrichcandidates", queryItems: [])
    }

    static func finalizeRecommendations() -> URL? {
        guard let baseURL = BackendConfiguration.baseURL else { return nil }
        return buildURL(baseURL: baseURL, functionName: "finalizerecommendations", queryItems: [])
    }

    static func swipeFeed() -> URL? {
        guard let baseURL = BackendConfiguration.baseURL else { return nil }
        return buildURL(baseURL: baseURL, functionName: "getswipefeed", queryItems: [])
    }

    static func recordSwipes() -> URL? {
        guard let baseURL = BackendConfiguration.baseURL else { return nil }
        return buildURL(baseURL: baseURL, functionName: "recordswipes", queryItems: [])
    }

    static func homeRows() -> URL? {
        guard let baseURL = BackendConfiguration.baseURL else { return nil }
        return buildURL(baseURL: baseURL, functionName: "gethomerows", queryItems: [])
    }

    static func evaluateBadges() -> URL? {
        guard let baseURL = BackendConfiguration.baseURL else { return nil }
        return buildURL(baseURL: baseURL, functionName: "evaluatebadges", queryItems: [])
    }

    static func resetSwipeSkips() -> URL? {
        guard let baseURL = BackendConfiguration.baseURL else { return nil }
        return buildURL(baseURL: baseURL, functionName: "resetswipeskips", queryItems: [])
    }

    static func deleteAccount() -> URL? {
        guard let baseURL = BackendConfiguration.baseURL else { return nil }
        return buildURL(baseURL: baseURL, functionName: "deleteaccount", queryItems: [])
    }

    // MARK: - Le Hall

    static func claimHandle() -> URL? {
        guard let baseURL = BackendConfiguration.baseURL else { return nil }
        return buildURL(baseURL: baseURL, functionName: "claimhandle", queryItems: [])
    }

    /// Contrôle de disponibilité, sans réservation — appelé pendant la saisie,
    /// avant que le compte n'existe et donc avant qu'un jeton Firebase ne
    /// soit disponible. `claimHandle` reste seule à trancher pour de bon.
    static func handleAvailable(handle: String) -> URL? {
        guard let baseURL = BackendConfiguration.baseURL else { return nil }
        return buildURL(baseURL: baseURL, functionName: "handleavailable", queryItems: [
            URLQueryItem(name: "handle", value: handle),
        ])
    }

    static func followUser() -> URL? {
        guard let baseURL = BackendConfiguration.baseURL else { return nil }
        return buildURL(baseURL: baseURL, functionName: "followuser", queryItems: [])
    }

    static func unfollowUser() -> URL? {
        guard let baseURL = BackendConfiguration.baseURL else { return nil }
        return buildURL(baseURL: baseURL, functionName: "unfollowuser", queryItems: [])
    }

    static func sendSuggestion() -> URL? {
        guard let baseURL = BackendConfiguration.baseURL else { return nil }
        return buildURL(baseURL: baseURL, functionName: "sendsuggestion", queryItems: [])
    }

    static func respondToSuggestion() -> URL? {
        guard let baseURL = BackendConfiguration.baseURL else { return nil }
        return buildURL(baseURL: baseURL, functionName: "respondtosuggestion", queryItems: [])
    }

    static func suggestionTargets() -> URL? {
        guard let baseURL = BackendConfiguration.baseURL else { return nil }
        return buildURL(baseURL: baseURL, functionName: "getsuggestiontargets", queryItems: [])
    }

    static func publicProfile() -> URL? {
        guard let baseURL = BackendConfiguration.baseURL else { return nil }
        return buildURL(baseURL: baseURL, functionName: "getpublicprofile", queryItems: [])
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

