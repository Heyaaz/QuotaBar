import Foundation
import Testing
@testable import QuotaBar

@Test
func parsesCodexWindows() throws {
    let json = #"{"id":1,"result":{"rateLimits":{"primary":{"usedPercent":25,"windowDurationMins":300,"resetsAt":1000},"secondary":{"usedPercent":60,"windowDurationMins":10080,"resetsAt":2000}}}}"#
    let snapshot = try CodexProvider.parseRateLimits(Data(json.utf8), fetchedAt: .distantPast)

    #expect(snapshot.provider == .codex)
    #expect(snapshot.windows.map(\.shortLabel) == ["5h", "W"])
    #expect(snapshot.windows.map(\.remainingPercent) == [75, 40])
}

@Test
func readsCodexRateLimitsWhenLiveTestsAreEnabled() async throws {
    guard ProcessInfo.processInfo.environment["QUOTABAR_LIVE_TESTS"] == "1" else { return }

    let snapshot = try await CodexProvider().fetch()
    #expect(!snapshot.windows.isEmpty)
}
