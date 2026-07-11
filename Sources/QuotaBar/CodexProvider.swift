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
            let input = Pipe()
            let output = Pipe()
            let error = Pipe()

            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = ["app-server", "--stdio"]
            process.standardInput = input
            process.standardOutput = output
            process.standardError = error

            do {
                try process.run()
            } catch {
                throw ProviderError.processFailed(error.localizedDescription)
            }

            let timeout = DispatchWorkItem {
                if process.isRunning { process.terminate() }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 10, execute: timeout)

            defer {
                timeout.cancel()
                try? input.fileHandleForWriting.close()
                if process.isRunning { process.terminate() }
            }

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
            try writeJSON(initialize, to: input.fileHandleForWriting)

            var reader = JSONLineReader(handle: output.fileHandleForReading)
            guard try reader.readMessage(id: 0) != nil else { throw ProviderError.timedOut }

            try writeJSON(["method": "initialized"], to: input.fileHandleForWriting)
            try writeJSON(["id": 1, "method": "account/rateLimits/read"], to: input.fileHandleForWriting)

            guard let response = try reader.readMessage(id: 1) else { throw ProviderError.timedOut }
            return response
        }.value
    }

    private static func writeJSON(_ object: [String: Any], to handle: FileHandle) throws {
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)
        try handle.write(contentsOf: data)
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

private struct JSONLineReader {
    let handle: FileHandle
    var buffer = Data()

    mutating func readMessage(id: Int) throws -> Data? {
        while true {
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer[..<newline]
                buffer.removeSubrange(...newline)
                guard
                    let object = try JSONSerialization.jsonObject(with: line) as? [String: Any],
                    object["id"] as? Int == id
                else { continue }
                return Data(line)
            }

            let chunk = handle.availableData
            if chunk.isEmpty { return nil }
            buffer.append(chunk)
        }
    }
}

