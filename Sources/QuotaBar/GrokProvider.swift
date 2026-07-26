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
            let process = Process()
            let output = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/expect")
            process.arguments = ["-c", Self.expectScript]
            process.environment = ProcessInfo.processInfo.environment.merging(
                ["QUOTABAR_GROK_BIN": executable],
                uniquingKeysWith: { _, new in new }
            )
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
            } catch {
                throw ProviderError.processFailed("Could not start the Grok usage request.")
            }

            let data = try output.fileHandleForReading.readToEnd() ?? Data()
            process.waitUntilExit()
            guard process.terminationStatus == 0, !data.isEmpty else {
                throw ProviderError.processFailed("Grok usage request failed.")
            }
            return data
        }.value
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

    private static let expectScript = #"""
    log_user 0
    set timeout 20
    set grok $env(QUOTABAR_GROK_BIN)
    spawn -noecho $grok --no-subagents --no-auto-update agent stdio

    send -- {{"jsonrpc":"2.0","id":0,"method":"initialize","params":{"protocolVersion":1,"clientCapabilities":{"fs":{"readTextFile":false,"writeTextFile":false},"terminal":false}}}}
    send -- "\n"
    expect -re {[^\r\n]*"id":0,"(?:result|error)"[^\r\n]*\r?\n}

    send -- {{"jsonrpc":"2.0","id":1,"method":"authenticate","params":{"methodId":"cached_token","_meta":{"headless":true}}}}
    send -- "\n"
    expect -re {[^\r\n]*"id":1,"(?:result|error)"[^\r\n]*\r?\n}

    send -- {{"jsonrpc":"2.0","id":2,"method":"_x.ai/billing","params":{}}}
    send -- "\n"
    expect -re {([^\r\n]*"id":2,"(?:result|error)"[^\r\n]*)\r?\n} {
        puts $expect_out(1,string)
    }
    """#
}
