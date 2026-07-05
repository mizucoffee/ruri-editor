//
//  TerminalPanelAppKitView.swift
//  ruri
//

import AppKit

final class TerminalPanelAppKitView: NSView {
    private let stackView = NSStackView()
    private let headerView = NSView()
    private let tabBarView = TerminalTabBarAppKitView()
    private let newTabButton = NSButton()
    private let separator = NSBox()
    private let bodyContainerView = NSView()
    private let emptyView = TerminalEmptyAppKitView()
    private let focusLineView = FocusAccentLineView()

    private var createTab: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func update(
        workspaceURL: URL?,
        tabs: [TerminalTabSnapshot],
        selectedTabID: TerminalTab.ID?,
        selectedTerminalView: NSView?,
        isFocused: Bool,
        createTab: @escaping () -> Void,
        selectTab: @escaping (TerminalTab.ID) -> Void,
        closeTab: @escaping (TerminalTab.ID) -> Void
    ) {
        self.createTab = createTab

        newTabButton.isEnabled = workspaceURL != nil
        focusLineView.setVisible(isFocused)

        tabBarView.update(
            tabs: tabs,
            selectedTabID: selectedTabID,
            selectTab: selectTab,
            closeTab: closeTab
        )

        if let selectedTerminalView {
            replaceBodyContent(with: selectedTerminalView)
        } else {
            emptyView.update(
                message: workspaceURL == nil
                    ? "Open a folder to start a terminal."
                    : "No terminal tab is open."
            )
            replaceBodyContent(with: emptyView)
        }
    }

    @objc private func newTabButtonClicked() {
        createTab?()
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        translatesAutoresizingMaskIntoConstraints = false

        stackView.orientation = .vertical
        stackView.alignment = .width
        stackView.distribution = .fill
        stackView.spacing = 0
        stackView.translatesAutoresizingMaskIntoConstraints = false

        headerView.translatesAutoresizingMaskIntoConstraints = false
        bodyContainerView.translatesAutoresizingMaskIntoConstraints = false
        bodyContainerView.wantsLayer = true
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        setupHeader()

        addSubview(stackView)
        stackView.addArrangedSubview(headerView)
        stackView.addArrangedSubview(separator)
        stackView.addArrangedSubview(bodyContainerView)

        addSubview(focusLineView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),

            headerView.widthAnchor.constraint(equalTo: stackView.widthAnchor),
            headerView.heightAnchor.constraint(equalToConstant: EditorMetrics.terminalHeaderHeight),

            separator.widthAnchor.constraint(equalTo: stackView.widthAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),

            bodyContainerView.widthAnchor.constraint(equalTo: stackView.widthAnchor),

            focusLineView.leadingAnchor.constraint(equalTo: leadingAnchor),
            focusLineView.trailingAnchor.constraint(equalTo: trailingAnchor),
            focusLineView.topAnchor.constraint(equalTo: bodyContainerView.topAnchor),
            focusLineView.heightAnchor.constraint(equalToConstant: EditorMetrics.focusLineHeight)
        ])
    }

    private func setupHeader() {
        let headerStack = NSStackView()
        headerStack.orientation = .horizontal
        headerStack.alignment = .centerY
        headerStack.distribution = .fill
        headerStack.spacing = 8
        headerStack.translatesAutoresizingMaskIntoConstraints = false

        tabBarView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        tabBarView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        configureIconButton(
            newTabButton,
            symbolName: "plus",
            accessibilityDescription: "New Terminal Tab",
            action: #selector(newTabButtonClicked)
        )

        headerView.addSubview(headerStack)
        headerStack.addArrangedSubview(tabBarView)
        headerStack.addArrangedSubview(newTabButton)

        NSLayoutConstraint.activate([
            headerStack.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 12),
            headerStack.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -10),
            headerStack.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            tabBarView.widthAnchor.constraint(greaterThanOrEqualToConstant: 0),
            tabBarView.heightAnchor.constraint(equalToConstant: EditorMetrics.tabHeight),

            newTabButton.widthAnchor.constraint(equalToConstant: EditorMetrics.iconButtonSize),
            newTabButton.heightAnchor.constraint(equalToConstant: EditorMetrics.iconButtonSize)
        ])
    }

    private func configureIconButton(
        _ button: NSButton,
        symbolName: String,
        accessibilityDescription: String,
        action: Selector
    ) {
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibilityDescription)
        button.toolTip = accessibilityDescription
        button.isBordered = false
        button.imageScaling = .scaleProportionallyDown
        button.contentTintColor = .secondaryLabelColor
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
    }

    private func replaceBodyContent(with contentView: NSView) {
        if contentView.superview === bodyContainerView,
           bodyContainerView.subviews.count == 1 {
            return
        }

        bodyContainerView.subviews.forEach { $0.removeFromSuperview() }

        contentView.translatesAutoresizingMaskIntoConstraints = false
        bodyContainerView.addSubview(contentView)

        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: bodyContainerView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: bodyContainerView.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: bodyContainerView.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: bodyContainerView.bottomAnchor)
        ])
    }
}

