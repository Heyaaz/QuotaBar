import AppKit
import ServiceManagement

@MainActor
final class StatusController: NSObject {
    private let store: UsageStore
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let popoverController: UsagePopoverController
    private var displayMode: MenuBarDisplayMode

    init(store: UsageStore) {
        self.store = store
        let displayMode = MenuBarDisplayMode(
            rawValue: UserDefaults.standard.string(forKey: "menuBarDisplayMode") ?? ""
        ) ?? .all
        self.displayMode = displayMode
        self.popoverController = UsagePopoverController(store: store, displayMode: displayMode)
        super.init()

        popover.behavior = .transient
        popover.contentSize = NSSize(width: 340, height: 310)
        popover.contentViewController = popoverController

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover)
            button.sendAction(on: [.leftMouseUp])
            button.setAccessibilityLabel("AI subscription usage")
            button.setAccessibilityHelp("Shows remaining Claude, Codex, Grok, and Kimi usage")
        }

        store.onChange = { [weak self] in self?.render() }
        popoverController.onDisplayModeChange = { [weak self] mode in
            self?.setDisplayMode(mode)
        }
        render()
    }

    private func render() {
        statusItem.length = NSStatusItem.variableLength
        statusItem.button?.attributedTitle = statusTitle()
        statusItem.button?.setAccessibilityLabel(
            ProviderID.allCases.map(accessibilityText).joined(separator: ", ")
        )
        statusItem.button?.toolTip = store.states.values.contains(where: \.isStale)
            ? "Some values are cached — click for details"
            : "AI subscription usage — click for details"
        popoverController.render()
    }

    private func statusTitle() -> NSAttributedString {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.controlTextColor,
        ]
        let title = NSMutableAttributedString()
        let entries: [(ProviderID, String)]

        switch displayMode {
        case .all:
            entries = ProviderID.allCases.map { ($0, usageText(for: $0)) }
        case .lowest:
            guard let lowest = Self.lowestQuota(in: store.states) else {
                return NSAttributedString(string: "…", attributes: attributes)
            }
            entries = [(
                lowest.provider,
                "\(lowest.window.shortLabel) \(lowest.window.remainingPercent)%"
            )]
        }

        for (index, entry) in entries.enumerated() {
            if index > 0 {
                title.append(NSAttributedString(string: "  │  ", attributes: attributes))
            }

            let attachment = NSTextAttachment()
            attachment.image = ProviderIcons.image(for: entry.0)
            attachment.bounds = NSRect(x: 0, y: -2, width: 13, height: 13)
            title.append(NSAttributedString(attachment: attachment))
            title.append(NSAttributedString(string: " \(entry.1)", attributes: attributes))
        }

        return title
    }

    private func usageText(for id: ProviderID) -> String {
        guard let state = store.states[id], let snapshot = state.snapshot else {
            return "—"
        }

        // Account windows (codex-lb) are labeled and only shown in the popover.
        let visible = snapshot.windows.filter { $0.label == nil }
        guard !visible.isEmpty else { return "—" }

        return visible
            .map { "\($0.shortLabel) \($0.remainingPercent)%" }
            .joined(separator: " · ")
    }

    private func accessibilityText(for id: ProviderID) -> String {
        guard let state = store.states[id], state.snapshot != nil else {
            return "\(id.rawValue) unavailable"
        }
        return "\(id.rawValue) \(usageText(for: id))\(state.isStale ? ", cached" : "")"
    }

    static func lowestQuota(
        in states: [ProviderID: ProviderState]
    ) -> (provider: ProviderID, window: QuotaWindow)? {
        var lowest: (provider: ProviderID, window: QuotaWindow)?
        for provider in ProviderID.allCases {
            for window in states[provider]?.snapshot?.windows ?? [] {
                // Labeled account windows (codex-lb) stay out of the menu bar.
                guard window.label == nil else { continue }
                if lowest == nil || window.remainingPercent < lowest!.window.remainingPercent {
                    lowest = (provider, window)
                }
            }
        }
        return lowest
    }

    private func setDisplayMode(_ mode: MenuBarDisplayMode) {
        guard displayMode != mode else { return }
        displayMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: "menuBarDisplayMode")
        popoverController.displayMode = mode
        render()
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}

@MainActor
private final class UsagePopoverController: NSViewController {
    private let store: UsageStore
    private let contentStack = NSStackView()
    private let refreshButton = NSButton()
    private let settingsButton = NSButton()
    private let spinner = NSProgressIndicator()
    var displayMode: MenuBarDisplayMode
    var onDisplayModeChange: ((MenuBarDisplayMode) -> Void)?

