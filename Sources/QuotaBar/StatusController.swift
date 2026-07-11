import AppKit

@MainActor
final class StatusController: NSObject {
    private let store: UsageStore
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let popoverController: UsagePopoverController

    init(store: UsageStore) {
        self.store = store
        self.popoverController = UsagePopoverController(store: store)
        super.init()

        popover.behavior = .transient
        popover.contentSize = NSSize(width: 340, height: 310)
        popover.contentViewController = popoverController

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover)
            button.sendAction(on: [.leftMouseUp])
            button.setAccessibilityLabel("AI subscription usage")
            button.setAccessibilityHelp("Shows remaining Claude, Codex, and Grok usage")
        }

        store.onChange = { [weak self] in self?.render() }
        render()
    }

    private func render() {
        let text = ProviderID.allCases.map(statusText).joined(separator: "  │  ")
        statusItem.length = NSStatusItem.variableLength
        statusItem.button?.attributedTitle = NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor.controlTextColor,
            ]
        )
        statusItem.button?.toolTip = "AI subscription usage — click for details"
        popoverController.render()
    }

    private func statusText(for id: ProviderID) -> String {
        let name = switch id {
        case .claude: "C"
        case .codex: "GPT"
        case .grok: "X"
        }
        guard let state = store.states[id], let snapshot = state.snapshot else {
            return "\(name) —"
        }

        let values = snapshot.windows
            .map { "\($0.shortLabel) \($0.remainingPercent)%" }
            .joined(separator: " · ")
        return "\(name) \(values)\(state.isStale ? " ~" : "")"
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
    private let spinner = NSProgressIndicator()

    init(store: UsageStore) {
        self.store = store
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
        label.widthAnchor.constraint(equalToConstant: 28).isActive = true

        let percent = text("\(window.remainingPercent)% left", size: 12, weight: .medium)
        percent.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)

        let reset = window.resetsAt.map { "resets \(Self.resetFormatter.string(from: $0))" } ?? "reset unavailable"
        let resetLabel = text(reset, size: 10, color: .secondaryLabelColor)
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
        let quit = NSButton(title: "Quit", target: NSApp, action: #selector(NSApplication.terminate(_:)))
        quit.bezelStyle = .accessoryBarAction
        quit.controlSize = .small

        let row = NSStackView(views: [label, spacer, quit])
        row.orientation = .horizontal
        row.alignment = .centerY
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
