import Foundation

struct KimiProvider: UsageProvider {
    let id = ProviderID.kimi

    private let databasePath: String
    private let deviceIDPath: String

    init(databasePath: String? = nil, deviceIDPath: String? = nil) {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.databasePath = databasePath ?? "\(home)/.gjc/agent/agent.db"
        self.deviceIDPath = deviceIDPath ?? "\(home)/.gjc/agent/kimi-device-id"
    }

    func fetch() async throws -> ProviderSnapshot {
        var credentials = try await Self.readCredentials(databasePath: databasePath)
        var didRefresh = false
        if credentials.needsRefresh(at: Date()) {
            credentials = try await Self.refreshCredentials(
                from: credentials,
                databasePath: databasePath,
                deviceID: deviceID
            )
            didRefresh = true
        }

        while true {
            guard let accessToken = credentials.accessToken else {
                throw Self.authenticationError
            }

            do {
                let data = try await Self.requestUsage(accessToken: accessToken, deviceID: deviceID)
                return try Self.parseUsage(data, fetchedAt: Date())
            } catch KimiRequestError.unauthorized {
                guard !didRefresh else { throw Self.authenticationError }
                credentials = try await Self.refreshCredentials(
                    from: credentials,
                    databasePath: databasePath,
                    deviceID: deviceID
                )
                didRefresh = true
            } catch KimiRequestError.failed {
                throw ProviderError.processFailed("Kimi usage request failed.")
            }
        }
    }

    static func parseUsage(_ data: Data, fetchedAt: Date) throws -> ProviderSnapshot {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.invalidResponse
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var windows: [QuotaWindow] = []

        if let limits = object["limits"] as? [[String: Any]] {
            for item in limits {
                guard
                    let detail = item["detail"] as? [String: Any],
                    let window = makeWindow(
                        from: detail,
                        durationMinutes: (item["window"] as? [String: Any]).flatMap(windowMinutes),
                        formatter: formatter
                    )
                else { continue }
                windows.append(window)
            }
        }

        if
            let usage = object["usage"] as? [String: Any],
            let weekly = makeWindow(from: usage, durationMinutes: 10_080, formatter: formatter)
        {
            windows.append(weekly)
        }

        guard !windows.isEmpty else { throw ProviderError.invalidResponse }
        return ProviderSnapshot(provider: .kimi, windows: windows, fetchedAt: fetchedAt)
    }

    private static func makeWindow(
        from detail: [String: Any],
        durationMinutes: Int?,
        formatter: ISO8601DateFormatter
    ) -> QuotaWindow? {
        guard let limit = number(detail["limit"]), limit > 0 else { return nil }

        let remainingPercent: Int
        if let remaining = number(detail["remaining"]) {
            remainingPercent = Int((remaining / limit * 100).rounded())
        } else if let used = number(detail["used"]) {
            remainingPercent = Int(((limit - used) / limit * 100).rounded())
        } else {
            return nil
        }

        let reset = (detail["resetTime"] as? String).flatMap(formatter.date(from:))
        return QuotaWindow(
            durationMinutes: durationMinutes,
            remainingPercent: max(0, min(100, remainingPercent)),
            resetsAt: reset
        )
    }

    private static func windowMinutes(from window: [String: Any]) -> Int? {
        guard let duration = number(window["duration"]) else { return nil }
        let unit = (window["timeUnit"] as? String ?? "").uppercased()
        let factor: Double
        if unit.contains("MINUTE") { factor = 1 }
        else if unit.contains("HOUR") { factor = 60 }
        else if unit.contains("DAY") { factor = 1_440 }
        else if unit.contains("SECOND") { factor = 1.0 / 60 }
        else { return nil }
        return max(1, Int((duration * factor).rounded()))
    }

