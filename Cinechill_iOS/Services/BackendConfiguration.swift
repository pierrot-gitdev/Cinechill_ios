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

        let hostRaw = (Bundle.main.object(forInfoDictionaryKey: "BACKEND_BASE_HOST") as? String) ?? ""
        let host = hostRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !host.isEmpty, host != "$(BACKEND_BASE_HOST)" {
            return URL(string: "https://\(host)")
        }

        // Legacy support if BACKEND_BASE_URL exists in user config.
        let urlRaw = (Bundle.main.object(forInfoDictionaryKey: "BACKEND_BASE_URL") as? String) ?? ""
        let urlTrimmed = urlRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !urlTrimmed.isEmpty, urlTrimmed != "$(BACKEND_BASE_URL)" else { return nil }

        let normalized: String
        if urlTrimmed.hasPrefix("\""), urlTrimmed.hasSuffix("\""), urlTrimmed.count >= 2 {
            normalized = String(urlTrimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            normalized = urlTrimmed
        }
        return URL(string: normalized)
    }
}

