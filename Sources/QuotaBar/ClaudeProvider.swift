import Foundation
import Security

struct ClaudeProvider: UsageProvider {
    let id = ProviderID.claude

    func fetch() async throws -> ProviderSnapshot {
        let token = try Self.readAccessToken()
        let data = try await Self.requestUsage(accessToken: token)
        return try Self.parseUsage(data, fetchedAt: Date())
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

    private static func readAccessToken() throws -> String {
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
            let oauth = root["claudeAiOauth"] as? [String: Any],
            let token = oauth["accessToken"] as? String,
            !token.isEmpty
        else { throw ProviderError.notAuthenticated }

        return token
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
                throw ProviderError.processFailed("Claude usage request failed.")
            }
            return data
        }.value
    }
}