    static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }

    private static func readCredentials(databasePath: String) async throws -> Credentials {
        let output = try await runProcess(
            executable: "/usr/bin/sqlite3",
            arguments: [
                "-readonly",
                databasePath,
                "SELECT data FROM auth_credentials WHERE provider = 'kimi-code' AND disabled_cause IS NULL ORDER BY id ASC LIMIT 1;",
            ],
            input: nil,
            failureMessage: "Could not read Kimi credentials."
        )

        guard
            let data = output.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw authenticationError }

        let accessToken = (object["access"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let refreshToken = (object["refresh"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let expiresAt = (object["expires"] as? NSNumber).map {
            Date(timeIntervalSince1970: $0.doubleValue / 1_000)
        }
        return Credentials(accessToken: accessToken, refreshToken: refreshToken, expiresAt: expiresAt)
    }

    private static func refreshCredentials(
        from credentials: Credentials,
        databasePath: String,
        deviceID: String?
    ) async throws -> Credentials {
        guard let refreshToken = credentials.refreshToken else { throw authenticationError }

        var config = """
        header = "Content-Type: application/x-www-form-urlencoded"
        header = "User-Agent: QuotaBar/0.1"
        header = "X-Msh-Platform: kimi_cli"
        data-urlencode = "grant_type=refresh_token"
        data-urlencode = "refresh_token=\(refreshToken)"
        data-urlencode = "client_id=17e5f671-d194-4dfb-9706-5516cb48c098"

        """
        if let deviceID { config += "header = \"X-Msh-Device-Id: \(deviceID)\"\n" }

        let output = try await runProcess(
            executable: "/usr/bin/curl",
            arguments: [
                "--silent", "--show-error", "--max-time", "10",
                "--config", "-",
                "https://auth.kimi.com/api/oauth/token",
            ],
            input: config,
            failureMessage: "Kimi token refresh failed."
        )

        guard
            let data = output.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let accessToken = object["access_token"] as? String, !accessToken.isEmpty
        else { throw authenticationError }

        let newRefresh = (object["refresh_token"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? refreshToken
        let expiresIn = (object["expires_in"] as? NSNumber)?.doubleValue ?? 3_600
        let expiresAt = Date().addingTimeInterval(expiresIn)
        let refreshed = Credentials(accessToken: accessToken, refreshToken: newRefresh, expiresAt: expiresAt)

        await writeBack(refreshed, databasePath: databasePath)
        return refreshed
    }

    // Persist rotated tokens so the CLI that owns the credential keeps working.
    private static func writeBack(_ credentials: Credentials, databasePath: String) async {
        guard let accessToken = credentials.accessToken else { return }
        let object: [String: Any] = [
            "access": accessToken,
            "refresh": credentials.refreshToken ?? "",
            "expires": Int((credentials.expiresAt ?? Date()).timeIntervalSince1970 * 1_000),
        ]
        guard
            let data = try? JSONSerialization.data(withJSONObject: object),
            var json = String(data: data, encoding: .utf8)
        else { return }
        json = json.replacingOccurrences(of: "'", with: "''")

        _ = try? await runProcess(
            executable: "/usr/bin/sqlite3",
            arguments: [
                databasePath,
                "UPDATE auth_credentials SET data = '\(json)' WHERE provider = 'kimi-code' AND disabled_cause IS NULL;",
            ],
            input: nil,
            failureMessage: "Kimi credential write-back failed."
        )
    }

    private static func requestUsage(accessToken: String, deviceID: String?) async throws -> Data {
        var config = """
        header = "Authorization: Bearer \(accessToken)"
        header = "User-Agent: QuotaBar/0.1"
        header = "X-Msh-Platform: kimi_cli"

        """
        if let deviceID { config += "header = \"X-Msh-Device-Id: \(deviceID)\"\n" }

        let output = try await runProcess(
            executable: "/usr/bin/curl",
            arguments: [
                "--silent", "--show-error", "--max-time", "10",
                "--write-out", "\n%{http_code}",
                "--config", "-",
                "https://api.kimi.com/coding/v1/usages",
            ],
            input: config,
            failureMessage: "Could not start the Kimi usage request."
        )

        guard let split = splitStatus(from: output) else { throw KimiRequestError.failed }
        switch split.status {
        case 200: return Data(split.body.utf8)
        case 401, 403: throw KimiRequestError.unauthorized
        default: throw KimiRequestError.failed
        }
    }

    private static func splitStatus(from output: String) -> (body: String, status: Int)? {
        guard let newline = output.lastIndex(of: "\n") else { return nil }
        let statusText = output[output.index(after: newline)...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard let status = Int(statusText) else { return nil }
        return (String(output[..<newline]), status)
    }

    private static func runProcess(
        executable: String,
        arguments: [String],
        input: String?,
        failureMessage: String
    ) async throws -> String {
        try await Task.detached {
            let process = Process()
            let inputPipe = Pipe()
            let outputPipe = Pipe()

            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardInput = inputPipe
            process.standardOutput = outputPipe
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
            } catch {
                throw ProviderError.processFailed(failureMessage)
            }

            if let input {
                try inputPipe.fileHandleForWriting.write(contentsOf: Data(input.utf8))
            }
            try inputPipe.fileHandleForWriting.close()

            let data = try outputPipe.fileHandleForReading.readToEnd() ?? Data()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw ProviderError.processFailed(failureMessage)
            }
            return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        }.value
    }

    private var deviceID: String? {
        guard
            let raw = try? String(contentsOfFile: deviceIDPath, encoding: .utf8)
        else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static var authenticationError: ProviderError {
        .processFailed("Sign in to Kimi Code first (gjc auth login kimi-code).")
    }

    private struct Credentials: Sendable {
        let accessToken: String?
        let refreshToken: String?
        let expiresAt: Date?

        func needsRefresh(at date: Date) -> Bool {
            guard accessToken != nil else { return true }
            return expiresAt.map { $0 <= date.addingTimeInterval(60) } ?? true
        }
    }

    private enum KimiRequestError: Error, Sendable {
        case unauthorized
        case failed
    }
}
