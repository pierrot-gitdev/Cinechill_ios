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

    /// Les opus d'une saga, pour la feuille qui propose d'ajouter les autres.
    static func collection(id: Int) -> URL? {
        guard let baseURL = BackendConfiguration.baseURL else { return nil }
        return buildURL(baseURL: baseURL, functionName: "getcollection", queryItems: [
            URLQueryItem(name: "id", value: String(id)),
        ])
    }

    // MARK: - Les séries

    static func tvDetails(id: Int) -> URL? {
        guard let baseURL = BackendConfiguration.baseURL else { return nil }
        return buildURL(baseURL: baseURL, functionName: "gettvdetails", queryItems: [
            URLQueryItem(name: "id", value: String(id)),
        ])
    }

    static func tvSeason(id: Int, season: Int) -> URL? {
        guard let baseURL = BackendConfiguration.baseURL else { return nil }
        return buildURL(baseURL: baseURL, functionName: "gettvseason", queryItems: [
            URLQueryItem(name: "id", value: String(id)),
            URLQueryItem(name: "season", value: String(season)),
        ])
    }

    static func enrichSeasons() -> URL? {
        guard let baseURL = BackendConfiguration.baseURL else { return nil }
        return buildURL(baseURL: baseURL, functionName: "enrichseasons", queryItems: [])
    }

    static func setNextEpisode() -> URL? {
        guard let baseURL = BackendConfiguration.baseURL else { return nil }
        return buildURL(baseURL: baseURL, functionName: "setnextepisode", queryItems: [])
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

    static func setGalleryLove() -> URL? {
        guard let baseURL = BackendConfiguration.baseURL else { return nil }
        return buildURL(baseURL: baseURL, functionName: "setgallerylove", queryItems: [])
    }

    static func enrichCandidates() -> URL? {
        guard let baseURL = BackendConfiguration.baseURL else { return nil }
        return buildURL(baseURL: baseURL, functionName: "enrichcandidates", queryItems: [])
    }

    /// L'état des Portes.
    static func doors() -> URL? {
        guard let baseURL = BackendConfiguration.baseURL else { return nil }
        return buildURL(baseURL: baseURL, functionName: "getdoors", queryItems: [])
    }

    static func sessionOutcome() -> URL? {
        guard let baseURL = BackendConfiguration.baseURL else { return nil }
        return buildURL(baseURL: baseURL, functionName: "recordsessionoutcome", queryItems: [])
    }

    // MARK: - CinéMatch v2

    static func cineMatchStarters() -> URL? {
        guard let baseURL = BackendConfiguration.baseURL else { return nil }
        return buildURL(baseURL: baseURL, functionName: "getcinematchstarters", queryItems: [])
    }

    static func cineMatchPicks() -> URL? {
        guard let baseURL = BackendConfiguration.baseURL else { return nil }
        return buildURL(baseURL: baseURL, functionName: "getcinematchpicks", queryItems: [])
    }

    static func cineMatchDaily() -> URL? {
        guard let baseURL = BackendConfiguration.baseURL else { return nil }
        return buildURL(baseURL: baseURL, functionName: "getcinematchdaily", queryItems: [])
    }

    static func cineMatchExposure() -> URL? {
        guard let baseURL = BackendConfiguration.baseURL else { return nil }
        return buildURL(baseURL: baseURL, functionName: "recordcinematchexposure", queryItems: [])
    }

    static func swipeFeed() -> URL? {
        guard let baseURL = BackendConfiguration.baseURL else { return nil }
        return buildURL(baseURL: baseURL, functionName: "getswipefeed", queryItems: [])
    }

    static func recordSwipes() -> URL? {
        guard let baseURL = BackendConfiguration.baseURL else { return nil }
        return buildURL(baseURL: baseURL, functionName: "recordswipes", queryItems: [])
    }

    static func probeGrid() -> URL? {
        guard let baseURL = BackendConfiguration.baseURL else { return nil }
        return buildURL(baseURL: baseURL, functionName: "getprobegrid", queryItems: [])
    }

    static func deckSheet() -> URL? {
        guard let baseURL = BackendConfiguration.baseURL else { return nil }
        return buildURL(baseURL: baseURL, functionName: "getdecksheet", queryItems: [])
    }

    static func homeRows() -> URL? {
        guard let baseURL = BackendConfiguration.baseURL else { return nil }
        return buildURL(baseURL: baseURL, functionName: "gethomerows", queryItems: [])
    }

    static func evaluateBadges() -> URL? {
        guard let baseURL = BackendConfiguration.baseURL else { return nil }
        return buildURL(baseURL: baseURL, functionName: "evaluatebadges", queryItems: [])
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

    /// Le nom public, écrit par le serveur avec ses préfixes de recherche :
    /// le client n'a pas le droit d'écrire ces derniers, sans quoi n'importe
    /// qui pourrait apparaître dans la recherche du nom d'un autre.
    static func setPublicName() -> URL? {
        guard let baseURL = BackendConfiguration.baseURL else { return nil }
        return buildURL(baseURL: baseURL, functionName: "setpublicname", queryItems: [])
    }

    static func followSuggestions() -> URL? {
        guard let baseURL = BackendConfiguration.baseURL else { return nil }
        return buildURL(baseURL: baseURL, functionName: "getfollowsuggestions", queryItems: [])
    }

    static func dismissFollowSuggestion() -> URL? {
        guard let baseURL = BackendConfiguration.baseURL else { return nil }
        return buildURL(baseURL: baseURL, functionName: "dismissfollowsuggestion", queryItems: [])
    }

    // MARK: - Blocage et signalement

    static func blockUser() -> URL? {
        guard let baseURL = BackendConfiguration.baseURL else { return nil }
        return buildURL(baseURL: baseURL, functionName: "blockuser", queryItems: [])
    }

    static func unblockUser() -> URL? {
        guard let baseURL = BackendConfiguration.baseURL else { return nil }
        return buildURL(baseURL: baseURL, functionName: "unblockuser", queryItems: [])
    }

    static func blockedUsers() -> URL? {
        guard let baseURL = BackendConfiguration.baseURL else { return nil }
        return buildURL(baseURL: baseURL, functionName: "getblockedusers", queryItems: [])
    }

    static func reportUser() -> URL? {
        guard let baseURL = BackendConfiguration.baseURL else { return nil }
        return buildURL(baseURL: baseURL, functionName: "reportuser", queryItems: [])
    }

    // MARK: - La recherche

    static func searchTitles() -> URL? {
        guard let baseURL = BackendConfiguration.baseURL else { return nil }
        return buildURL(baseURL: baseURL, functionName: "searchtitles", queryItems: [])
    }

    // MARK: - Les notifications

    /// Rattache le jeton FCM de l'appareil au compte, avec la langue de l'app
    /// et le fuseau : le serveur rédige et date chaque notification avec.
    static func registerDevice() -> URL? {
        guard let baseURL = BackendConfiguration.baseURL else { return nil }
        return buildURL(baseURL: baseURL, functionName: "registerdevice", queryItems: [])
    }

    /// Détache le jeton. Appelé à la déconnexion, avec le compte qui s'en va.
    static func unregisterDevice() -> URL? {
        guard let baseURL = BackendConfiguration.baseURL else { return nil }
        return buildURL(baseURL: baseURL, functionName: "unregisterdevice", queryItems: [])
    }

    /// La réponse à « Tu as regardé ce film hier ? ».
    static func setFilmVerdict() -> URL? {
        guard let baseURL = BackendConfiguration.baseURL else { return nil }
        return buildURL(baseURL: baseURL, functionName: "setfilmverdict", queryItems: [])
    }

    static func axisQuestion() -> URL? {
        guard let baseURL = BackendConfiguration.baseURL else { return nil }
        return buildURL(baseURL: baseURL, functionName: "getaxisquestion", queryItems: [])
    }

    static func axisAnswer() -> URL? {
        guard let baseURL = BackendConfiguration.baseURL else { return nil }
        return buildURL(baseURL: baseURL, functionName: "recordaxisanswer", queryItems: [])
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

