import Foundation

nonisolated struct StreamingPlatform: Identifiable, Hashable {
    let id: String
    let providerID: Int
    let name: String
    let logoPath: String?

    var shortLabel: String {
        String(name.prefix(2)).uppercased()
    }

    var logoURL: URL? {
        guard let logoPath, !logoPath.isEmpty else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w92\(logoPath)")
    }
}

nonisolated extension StreamingPlatform {
    private struct CurationRule {
        let displayName: String
        let aliases: [String]
    }

    private static let curationRules: [CurationRule] = [
        CurationRule(displayName: "Netflix", aliases: ["netflix"]),
        CurationRule(displayName: "Prime Video", aliases: ["primevideo", "amazonprimevideo"]),
        CurationRule(displayName: "Disney +", aliases: ["disneyplus", "disney+"]),
        CurationRule(displayName: "Pathé Home", aliases: ["pathehome", "pathéhome"]),
        CurationRule(displayName: "Canal +", aliases: ["canal+", "canalplus"]),
        CurationRule(displayName: "Apple TV", aliases: ["appletv", "appletvplus"]),
        CurationRule(displayName: "HBO Max", aliases: ["hbomax", "max"]),
        CurationRule(displayName: "Paramount +", aliases: ["paramount+", "paramountplus"]),
        CurationRule(displayName: "Arte", aliases: ["arte"]),
        CurationRule(displayName: "TF1", aliases: ["tf1plus"]),
        CurationRule(displayName: "Molotov TV", aliases: ["molotovtv", "molotov"])
    ]

    /// Réduit la liste brute des providers TMDB à la sélection de plateformes affichée dans l'app.
    static func curated(from providers: [TMDBWatchProvider]) -> [StreamingPlatform] {
        let normalizedProviders = providers.map { ($0, normalize($0.providerName)) }

        var curated: [StreamingPlatform] = []
        for rule in curationRules {
            let ruleAliases = Set(rule.aliases.map(normalize))
            if let matched = normalizedProviders.first(where: { ruleAliases.contains($0.1) })?.0 {
                curated.append(
                    StreamingPlatform(
                        id: String(matched.providerID),
                        providerID: matched.providerID,
                        name: rule.displayName,
                        logoPath: matched.logoPath
                    )
                )
            }
        }
        return curated
    }

    private static func normalize(_ raw: String) -> String {
        raw
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "[^a-z0-9+]", with: "", options: .regularExpression)
    }
}

