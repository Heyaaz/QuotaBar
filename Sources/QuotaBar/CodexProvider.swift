import Foundation

struct CodexProvider: UsageProvider {
    let id = ProviderID.codex

    private let executable: String?

    init(executable: String? = nil) {
        self.executable = executable
    }

    func fetch() async throws -> ProviderSnapshot {
        let path = executable ?? Self.findExecutable()
        guard let path else { throw ProviderError.executableNotFound("Codex CLI") }

        let response = try await Self.readRateLimits(executable: path)
        return try Self.parseRateLimits(response, fetchedAt: Date())
    }

    static func parseRateLimits(_ data: Data, fetchedAt: Date) throws -> ProviderSnapshot {
        guard
            let message = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            message["error"] == nil,
            let result = message["result"] as? [String: Any]
        else { throw ProviderError.invalidResponse }

        let snapshot: [String: Any]?
        if
            let buckets = result["rateLimitsByLimitId"] as? [String: Any],
            let codex = buckets["codex"] as? [String: Any]
        {
            snapshot = codex
        } else {
            snapshot = result["rateLimits"] as? [String: Any]
        }

        guard let snapshot else { throw ProviderError.invalidResponse }

        let windows = ["primary", "secondary"].compactMap { key -> QuotaWindow? in
            guard
                let window = snapshot[key] as? [String: Any],
                let used = window["usedPercent"] as? Int
            else { return nil }

            let duration = window["windowDurationMins"] as? Int
            let reset = (window["resetsAt"] as? TimeInterval).map(Date.init(timeIntervalSince1970:))
            return QuotaWindow(
                durationMinutes: duration,
                remainingPercent: max(0, min(100, 100 - used)),
                resetsAt: reset
            )
        }

        guard !windows.isEmpty else { throw ProviderError.invalidResponse }
        return ProviderSnapshot(provider: .codex, windows: windows, fetchedAt: fetchedAt)
    }

    private static func readRateLimits(executable: String) async throws -> Data {
        try await Task.detached {
            let client = try JSONLineProcess(executable: executable, arguments: ["app-server", "--stdio"])
            defer { client.close() }

            let initialize: [String: Any] = [
                "id": 0,
                "method": "initialize",
                "params": [
                    "clientInfo": [
                        "name": "quota_bar",
                        "title": "QuotaBar",
                        "version": "0.1.0",
                    ],
                ],
            ]
            try client.send(initialize)
            _ = try client.read(id: 0)
            try client.send(["method": "initialized"])
            try client.send(["id": 1, "method": "account/rateLimits/read"])
            return try client.read(id: 1)
        }.value
    }

    private static func findExecutable() -> String? {
        let candidates = [
            ProcessInfo.processInfo.environment["CODEX_BIN"],
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "/Applications/ChatGPT.app/Contents/Resources/codex",
        ].compactMap { $0 }

        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
