import Foundation

/// Reads per-account quota from a local codex-lb instance
/// (https://github.com/Soju06/codex-lb). Each routed account becomes one
/// window, labeled with the account's short name, so the pool shows up as
/// one row per account instead of a single aggregate number.
struct CodexLBProvider {

    private let baseURL: URL

    init(baseURL: URL? = nil) {
        self.baseURL = baseURL ?? Self.defaultBaseURL
    }

    /// Override with `CODEXBAR_ENDPOINT`, e.g. `CODEXBAR_ENDPOINT=http://127.0.0.1:9000`.
    static var defaultBaseURL: URL {
        let raw = ProcessInfo.processInfo.environment["CODEXBAR_ENDPOINT"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let raw, !raw.isEmpty, let url = URL(string: raw) { return url }
        return URL(string: "http://127.0.0.1:2455")!
    }

    func fetch() async throws -> ProviderSnapshot {
        var request = URLRequest(url: baseURL.appending(path: "api/accounts"))
        request.timeoutInterval = 10

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ProviderError.processFailed(
                "codex-lb is not reachable at \(baseURL.absoluteString). Start it or set CODEXBAR_ENDPOINT."
            )
        }

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ProviderError.processFailed("codex-lb returned an error.")
        }

        return try Self.parseAccounts(data, fetchedAt: Date())
    }

    static func parseAccounts(_ data: Data, fetchedAt: Date) throws -> ProviderSnapshot {
        let response: AccountsResponse
        do {
            response = try JSONDecoder().decode(AccountsResponse.self, from: data)
        } catch {
            throw ProviderError.invalidResponse
        }

        let windows = response.accounts.compactMap { account -> QuotaWindow? in
            guard account.isActive else { return nil }
            guard let percent = account.usage?.secondaryRemainingPercent
                ?? account.usage?.primaryRemainingPercent
            else { return nil }

            return QuotaWindow(
                durationMinutes: account.windowMinutesSecondary,
                remainingPercent: Self.clampedPercent(percent),
                resetsAt: account.resetAtSecondary.flatMap(Self.parseISO8601),
                label: account.shortName
            )
        }

        guard !windows.isEmpty else { throw ProviderError.invalidResponse }
        return ProviderSnapshot(provider: .codex, windows: windows, fetchedAt: fetchedAt)
    }

    private static func clampedPercent(_ value: Double) -> Int {
        Int(max(0, min(100, value.rounded())))
    }

    private static func parseISO8601(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }
}

/// Response of `GET /api/accounts` on a local codex-lb instance.
private struct AccountsResponse: Decodable, Sendable {
    let accounts: [CodexLBAccount]
}

private struct CodexLBAccount: Decodable, Sendable {
    let accountId: String
    let email: String?
    let alias: String?
    let displayName: String?
    let status: String?
    let usage: CodexLBUsage?
    let resetAtSecondary: String?
    let windowMinutesSecondary: Int?

    var isActive: Bool { (status ?? "").lowercased() == "active" }

    /// Alias, display name, or account id — short enough to fit the menu bar.
    /// Email-like values (codex-lb often reports the email as display name)
    /// collapse to their local part.
    var shortName: String {
        var name = alias ?? displayName ?? email ?? accountId
        if let at = name.firstIndex(of: "@"), !name[..<at].isEmpty {
            name = String(name[..<at])
        }
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.count <= 14 ? name : String(name.prefix(13)) + "…"
    }
}

private struct CodexLBUsage: Decodable, Sendable {
    let primaryRemainingPercent: Double?
    let secondaryRemainingPercent: Double?
}