    init(store: UsageStore, displayMode: MenuBarDisplayMode) {
        self.store = store
        self.displayMode = displayMode
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root = NSView()

        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 13
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(contentStack)

        NSLayoutConstraint.activate([
            root.widthAnchor.constraint(equalToConstant: 340),
            contentStack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            contentStack.topAnchor.constraint(equalTo: root.topAnchor, constant: 14),
            contentStack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -14),
        ])
        view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        render()
    }

    func render() {
        guard isViewLoaded else { return }
        contentStack.arrangedSubviews.forEach { view in
            contentStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        contentStack.addArrangedSubview(makeHeader())
        for id in ProviderID.allCases {
            contentStack.addArrangedSubview(makeProviderRow(id))
        }
        contentStack.addArrangedSubview(makeFooter())
    }

    private func makeHeader() -> NSView {
        let title = text("AI usage", size: 15, weight: .semibold)
        refreshButton.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh usage")
        refreshButton.bezelStyle = .accessoryBarAction
        refreshButton.isBordered = false
        refreshButton.target = self
        refreshButton.action = #selector(refresh)
        refreshButton.setAccessibilityLabel("Refresh usage")

        spinner.style = .spinning
        spinner.controlSize = .small
        let refreshing = store.states.values.contains(where: \.isRefreshing)
        refreshing ? spinner.startAnimation(nil) : spinner.stopAnimation(nil)
        spinner.isHidden = !refreshing
        refreshButton.isEnabled = !refreshing

        let spacer = NSView()
        let row = NSStackView(views: [title, spacer, spinner, refreshButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 7
        row.widthAnchor.constraint(equalToConstant: 308).isActive = true
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return row
    }

    private func makeProviderRow(_ id: ProviderID) -> NSView {
        let state = store.states[id, default: ProviderState()]
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 5
        stack.widthAnchor.constraint(equalToConstant: 308).isActive = true

        let header = NSStackView()
        header.orientation = .horizontal
        header.alignment = .firstBaseline
        header.spacing = 8
        header.addArrangedSubview(text(id.rawValue, size: 13, weight: .semibold))

        if let error = state.errorMessage {
            let status = text(state.isStale ? "Stale · \(error)" : error, size: 10, color: .secondaryLabelColor)
            status.lineBreakMode = .byTruncatingTail
            header.addArrangedSubview(status)
        }
        stack.addArrangedSubview(header)

        if let snapshot = state.snapshot {
            for window in snapshot.windows {
                stack.addArrangedSubview(makeWindowRow(window))
            }
        } else if state.errorMessage == nil {
            stack.addArrangedSubview(text("Checking…", size: 11, color: .secondaryLabelColor))
        }

        return stack
    }

    private func makeWindowRow(_ window: QuotaWindow) -> NSView {
        let label = text(window.shortLabel, size: 11, weight: .medium)
        label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        label.lineBreakMode = .byTruncatingTail
        if window.label == nil {
            label.widthAnchor.constraint(equalToConstant: 28).isActive = true
        } else {
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            label.widthAnchor.constraint(lessThanOrEqualToConstant: 96).isActive = true
        }

        let percent = text("\(window.remainingPercent)% left", size: 12, weight: .medium)
        percent.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)

        let reset = window.resetsAt.map { "resets \(Self.resetFormatter.string(from: $0))" } ?? "reset unavailable"
        let resetLabel = text(reset, size: 10, color: .secondaryLabelColor)
        resetLabel.lineBreakMode = .byTruncatingTail
        resetLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let spacer = NSView()

        let row = NSStackView(views: [label, percent, spacer, resetLabel])
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 8
        row.widthAnchor.constraint(equalToConstant: 308).isActive = true
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return row
    }

    private func makeFooter() -> NSView {
        let latest = store.states.values.compactMap(\.snapshot?.fetchedAt).max()
        let updated = latest.map { "Updated \(Self.updatedFormatter.string(from: $0))" } ?? "Not updated yet"
        let label = text(updated, size: 10, color: .tertiaryLabelColor)
        let spacer = NSView()

        settingsButton.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings")
        settingsButton.bezelStyle = .accessoryBarAction
        settingsButton.isBordered = false
        settingsButton.target = self
        settingsButton.action = #selector(showSettings)
        settingsButton.setAccessibilityLabel("Settings")

        let quit = NSButton(title: "Quit", target: NSApp, action: #selector(NSApplication.terminate(_:)))
        quit.bezelStyle = .accessoryBarAction
        quit.controlSize = .small

        let row = NSStackView(views: [label, spacer, settingsButton, quit])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 7
        row.widthAnchor.constraint(equalToConstant: 308).isActive = true
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return row
    }

    private func text(
        _ value: String,
        size: CGFloat,
        weight: NSFont.Weight = .regular,
        color: NSColor = .labelColor
    ) -> NSTextField {
        let field = NSTextField(labelWithString: value)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = color
        return field
    }

    @objc private func refresh() {
        Task { await store.refresh() }
    }

    @objc private func showSettings() {
        let launchAtLogin = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchAtLogin.target = self
        launchAtLogin.state = switch SMAppService.mainApp.status {
        case .enabled: .on
        case .requiresApproval: .mixed
        default: .off
        }

        let menu = NSMenu()
        menu.addItem(launchAtLogin)
        menu.addItem(.separator())

        for (title, mode) in [
            ("Show All Providers", MenuBarDisplayMode.all),
            ("Show Lowest Only", MenuBarDisplayMode.lowest),
        ] {
            let item = NSMenuItem(
                title: title,
                action: #selector(selectDisplayMode(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = mode.rawValue
            item.state = displayMode == mode ? .on : .off
            menu.addItem(item)
        }

        menu.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: settingsButton.bounds.maxY),
            in: settingsButton
        )
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            switch service.status {
            case .enabled:
                try service.unregister()
            case .requiresApproval:
                SMAppService.openSystemSettingsLoginItems()
            default:
                try service.register()
            }
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    @objc private func selectDisplayMode(_ sender: NSMenuItem) {
        guard
            let rawValue = sender.representedObject as? String,
            let mode = MenuBarDisplayMode(rawValue: rawValue)
        else { return }

        displayMode = mode
        onDisplayModeChange?(mode)
    }

    private static let resetFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    private static let updatedFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter
    }()
}