private final class TerminalTabBarAppKitView: NSView {
    private let scrollView = NSScrollView()
    private let contentView = NSView()
    private let stackView = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func update(
        tabs: [TerminalTabSnapshot],
        selectedTabID: TerminalTab.ID?,
        selectTab: @escaping (TerminalTab.ID) -> Void,
        closeTab: @escaping (TerminalTab.ID) -> Void
    ) {
        stackView.arrangedSubviews.forEach { view in
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        for tab in tabs {
            let tabView = TerminalTabItemAppKitView(
                tab: tab,
                isSelected: tab.id == selectedTabID,
                selectTab: selectTab,
                closeTab: closeTab
            )
            stackView.addArrangedSubview(tabView)
        }
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.verticalScrollElasticity = .none

        contentView.translatesAutoresizingMaskIntoConstraints = false

        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.distribution = .fill
        stackView.spacing = 4
        stackView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(scrollView)
        scrollView.documentView = contentView
        contentView.addSubview(stackView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            contentView.heightAnchor.constraint(equalTo: scrollView.contentView.heightAnchor),
            contentView.widthAnchor.constraint(greaterThanOrEqualTo: scrollView.contentView.widthAnchor),

            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor),
            stackView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
    }
}

private final class TerminalTabItemAppKitView: NSView {
    private let tabID: TerminalTab.ID
    private let isSelected: Bool
    private let closeButton = NSButton()
    private let selectTab: (TerminalTab.ID) -> Void
    private let closeTab: (TerminalTab.ID) -> Void

    init(
        tab: TerminalTabSnapshot,
        isSelected: Bool,
        selectTab: @escaping (TerminalTab.ID) -> Void,
        closeTab: @escaping (TerminalTab.ID) -> Void
    ) {
        tabID = tab.id
        self.isSelected = isSelected
        self.selectTab = selectTab
        self.closeTab = closeTab

        super.init(frame: .zero)

        setup(tab: tab)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool {
        false
    }

    override func mouseDown(with event: NSEvent) {
        if containsEvent(event, in: closeButton) {
            closeTab(tabID)
            return
        }

        selectTab(tabID)
    }

    @objc private func closeButtonClicked() {
        closeTab(tabID)
    }

    private func setup(tab: TerminalTabSnapshot) {
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.backgroundColor = isSelected
            ? NSColor.controlAccentColor.withAlphaComponent(0.15).cgColor
            : NSColor.clear.cgColor

        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: EditorMetrics.tabHeight).isActive = true

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: tab.title)
        titleLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        titleLabel.textColor = isSelected ? .labelColor : .secondaryLabelColor
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close Terminal Tab")
        closeButton.isBordered = false
        closeButton.imageScaling = .scaleProportionallyDown
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.target = self
        closeButton.action = #selector(closeButtonClicked)
        closeButton.sendAction(on: [.leftMouseDown])
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stack)
        if let agentStatus = tab.agentStatus {
            stack.addArrangedSubview(TerminalAgentStatusAppKitView(agentStatus: agentStatus))
        }
        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(closeButton)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 9),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),

            titleLabel.widthAnchor.constraint(lessThanOrEqualToConstant: EditorMetrics.terminalTabMaxTitleWidth),

            closeButton.widthAnchor.constraint(equalToConstant: 16),
            closeButton.heightAnchor.constraint(equalToConstant: 16)
        ])
    }

    private func containsEvent(_ event: NSEvent, in view: NSView) -> Bool {
        let location = convert(event.locationInWindow, from: nil)
        let hitFrame = convert(view.bounds, from: view).insetBy(dx: -4, dy: -4)
        return hitFrame.contains(location)
    }
}

