import Foundation

enum BackendConfiguration {
    static var baseURL: URL? {
        #if DEBUG
        if let env = ProcessInfo.processInfo.environment["BACKEND_BASE_URL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !env.isEmpty
        {
            return URL(string: env)
        }
        #endif

        let raw =
            (Bundle.main.object(forInfoDictionaryKey: "BACKEND_BASE_URL") as? String)
            ?? ""
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "$(BACKEND_BASE_URL)" else { return nil }
        return URL(string: trimmed)
    }
}

