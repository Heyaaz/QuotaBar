import Foundation

enum ProviderID: String, Codable, CaseIterable, Sendable {
    case claude = "Claude"
    case codex = "Codex"
    case grok = "Grok"
}

enum MenuBarDisplayMode: String, Sendable {
    case all
    case lowest
}

struct QuotaWindow: Codable, Equatable, Sendable {
    let durationMinutes: Int?
    let remainingPercent: Int
    let resetsAt: Date?

    var shortLabel: String {
        guard let durationMinutes else { return "W" }
        if durationMinutes == 300 { return "5h" }
        if durationMinutes % 10_080 == 0 { return "W" }
        if durationMinutes % 1_440 == 0 { return "\(durationMinutes / 1_440)d" }
        if durationMinutes % 60 == 0 { return "\(durationMinutes / 60)h" }
        return "\(durationMinutes)m"
    }
}

struct ProviderSnapshot: Codable, Equatable, Sendable {
    let provider: ProviderID
    let windows: [QuotaWindow]
    let fetchedAt: Date
}

enum ProviderError: LocalizedError, Equatable, Sendable {
    case executableNotFound(String)
    case notAuthenticated
    case invalidResponse
    case processFailed(String)
    case timedOut

    var errorDescription: String? {
        switch self {
        case .executableNotFound(let name): "Install and sign in to \(name)."
        case .notAuthenticated: "Sign in with the official client."
        case .invalidResponse: "The provider returned an unsupported response."
        case .processFailed(let message): message
        case .timedOut: "The provider did not respond in time."
        }
    }
}

protocol UsageProvider: Sendable {
    var id: ProviderID { get }
    func fetch() async throws -> ProviderSnapshot
}

struct ProviderState: Equatable, Sendable {
    var snapshot: ProviderSnapshot?
    var errorMessage: String?
    var isRefreshing = false
    var isStale = false
}
