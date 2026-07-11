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

@Test
func parsesClaudeWindows() throws {
    let json = #"{"five_hour":{"utilization":3.0,"resets_at":"2026-07-11T19:40:00.296175+00:00"},"seven_day":{"utilization":18.0,"resets_at":"2026-07-17T13:00:00.296197+00:00"}}"#
    let snapshot = try ClaudeProvider.parseUsage(Data(json.utf8), fetchedAt: .distantPast)

    #expect(snapshot.provider == .claude)
    #expect(snapshot.windows.map(\.shortLabel) == ["5h", "W"])
    #expect(snapshot.windows.map(\.remainingPercent) == [97, 82])
    #expect(snapshot.windows.allSatisfy { $0.resetsAt != nil })
}

@Test
func readsClaudeUsageWhenLiveTestsAreEnabled() async throws {
    guard ProcessInfo.processInfo.environment["QUOTABAR_LIVE_TESTS"] == "1" else { return }

    let snapshot = try await ClaudeProvider().fetch()
    #expect(!snapshot.windows.isEmpty)
}

@Test
func parsesGrokWeeklyWindow() throws {
    let json = #"{"jsonrpc":"2.0","id":2,"result":{"config":{"creditUsagePercent":21.5,"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","end":"2026-07-18T14:35:45.502164+00:00"}}}}"#
    let snapshot = try GrokProvider.parseBilling(Data(json.utf8), fetchedAt: .distantPast)

    #expect(snapshot.provider == .grok)
    #expect(snapshot.windows.map(\.shortLabel) == ["W"])
    #expect(snapshot.windows.map(\.remainingPercent) == [78])
    #expect(snapshot.windows[0].resetsAt != nil)
}

@Test
func readsGrokUsageWhenLiveTestsAreEnabled() async throws {
    guard ProcessInfo.processInfo.environment["QUOTABAR_LIVE_TESTS"] == "1" else { return }

    let snapshot = try await GrokProvider().fetch()
    #expect(snapshot.windows.count == 1)
}
