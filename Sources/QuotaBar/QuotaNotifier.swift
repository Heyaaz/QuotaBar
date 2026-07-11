import UserNotifications

struct QuotaAlert: Equatable, Sendable {
    let provider: ProviderID
    let windowLabel: String
    let remainingPercent: Int
    let threshold: Int

    static func crossings(
        from previous: ProviderSnapshot?,
        to current: ProviderSnapshot
    ) -> [QuotaAlert] {
        guard let previous, previous.provider == current.provider else { return [] }

        return current.windows.compactMap { window in
            guard let oldPercent = previous.windows.first(where: {
                $0.durationMinutes == window.durationMinutes
            })?.remainingPercent else { return nil }

            guard let threshold = [5, 20].first(where: {
                oldPercent > $0 && window.remainingPercent <= $0
            }) else { return nil }

            return QuotaAlert(
                provider: current.provider,
                windowLabel: window.shortLabel,
                remainingPercent: window.remainingPercent,
                threshold: threshold
            )
        }
    }
}

@MainActor
final class QuotaNotifier {
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func notifyCrossings(from previous: ProviderSnapshot?, to current: ProviderSnapshot) {
        for alert in QuotaAlert.crossings(from: previous, to: current) {
            let content = UNMutableNotificationContent()
            content.title = "\(alert.provider.rawValue) \(alert.windowLabel) quota low"
            content.body = "\(alert.remainingPercent)% remaining — crossed \(alert.threshold)%"
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )
            UNUserNotificationCenter.current().add(request)
        }
    }
}