private final class TerminalAgentStatusAppKitView: NSView {
    private let agentStatus: CodingAgentTerminalStatus

    init(agentStatus: CodingAgentTerminalStatus) {
        self.agentStatus = agentStatus
        super.init(frame: .zero)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        toolTip = "\(agentStatus.status.displayTitle) \(agentStatus.status.state.rawValue) at \(agentStatus.status.event)"

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 14),
            heightAnchor.constraint(equalToConstant: 14)
        ])

        switch agentStatus.status.state {
        case .running:
            let progress = NSProgressIndicator()
            progress.style = .spinning
            progress.controlSize = .mini
            progress.isIndeterminate = true
            progress.startAnimation(nil)
            progress.translatesAutoresizingMaskIntoConstraints = false
            addSubview(progress)
            NSLayoutConstraint.activate([
                progress.centerXAnchor.constraint(equalTo: centerXAnchor),
                progress.centerYAnchor.constraint(equalTo: centerYAnchor),
                progress.widthAnchor.constraint(equalToConstant: 12),
                progress.heightAnchor.constraint(equalToConstant: 12)
            ])

        case .waiting, .completed, .error:
            let imageView = NSImageView()
            imageView.image = NSImage(
                systemSymbolName: systemSymbolName,
                accessibilityDescription: toolTip
            )
            imageView.contentTintColor = color
            imageView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
            imageView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(imageView)
            NSLayoutConstraint.activate([
                imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
                imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: 12),
                imageView.heightAnchor.constraint(equalToConstant: 12)
            ])
        }

        if agentStatus.isUnread {
            let unreadDot = NSView()
            unreadDot.wantsLayer = true
            unreadDot.layer?.cornerRadius = 2.5
            unreadDot.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
            unreadDot.translatesAutoresizingMaskIntoConstraints = false
            addSubview(unreadDot)
            NSLayoutConstraint.activate([
                unreadDot.widthAnchor.constraint(equalToConstant: 5),
                unreadDot.heightAnchor.constraint(equalToConstant: 5),
                unreadDot.topAnchor.constraint(equalTo: topAnchor),
                unreadDot.trailingAnchor.constraint(equalTo: trailingAnchor)
            ])
        }
    }

    private var systemSymbolName: String {
        switch agentStatus.status.state {
        case .running:
            "circle.dotted"
        case .waiting:
            "pause.circle.fill"
        case .completed:
            "checkmark.circle.fill"
        case .error:
            "exclamationmark.circle.fill"
        }
    }

    private var color: NSColor {
        switch agentStatus.status.state {
        case .running:
            .controlAccentColor
        case .waiting:
            .systemOrange
        case .completed:
            .secondaryLabelColor
        case .error:
            .systemRed
        }
    }
}

private final class TerminalEmptyAppKitView: NSView {
    private let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func update(message: String) {
        label.stringValue = message
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        label.font = .systemFont(ofSize: NSFont.systemFontSize)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24)
        ])
    }
}
