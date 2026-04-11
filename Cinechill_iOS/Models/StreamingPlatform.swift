import Foundation

struct StreamingPlatform: Identifiable, Hashable {
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

