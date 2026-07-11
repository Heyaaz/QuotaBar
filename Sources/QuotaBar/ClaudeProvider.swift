import Foundation
import Security

struct ClaudeProvider: UsageProvider {
    let id = ProviderID.claude

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetch() async throws -> ProviderSnapshot {
        let token = try Self.readAccessToken()
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("QuotaBar/0.1", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ProviderError.invalidResponse }
        if http.statusCode == 401 { throw ProviderError.notAuthenticated }
        guard (200..<300).contains(http.statusCode) else {
            throw ProviderError.processFailed("Claude usage request failed (HTTP \(http.statusCode)).")
        }

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
}

