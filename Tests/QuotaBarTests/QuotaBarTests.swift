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
func addsHomebrewToolsToCodexProcessPath() {
    let environment = CodexProvider.processEnvironment(executable: "/opt/homebrew/bin/codex")
    let path = environment["PATH"]?.split(separator: ":")

    #expect(environment["QUOTABAR_CODEX_BIN"] == "/opt/homebrew/bin/codex")
    #expect(path?.contains("/opt/homebrew/bin") == true)
    #expect(path?.contains("/usr/local/bin") == true)
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
func preparesCleanClaudeCLIEnvironment() {
    let environment = ClaudeProvider.processEnvironment(
        executable: "/opt/homebrew/bin/claude",
        baseEnvironment: [
            "ANTHROPIC_API_KEY": "secret",
            "CLAUDE_CODE_OAUTH_TOKEN": "stale",
            "PATH": "/usr/bin:/bin",
        ]
    )
    let path = environment["PATH"]?.split(separator: ":")

    #expect(environment["QUOTABAR_CLAUDE_BIN"] == "/opt/homebrew/bin/claude")
    #expect(environment["ANTHROPIC_API_KEY"] == nil)
    #expect(environment["CLAUDE_CODE_OAUTH_TOKEN"] == nil)
    #expect(path?.contains("/opt/homebrew/bin") == true)
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

@Test
func parsesKimiWindows() throws {
    let json = #"{"usage":{"limit":"100","used":"1","remaining":"99","resetTime":"2026-07-29T00:53:55.769566Z"},"limits":[{"window":{"duration":300,"timeUnit":"TIME_UNIT_MINUTE"},"detail":{"limit":"100","used":"7","remaining":"93","resetTime":"2026-07-22T05:53:55.769566Z"}}]}"#
    let snapshot = try KimiProvider.parseUsage(Data(json.utf8), fetchedAt: .distantPast)

    #expect(snapshot.provider == .kimi)
    #expect(snapshot.windows.map(\.shortLabel) == ["5h", "W"])
    #expect(snapshot.windows.map(\.remainingPercent) == [93, 99])
    #expect(snapshot.windows.allSatisfy { $0.resetsAt != nil })
}

@Test
func readsKimiUsageWhenLiveTestsAreEnabled() async throws {
    guard ProcessInfo.processInfo.environment["QUOTABAR_LIVE_TESTS"] == "1" else { return }

    let snapshot = try await KimiProvider().fetch()
    #expect(!snapshot.windows.isEmpty)
}

@Test @MainActor
func keepsSuccessfulProvidersWhenAnotherFails() async {
    let now = Date()
    let snapshot = ProviderSnapshot(
        provider: .claude,
        windows: [QuotaWindow(durationMinutes: 300, remainingPercent: 75, resetsAt: nil)],
        fetchedAt: now
    )
    let cache = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let store = UsageStore(
        providers: [
            StubProvider(id: .claude, result: .success(snapshot)),
            StubProvider(id: .codex, result: .failure(.notAuthenticated)),
        ],
        cacheURL: cache
    )

    await store.refresh()

    #expect(store.states[.claude]?.snapshot == snapshot)
    #expect(store.states[.codex]?.errorMessage != nil)
    #expect(store.states[.claude]?.errorMessage == nil)
}

@Test
func rejectsOldCachedUsageAndExpiredWindows() {
    let now = Date(timeIntervalSince1970: 10_000)
    let old = ProviderSnapshot(
        provider: .claude,
        windows: [QuotaWindow(durationMinutes: 300, remainingPercent: 96, resetsAt: nil)],
        fetchedAt: now.addingTimeInterval(-601)
    )
    let partlyExpired = ProviderSnapshot(
        provider: .claude,
        windows: [
            QuotaWindow(durationMinutes: 300, remainingPercent: 96, resetsAt: now),
            QuotaWindow(durationMinutes: 10_080, remainingPercent: 82, resetsAt: now.addingTimeInterval(60)),
        ],
        fetchedAt: now.addingTimeInterval(-60)
    )

    #expect(old.usableCache(at: now) == nil)
    #expect(partlyExpired.usableCache(at: now)?.windows.map(\.shortLabel) == ["W"])
}

private struct StubProvider: UsageProvider {
    let id: ProviderID
    let result: Result<ProviderSnapshot, ProviderError>

    func fetch() async throws -> ProviderSnapshot {
        try result.get()
    }
}

@Test
func formatsProviderNativeWindowLabels() {
    let windows = [
        QuotaWindow(durationMinutes: 300, remainingPercent: 1, resetsAt: nil),
        QuotaWindow(durationMinutes: 1_440, remainingPercent: 1, resetsAt: nil),
        QuotaWindow(durationMinutes: 10_080, remainingPercent: 1, resetsAt: nil),
    ]

    #expect(windows.map(\.shortLabel) == ["5h", "1d", "W"])
}

@Test
func omitsUnavailableCodexWindow() throws {
    let json = #"{"id":1,"result":{"rateLimits":{"primary":{"usedPercent":10,"windowDurationMins":300,"resetsAt":1000},"secondary":null}}}"#
    let snapshot = try CodexProvider.parseRateLimits(Data(json.utf8), fetchedAt: .distantPast)

    #expect(snapshot.windows.count == 1)
    #expect(snapshot.windows[0].remainingPercent == 90)
}

@Test @MainActor
func decodesCompactMenuBarLogos() {
    for provider in ProviderID.allCases {
        let image = ProviderIcons.image(for: provider)
        #expect(image.isTemplate)
        #expect(image.size.width == 13)
        #expect(image.size.height == 13)
    }
}

@Test
func alertsOnlyWhenQuotaCrossesAThreshold() {
    let previous = ProviderSnapshot(
        provider: .claude,
        windows: [
            QuotaWindow(durationMinutes: 300, remainingPercent: 21, resetsAt: nil),
            QuotaWindow(durationMinutes: 10_080, remainingPercent: 6, resetsAt: nil),
        ],
        fetchedAt: .distantPast
    )
    let current = ProviderSnapshot(
        provider: .claude,
        windows: [
            QuotaWindow(durationMinutes: 300, remainingPercent: 19, resetsAt: nil),
            QuotaWindow(durationMinutes: 10_080, remainingPercent: 4, resetsAt: nil),
        ],
        fetchedAt: .distantFuture
    )

    #expect(QuotaAlert.crossings(from: nil, to: current).isEmpty)
    #expect(QuotaAlert.crossings(from: previous, to: current).map(\.threshold) == [20, 5])
    #expect(QuotaAlert.crossings(from: current, to: current).isEmpty)

    let newPeriod = ProviderSnapshot(
        provider: .claude,
        windows: [
            QuotaWindow(durationMinutes: 300, remainingPercent: 4, resetsAt: .distantFuture),
        ],
        fetchedAt: .distantFuture
    )
    #expect(QuotaAlert.crossings(from: previous, to: newPeriod).isEmpty)
}

@Test @MainActor
func selectsTheLowestRemainingQuotaForCompactDisplay() {
    let states: [ProviderID: ProviderState] = [
        .claude: ProviderState(snapshot: ProviderSnapshot(
            provider: .claude,
            windows: [QuotaWindow(durationMinutes: 300, remainingPercent: 40, resetsAt: nil)],
            fetchedAt: .distantPast
        )),
        .codex: ProviderState(snapshot: ProviderSnapshot(
            provider: .codex,
            windows: [QuotaWindow(durationMinutes: 10_080, remainingPercent: 12, resetsAt: nil)],
            fetchedAt: .distantPast
        )),
    ]

    let lowest = StatusController.lowestQuota(in: states)
    #expect(lowest?.provider == .codex)
    #expect(lowest?.window.shortLabel == "W")
    #expect(lowest?.window.remainingPercent == 12)
}
