//
//  StatusBarPopoverController.swift
//  MeetingBar
//

import AppKit
import SwiftUI

/// A borderless panel that takes key status without activating the app, so
/// opening the timeline leaves the frontmost app's menu bar and focus alone.
final class StatusBarPanel: NSPanel {
    var onCancel: (() -> Void)?
    var onKeyDown: ((NSEvent) -> Bool)?
    var onKeyEquivalent: ((NSEvent) -> Bool)?

    private let acceptsKey: Bool

    init(acceptsKey: Bool) {
        self.acceptsKey = acceptsKey
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .popUpMenu
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
    }

    override var canBecomeKey: Bool { acceptsKey }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_: Any?) {
        onCancel?()
    }

    override func keyDown(with event: NSEvent) {
        if onKeyDown?(event) != true {
            super.keyDown(with: event)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        onKeyEquivalent?(event) == true || super.performKeyEquivalent(with: event)
    }
}

/// The details panel is never key, so its first click must reach its buttons.
final class StatusBarPanelHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for _: NSEvent?) -> Bool { true }
}

enum StatusBarPopoverKey {
    static let returnKey: UInt16 = 36
    static let tab: UInt16 = 48
    static let escape: UInt16 = 53
    static let keypadEnter: UInt16 = 76
    static let downArrow: UInt16 = 125
    static let upArrow: UInt16 = 126
}

@MainActor
final class StatusBarPopoverController {
    private static let cornerRadius: CGFloat = 12
    private static let detailsMaxHeight: CGFloat = 560
    private static let chromeHeight: CGFloat = 160
    private static let clockInterval: TimeInterval = 30
    private static let showDetailsDelay: TimeInterval = 0.2
    private static let switchDetailsDelay: TimeInterval = 0.12
    private static let hideDetailsDelay: TimeInterval = 0.25

    let model = StatusBarPopoverModel()

    var onClose: () -> Void = {}
    var onClockTick: () -> Void = {}
    var isFantasticalInstalled = false
    var timeFormat: TimeFormat = .military

    private var panel: StatusBarPanel?
    private var hostingView: NSView?
    private var detailsPanel: StatusBarPanel?
    private var detailsEvent: TimelineEventPresentation?
    private var pendingDetailsChange: DispatchWorkItem?
    private var monitors: [Any] = []
    private var observers: [NSObjectProtocol] = []
    private var clock: Timer?
    private weak var anchorButton: NSStatusBarButton?

    var isOpen: Bool { panel != nil }

    private var metrics: TimelineMetrics {
        TimelineMetrics(density: model.presentation.density)
    }

    init() {
        model.onEventHover = { [weak self] id, isHovering in
            self?.eventHoverChanged(id: id, isHovering: isHovering)
        }
    }

    func update(_ presentation: StatusBarPopoverPresentation) {
        model.presentation = presentation
        guard isOpen else { return }
        refitPanel()
        refreshDetails()
    }

    // MARK: - Showing

    func open(relativeTo button: NSStatusBarButton) {
        guard panel == nil,
              let buttonWindow = button.window,
              let screen = buttonWindow.screen ?? NSScreen.main
        else { return }

        anchorButton = button
        model.maxTimelineHeight = min(
            metrics.maxTimelineHeight,
            screen.visibleFrame.height - Self.chromeHeight
        )

        let hosting = StatusBarPanelHostingView(rootView: StatusBarPopoverView(model: model))
        let panel = StatusBarPanel(acceptsKey: true)
        panel.contentView = Self.container(for: hosting)
        panel.onCancel = { [weak self] in self?.close() }
        panel.onKeyDown = { [weak self] in self?.handleKeyDown($0) ?? false }
        panel.onKeyEquivalent = { [weak self] in self?.handleKeyEquivalent($0) ?? false }

        self.panel = panel
        hostingView = hosting
        refitPanel()
        panel.makeKeyAndOrderFront(nil)
        // Waits for the first layout pass, and for the button's own mouse
        // tracking, which clears its highlight.
        DispatchQueue.main.async { [weak self, weak button] in
            self?.model.scrollToNow()
            button?.highlight(true)
        }
        startMonitoring(panel)
    }

