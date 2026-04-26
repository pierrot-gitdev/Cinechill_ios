import CryptoKit
import Foundation

actor DiskCache {
    private let directory: URL
    private let defaultTTL: TimeInterval

    init(name: String, defaultTTL: TimeInterval = 6 * 3600) {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent("cinechill_\(name)", isDirectory: true)
        self.defaultTTL = defaultTTL
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func read(for key: String) -> (data: Data, isExpired: Bool)? {
        let (dataURL, metaURL) = urls(for: key)
        guard
            let raw = try? Data(contentsOf: dataURL),
            let metaRaw = try? Data(contentsOf: metaURL),
            let meta = try? JSONDecoder().decode(Meta.self, from: metaRaw)
        else { return nil }
        return (raw, meta.expiresAt < Date())
    }

    func store(_ data: Data, for key: String, ttl: TimeInterval? = nil) {
        let (dataURL, metaURL) = urls(for: key)
        let meta = Meta(expiresAt: Date().addingTimeInterval(ttl ?? defaultTTL))
        try? data.write(to: dataURL, options: .atomic)
        try? JSONEncoder().encode(meta).write(to: metaURL, options: .atomic)
    }

    private func urls(for key: String) -> (data: URL, meta: URL) {
        let hash = SHA256.hash(data: Data(key.utf8))
            .map { String(format: "%02x", $0) }.joined()
        return (
            directory.appendingPathComponent(hash),
            directory.appendingPathComponent(hash + ".meta")
        )
    }

    private struct Meta: Codable {
        let expiresAt: Date
    }
}
