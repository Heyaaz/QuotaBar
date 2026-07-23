import Foundation
import Security

struct ClaudeProvider: UsageProvider {
    let id = ProviderID.claude

    func fetch() async throws -> ProviderSnapshot {
        var credentials = try Self.currentCredentials()
        var didRefresh = false

        if credentials.needsRefresh(at: Date()) {
            credentials = try await Self.refreshCredentials(from: credentials)
            Self.setCachedCredentials(credentials)
            didRefresh = true
        }

        while true {
            guard let accessToken = credentials.accessToken else {
                throw Self.authenticationError
            }

            do {
                let data = try await Self.requestUsage(accessToken: accessToken)
                return try Self.parseUsage(data, fetchedAt: Date())
            } catch ClaudeRequestError.unauthorized {
                guard !didRefresh else { throw Self.authenticationError }
                Self.setCachedCredentials(nil)
                credentials = try await Self.refreshCredentials(from: credentials)
                Self.setCachedCredentials(credentials)
                didRefresh = true
            } catch ClaudeRequestError.rateLimited {
                throw ProviderError.processFailed("Claude is rate limited. Try again shortly.")
            } catch ClaudeRequestError.failed {
                throw ProviderError.processFailed("Claude usage request failed.")
            }
        }
    }

    static func parseUsage(_ data: Data, fetchedAt: Date) throws -> ProviderSnapshot {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.invalidResponse
        }

        let definitions: [(key: String, minutes: Int)] = [
            ("five_hour", 300),
            ("seven_day", 10_080),
        ]
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let windows = definitions.compactMap { definition -> QuotaWindow? in
            guard
                let value = object[definition.key] as? [String: Any],
                let utilization = value["utilization"] as? Double
            else { return nil }

            let reset = (value["resets_at"] as? String).flatMap(formatter.date(from:))
            return QuotaWindow(
                durationMinutes: definition.minutes,
                remainingPercent: max(0, min(100, 100 - Int(utilization.rounded()))),
                resetsAt: reset
            )
        }

