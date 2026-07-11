import Foundation

struct GrokProvider: UsageProvider {
    let id = ProviderID.grok

    private let executable: String?

    init(executable: String? = nil) {
        self.executable = executable
    }

    func fetch() async throws -> ProviderSnapshot {
        let path = executable ?? Self.findExecutable()
        guard let path else { throw ProviderError.executableNotFound("Grok Build") }

        let response = try await Self.readBilling(executable: path)
        return try Self.parseBilling(response, fetchedAt: Date())
    }

    static func parseBilling(_ data: Data, fetchedAt: Date) throws -> ProviderSnapshot {
        guard
            let message = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            message["error"] == nil,
            let result = message["result"] as? [String: Any],
            let config = result["config"] as? [String: Any]
        else { throw ProviderError.invalidResponse }

        let currentPeriod = config["currentPeriod"] as? [String: Any]
        let rawUsed = Self.number(config["creditUsagePercent"])
            ?? Self.number(currentPeriod?["usagePercent"])
            ?? Self.number(currentPeriod?["usedPercent"])
            ?? 0
        let resetText = currentPeriod?["end"] as? String ?? config["billingPeriodEnd"] as? String
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let reset = resetText.flatMap(formatter.date(from:))

        let window = QuotaWindow(
            durationMinutes: 10_080,
            remainingPercent: max(0, min(100, 100 - Int(rawUsed.rounded()))),
            resetsAt: reset
        )
        return ProviderSnapshot(provider: .grok, windows: [window], fetchedAt: fetchedAt)
    }

    private static func readBilling(executable: String) async throws -> Data {
        try await Task.detached {
            let client = try JSONLineProcess(
                executable: executable,
                arguments: ["--no-subagents", "--no-auto-update", "agent", "stdio"],
                timeoutSeconds: 20
            )
            defer { client.close() }

            try client.send([
                "jsonrpc": "2.0",
                "id": 0,
                "method": "initialize",
                "params": [
                    "protocolVersion": 1,
                    "clientCapabilities": [
                        "fs": ["readTextFile": false, "writeTextFile": false],
                        "terminal": false,
                    ],
                ],
            ])
            do {
                _ = try client.read(id: 0)
            } catch {
                throw ProviderError.processFailed("Grok initialize failed: \(error.localizedDescription)")
            }

            try client.send([
                "jsonrpc": "2.0",
                "id": 1,
                "method": "authenticate",
                "params": [
                    "methodId": "cached_token",
                    "_meta": ["headless": true],
                ],
            ])
            let auth: Data
            do {
                auth = try client.read(id: 1)
            } catch {
                throw ProviderError.processFailed("Grok authentication failed: \(error.localizedDescription)")
            }
            if Self.hasError(auth) { throw ProviderError.notAuthenticated }

            try client.send([
                "jsonrpc": "2.0",
                "id": 2,
                "method": "_x.ai/billing",
                "params": [:],
            ])
            do {
                return try client.read(id: 2)
            } catch {
                throw ProviderError.processFailed("Grok usage request failed: \(error.localizedDescription)")
            }
        }.value
    }

    private static func hasError(_ data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return true
        }
        return object["error"] != nil
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        return nil
    }

    private static func findExecutable() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            ProcessInfo.processInfo.environment["GROK_BIN"],
            "\(home)/.grok/bin/grok",
            "\(home)/.local/bin/grok",
            "/opt/homebrew/bin/grok",
            "/usr/local/bin/grok",
        ].compactMap { $0 }

        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