    func close() {
        guard let panel else { return }
        pendingDetailsChange?.cancel()
        pendingDetailsChange = nil
        hideDetails()
        stopMonitoring()

        panel.orderOut(nil)
        self.panel = nil
        hostingView = nil
        model.highlightedEventID = nil
        model.removeAllAnchors()
        anchorButton?.highlight(false)
        anchorButton = nil
        onClose()
    }

    private func refitPanel() {
        guard let panel, let hostingView, let screen = currentScreen else { return }
        hostingView.layoutSubtreeIfNeeded()
        let frame = StatusBarPopoverPlacement.popoverFrame(
            size: hostingView.fittingSize,
            button: anchorFrame,
            visible: screen.visibleFrame
        )
        panel.setFrame(frame, display: true)
        panel.invalidateShadow()
    }

    private var anchorFrame: NSRect {
        guard let button = anchorButton, let window = button.window else { return .zero }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    private var currentScreen: NSScreen? {
        anchorButton?.window?.screen ?? NSScreen.main
    }

    private static func container(for content: NSView) -> NSView {
        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.maskImage = roundedMask(radius: cornerRadius)

        content.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            content.topAnchor.constraint(equalTo: effect.topAnchor),
            content.bottomAnchor.constraint(equalTo: effect.bottomAnchor)
        ])
        return effect
    }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }

    // MARK: - Dismissal

    private func startMonitoring(_ panel: NSPanel) {
        let closeOnOutsideClick: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]

        if let global = NSEvent.addGlobalMonitorForEvents(
            matching: closeOnOutsideClick,
            handler: { [weak self] _ in
                MainActor.assumeIsolated { self?.close() }
            }
        ) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(
            matching: closeOnOutsideClick,
            handler: { [weak self] event in
                nonisolated(unsafe) let click = event
                MainActor.assumeIsolated {
                    if let self, self.isOutsideClick(click) {
                        self.close()
                    }
                }
                return event
            }
        ) {
            monitors.append(local)
        }

        let center = NotificationCenter.default
        observers = [
            center.addObserver(
                forName: NSWindow.didResignKeyNotification,
                object: panel,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.close() }
            },
            center.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.close() }
            }
        ]

        clock = Timer.scheduledTimer(withTimeInterval: Self.clockInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.onClockTick() }
        }
    }

    private func stopMonitoring() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        clock?.invalidate()
        clock = nil
    }

    private func isOutsideClick(_ event: NSEvent) -> Bool {
        // The status button toggles the popover itself; closing here too would
        // reopen it on the same click.
        event.window !== panel
            && event.window !== detailsPanel
            && event.window !== anchorButton?.window
    }

    // MARK: - Details

    private func eventHoverChanged(id: String, isHovering: Bool) {
        if isHovering {
            model.highlightedEventID = id
            let delay = detailsPanel == nil ? Self.showDetailsDelay : Self.switchDetailsDelay
            scheduleDetailsChange(after: delay) { [weak self] in
                self?.showDetails(eventID: id)
            }
        } else if model.highlightedEventID == id {
            scheduleDetailsChange(after: Self.hideDetailsDelay) { [weak self] in
                self?.hideDetails()
                self?.model.highlightedEventID = nil
            }
        }
    }

    private func detailsHoverChanged(isHovering: Bool) {
        if isHovering {
            pendingDetailsChange?.cancel()
        } else {
            scheduleDetailsChange(after: Self.hideDetailsDelay) { [weak self] in
                self?.hideDetails()
                self?.model.highlightedEventID = nil
            }
        }
    }

    private func scheduleDetailsChange(
        after delay: TimeInterval,
        _ change: @escaping @MainActor () -> Void
    ) {
        pendingDetailsChange?.cancel()
        let work = DispatchWorkItem { MainActor.assumeIsolated { change() } }
        pendingDetailsChange = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func refreshDetails() {
        guard let detailsEvent else { return }
        guard let event = model.presentation.events.first(where: { $0.id == detailsEvent.id }) else {
            hideDetails()
            return
        }
        // The clock ticks while the panel is read; rebuilding it would reset its scroll.
        if event != detailsEvent {
            showDetails(eventID: event.id)
        }
    }

    private func showDetails(eventID: String) {
        guard let panel,
              let screen = currentScreen,
              let event = model.presentation.events.first(where: { $0.id == eventID }),
              let anchor = model.anchor(id: eventID)?.screenFrame
        else { return }

        let metrics = metrics
        let content = EventDetailsView(
            event: event,
            metrics: metrics,
            timeFormat: timeFormat,
            isFantasticalInstalled: isFantasticalInstalled,
            actions: model.actions
        )
        let fitted = content.fitted(
            maxHeight: min(Self.detailsMaxHeight, screen.visibleFrame.height - 16)
        )
        let root = EventDetailsContainer(
            content: fitted.view,
            onHover: { [weak self] in self?.detailsHoverChanged(isHovering: $0) }
        )
        let details = detailsPanel ?? makeDetailsPanel()
        details.contentView = Self.container(for: StatusBarPanelHostingView(rootView: root))
        details.setFrame(
            StatusBarPopoverPlacement.detailsFrame(
                size: CGSize(width: metrics.detailsWidth, height: fitted.height),
                anchor: anchor,
                popover: panel.frame,
                visible: screen.visibleFrame
            ),
            display: true
        )
        details.invalidateShadow()
        details.orderFront(nil)
        detailsEvent = event
    }

    private func makeDetailsPanel() -> StatusBarPanel {
        let details = StatusBarPanel(acceptsKey: false)
        detailsPanel = details
        return details
    }

    private func hideDetails() {
        detailsPanel?.orderOut(nil)
        detailsPanel = nil
        detailsEvent = nil
    }

    // MARK: - Keyboard

    /// Like a menu, the panel ignores other typing instead of beeping. Tab
    /// stays with AppKit so Full Keyboard Access can reach the buttons.
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case StatusBarPopoverKey.downArrow:
            moveHighlight(by: 1)
        case StatusBarPopoverKey.upArrow:
            moveHighlight(by: -1)
        case StatusBarPopoverKey.escape:
            close()
        case StatusBarPopoverKey.returnKey, StatusBarPopoverKey.keypadEnter:
            if let event = highlightedEvent, event.canJoin {
                model.actions.join(event.event)
            }
        case StatusBarPopoverKey.tab:
            return false
        default:
            break
        }
        return true
    }

    private func handleKeyEquivalent(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command else {
            return false
        }
        switch event.charactersIgnoringModifiers {
        case ",":
            model.actions.openPreferences()
        case "q":
            model.actions.quit()
        case "r":
            model.actions.refresh()
        default:
            return false
        }
        return true
    }

    private var highlightedEvent: TimelineEventPresentation? {
        model.presentation.events.first { $0.id == model.highlightedEventID }
    }

    private func moveHighlight(by step: Int) {
        let events = model.presentation.events
        guard !events.isEmpty else { return }

        let index: Int
        if let current = events.firstIndex(where: { $0.id == model.highlightedEventID }) {
            index = min(max(current + step, 0), events.count - 1)
        } else {
            index = events.firstIndex(where: \.isNext) ?? 0
        }

        let id = events[index].id
        model.highlightedEventID = id
        model.anchor(id: id)?.scrollIntoView()
        scheduleDetailsChange(after: Self.switchDetailsDelay) { [weak self] in
            self?.showDetails(eventID: id)
        }
    }
}

private struct EventDetailsContainer: View {
    let content: EventDetailsView
    let onHover: (Bool) -> Void

    var body: some View {
        content
            .background(TimelineAnchor(onHover: onHover))
    }
}
