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
            let process = Process()
            let output = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/expect")
            process.arguments = ["-c", Self.expectScript]
            process.environment = Self.processEnvironment(executable: executable)
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
            } catch {
                throw ProviderError.processFailed("Could not start the Codex usage request.")
            }

            let data = try output.fileHandleForReading.readToEnd() ?? Data()
            process.waitUntilExit()
            guard process.terminationStatus == 0, !data.isEmpty else {
                throw ProviderError.processFailed("Codex usage request failed.")
            }
            return data
        }.value
    }

    static func processEnvironment(executable: String) -> [String: String] {
        let environment = ProcessInfo.processInfo.environment
        let executableDirectory = URL(fileURLWithPath: executable)
            .deletingLastPathComponent()
            .path
        let path = [
            executableDirectory,
            "/opt/homebrew/bin",
            "/usr/local/bin",
            environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin",
        ].joined(separator: ":")

        return environment.merging(
            ["QUOTABAR_CODEX_BIN": executable, "PATH": path],
            uniquingKeysWith: { _, new in new }
        )
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

    private static let expectScript = #"""
    log_user 0
    set timeout 15
    set codex $env(QUOTABAR_CODEX_BIN)
    spawn -noecho $codex app-server --stdio

    send -- {{"id":0,"method":"initialize","params":{"clientInfo":{"name":"quota_bar","title":"QuotaBar","version":"0.1.0"}}}}
    send -- "\n"
    expect -re {[^\r\n]*"id":0[^\r\n]*\r?\n}
    expect -re {[^\r\n]*"id":0[^\r\n]*\r?\n}

    send -- {{"method":"initialized"}}
    send -- "\n"
    expect -re {[^\r\n]*"method":"initialized"[^\r\n]*\r?\n}

    send -- {{"id":1,"method":"account/rateLimits/read"}}
    send -- "\n"
    expect -re {[^\r\n]*"id":1[^\r\n]*\r?\n}
    expect -re {([^\r\n]*"id":1[^\r\n]*)\r?\n} {
        puts $expect_out(1,string)
    }
    """#
}
