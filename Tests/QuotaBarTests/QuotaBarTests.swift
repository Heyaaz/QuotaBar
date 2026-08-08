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
func parsesCodexLBAccounts() throws {
    let json = #"{"accounts":[{"accountId":"a1","email":"first@example.com","alias":"main","status":"active","usage":{"primaryRemainingPercent":20,"secondaryRemainingPercent":42},"resetAtSecondary":"2026-08-15T12:00:00Z","windowMinutesSecondary":10080},{"accountId":"a2","email":"second@example.com","displayName":"second@example.com","status":"active","usage":{"secondaryRemainingPercent":8}},{"accountId":"a3","email":"third@example.com","status":"paused","usage":{"secondaryRemainingPercent":99}}]}"#
    let snapshot = try CodexLBProvider.parseAccounts(Data(json.utf8), fetchedAt: .distantPast)

    #expect(snapshot.provider == .codex)
    #expect(snapshot.windows.map(\.shortLabel) == ["main", "second"])
    #expect(snapshot.windows.map(\.remainingPercent) == [42, 8])
    #expect(snapshot.windows[0].durationMinutes == 10_080)
    #expect(snapshot.windows[0].resetsAt != nil)
    #expect(snapshot.windows[1].resetsAt == nil)
}

@Test
func rejectsCodexLBResponseWithoutUsableAccounts() {
    let noUsage = #"{"accounts":[{"accountId":"a1","status":"active","usage":null}]}"#
    let noActive = #"{"accounts":[{"accountId":"a1","status":"paused","usage":{"secondaryRemainingPercent":50}}]}"#

    #expect(throws: ProviderError.self) {
        try CodexLBProvider.parseAccounts(Data(noUsage.utf8), fetchedAt: .distantPast)
    }
    #expect(throws: ProviderError.self) {
        try CodexLBProvider.parseAccounts(Data(noActive.utf8), fetchedAt: .distantPast)
    }
}

@Test
func readsCodexLBAccountsWhenLiveTestsAreEnabled() async throws {
    guard ProcessInfo.processInfo.environment["QUOTABAR_LIVE_TESTS"] == "1" else { return }

    let snapshot = try await CodexLBProvider().fetch()
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
func parsesGrokBillingWithoutUsageFields() throws {
    let json = #"{"jsonrpc":"2.0","id":2,"result":{"config":{"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","start":"2026-07-25T14:35:45.502164+00:00","end":"2026-08-01T14:35:45.502164+00:00"},"onDemandCap":{"val":0},"onDemandUsed":{"val":0},"prepaidBalance":{"val":0},"isUnifiedBillingUser":true,"billingPeriodStart":"2026-07-25T14:35:45.502164+00:00","billingPeriodEnd":"2026-08-01T14:35:45.502164+00:00"},"subscription_tier":"SuperGrok"}}"#
    let snapshot = try GrokProvider.parseBilling(Data(json.utf8), fetchedAt: .distantPast)

    #expect(snapshot.provider == .grok)
    #expect(snapshot.windows.map(\.shortLabel) == ["W"])
    #expect(snapshot.windows.map(\.remainingPercent) == [100])
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
func alertsMatchLabeledWindowsByAccount() {
    let previous = ProviderSnapshot(
        provider: .codex,
        windows: [
            QuotaWindow(durationMinutes: 10_080, remainingPercent: 30, resetsAt: nil, label: "main"),
            QuotaWindow(durationMinutes: 10_080, remainingPercent: 22, resetsAt: nil, label: "backup"),
        ],
        fetchedAt: .distantPast
    )
    let current = ProviderSnapshot(
        provider: .codex,
        windows: [
            QuotaWindow(durationMinutes: 10_080, remainingPercent: 28, resetsAt: nil, label: "main"),
            QuotaWindow(durationMinutes: 10_080, remainingPercent: 4, resetsAt: nil, label: "backup"),
        ],
        fetchedAt: .distantFuture
    )

    let alerts = QuotaAlert.crossings(from: previous, to: current)
    #expect(alerts.count == 1)
    #expect(alerts[0].windowLabel == "backup")
    #expect(alerts[0].threshold == 5)
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

@Test @MainActor
func ignoresLabeledAccountWindowsForMenuBarDisplay() {
    let states: [ProviderID: ProviderState] = [
        .codex: ProviderState(snapshot: ProviderSnapshot(
            provider: .codex,
            windows: [
                QuotaWindow(durationMinutes: 300, remainingPercent: 50, resetsAt: nil),
                QuotaWindow(durationMinutes: 10_080, remainingPercent: 5, resetsAt: nil, label: "pion0458"),
            ],
            fetchedAt: .distantPast
        )),
    ]

    // The account window is the lowest, but labeled windows never drive the menu bar.
    let lowest = StatusController.lowestQuota(in: states)
    #expect(lowest?.window.remainingPercent == 50)
}