        guard !windows.isEmpty else { throw ProviderError.invalidResponse }
        return ProviderSnapshot(provider: .claude, windows: windows, fetchedAt: fetchedAt)
    }

    // In-memory credential cache. Avoids hitting the Keychain (and its
    // authorization prompt) on every 5-minute refresh while the access token
    // is still valid. The cache is invalidated on expiry or 401.
    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var cachedCredentialsValue: Credentials?

    private static func currentCredentials() throws -> Credentials {
        cacheLock.lock()
        let cached = cachedCredentialsValue
        cacheLock.unlock()

        if let cached {
            return cached
        }

        let fresh = try readCredentials()
        setCachedCredentials(fresh)
        return fresh
    }

    private static func setCachedCredentials(_ credentials: Credentials?) {
        cacheLock.lock()
        cachedCredentialsValue = credentials
        cacheLock.unlock()
    }

    private static func readCredentials() throws -> Credentials {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard
            status == errSecSuccess,
            let data = result as? Data,
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let oauth = root["claudeAiOauth"] as? [String: Any]
        else { throw authenticationError }

        let accessToken = (oauth["accessToken"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let refreshToken = (oauth["refreshToken"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let expiresAt = (oauth["expiresAt"] as? NSNumber).map {
            Date(timeIntervalSince1970: $0.doubleValue / 1_000)
        }
        return Credentials(accessToken: accessToken, refreshToken: refreshToken, expiresAt: expiresAt)
    }

    private static func refreshCredentials(from credentials: Credentials) async throws -> Credentials {
        guard credentials.refreshToken != nil else { throw authenticationError }
        guard let executable = findExecutable() else {
            throw ProviderError.executableNotFound("Claude CLI")
        }

        try await touchClaudeCLI(executable: executable)
        for _ in 0..<5 {
            if let updated = try? readCredentials(), !updated.needsRefresh(at: Date()) {
                return updated
            }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        throw authenticationError
    }

    private static func touchClaudeCLI(executable: String) async throws {
        try await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/expect")
            process.arguments = ["-c", expectScript]
            process.environment = processEnvironment(executable: executable)
            process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
            } catch {
                throw ProviderError.processFailed("Could not start Claude CLI.")
            }

            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw ProviderError.processFailed("Claude CLI could not refresh OAuth.")
            }
        }.value
    }

    private static func requestUsage(accessToken: String) async throws -> Data {
        try await Task.detached {
            let process = Process()
            let input = Pipe()
            let output = Pipe()

            process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
            process.arguments = [
                "--silent",
                "--show-error",
                "--fail-with-body",
                "--max-time", "10",
                "--config", "-",
                "https://api.anthropic.com/api/oauth/usage",
            ]
            process.standardInput = input
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
            } catch {
                throw ProviderError.processFailed("Could not start the Claude usage request.")
            }

            let escapedToken = accessToken
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            let config = """
            header = "Authorization: Bearer \(escapedToken)"
            header = "anthropic-beta: oauth-2025-04-20"
            header = "User-Agent: QuotaBar/0.1"

            """
            try input.fileHandleForWriting.write(contentsOf: Data(config.utf8))
            try input.fileHandleForWriting.close()

            let data = try output.fileHandleForReading.readToEnd() ?? Data()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw Self.requestError(from: data)
            }
            return data
        }.value
    }

    static func processEnvironment(
        executable: String,
        baseEnvironment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        let executableDirectory = URL(fileURLWithPath: executable)
            .deletingLastPathComponent()
            .path
        let path = [
            executableDirectory,
            "/opt/homebrew/bin",
            "/usr/local/bin",
            baseEnvironment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin",
        ].joined(separator: ":")
        var environment = baseEnvironment.merging(
            [
                "DISABLE_AUTOUPDATER": "1",
                "PATH": path,
                "QUOTABAR_CLAUDE_BIN": executable,
            ],
            uniquingKeysWith: { _, new in new }
        )
        for key in Array(environment.keys) where key == "CLAUDE_CODE_OAUTH_TOKEN" || key.hasPrefix("ANTHROPIC_") {
            environment.removeValue(forKey: key)
        }
        return environment
    }

    private static func findExecutable() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            ProcessInfo.processInfo.environment["CLAUDE_BIN"],
            ProcessInfo.processInfo.environment["CLAUDE_CLI_PATH"],
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "\(home)/.local/bin/claude",
            "\(home)/.claude/local/claude",
        ].compactMap { $0 }

        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static func requestError(from data: Data) -> ClaudeRequestError {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let error = root["error"] as? [String: Any],
            let type = error["type"] as? String
        else { return .failed }

        if type.contains("authentication") { return .unauthorized }
        if type.contains("rate_limit") { return .rateLimited }
        return .failed
    }

    private static var authenticationError: ProviderError {
        .processFailed("Run claude auth login.")
    }

    private struct Credentials: Sendable {
        let accessToken: String?
        let refreshToken: String?
        let expiresAt: Date?

        func needsRefresh(at date: Date) -> Bool {
            guard accessToken != nil else { return true }
            return expiresAt.map { $0 <= date.addingTimeInterval(60) } ?? false
        }
    }

    private enum ClaudeRequestError: Error, Sendable {
        case unauthorized
        case rateLimited
        case failed
    }

    private static let expectScript = #"""
    log_user 0
    set timeout 1
    set claude $env(QUOTABAR_CLAUDE_BIN)
    spawn -noecho $claude --allowed-tools ""

    set started [clock milliseconds]
    set deadline [expr {$started + 8000}]
    set sent 0
    set last_enter $started

    while {[clock milliseconds] < $deadline} {
        expect {
            -re {\033\[6n} { send -- "\033\[1;1R" }
            -re {Do you trust the files in this folder\?} { send -- "y\r" }
            -re {Quick safety check:} { send -- "\r" }
            -re {Yes, I trust this folder} { send -- "\r" }
            -re {Ready to code here\?} { send -- "\r" }
            -re {Press Enter to continue} { send -- "\r" }
            timeout {}
            eof { break }
        }

        set now [clock milliseconds]
        if {!$sent && $now - $started >= 2000} {
            send -- "/status\r"
            set sent 1
            set last_enter $now
        } elseif {$sent && $now - $last_enter >= 800} {
            send -- "\r"
            set last_enter $now
        }
    }

    catch {send -- "/exit\r"}
    after 200
    catch {close}
    catch {wait}
    """#
}
