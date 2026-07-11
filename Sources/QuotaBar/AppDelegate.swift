import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = UsageStore()
    private let notifier = QuotaNotifier()
    private var statusController: StatusController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        notifier.requestAuthorization()
        store.onSnapshotUpdate = { [notifier] previous, current in
            notifier.notifyCrossings(from: previous, to: current)
        }
        statusController = StatusController(store: store)
        store.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.stop()
    }
}
