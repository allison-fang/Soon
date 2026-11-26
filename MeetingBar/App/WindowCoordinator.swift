//
//  WindowCoordinator.swift
//  MeetingBar
//

import AppKit
import SwiftUI

enum FullscreenNotificationScreenSelectionPolicy {
    static func select<Screen>(
        keyWindowScreen: Screen?,
        mainWindowScreen: Screen?,
        mouseScreen: Screen?,
        mainScreen: Screen?,
        screens: [Screen]
    ) -> Screen? {
        keyWindowScreen ?? mainWindowScreen ?? mouseScreen ?? mainScreen ?? screens.first
    }
}

enum FullscreenNotificationKeyboardPolicy {
    static let escapeKeyCode: UInt16 = 53

    static func shouldDismiss(keyCode: UInt16) -> Bool {
        keyCode == escapeKeyCode
    }
}

enum FullscreenNotificationRepositionPolicy {
    /// Decides whether an open alert must be moved after the display layout
    /// changed. An alert is stranded once any part of it falls outside every
    /// connected screen — e.g. it was shown on an external monitor that has
    /// since been disconnected — so it should be moved back onto a visible
    /// screen. An alert still fully on a connected screen is left alone, so a
    /// benign change elsewhere doesn't yank it to another display.
    static func needsReposition(
        windowFrame: CGRect,
        screenFrames: [CGRect],
        isVisible: Bool = true
    ) -> Bool {
        guard isVisible else { return false }
        return !screenFrames.contains { $0.contains(windowFrame) }
    }
}

final class FullscreenNotificationWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        if FullscreenNotificationKeyboardPolicy.shouldDismiss(keyCode: event.keyCode) {
            close()
            return
        }
        super.keyDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        close()
    }
}

final class OnboardingWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            close()
            return
        }
        super.keyDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        close()
    }
}

enum OnboardingWindowPresentationPolicy {
    static let contentRect = NSRect(x: 0, y: 0, width: 760, height: 520)
    static let minimumSize = NSSize(width: 640, height: 460)
    static let styleMask: NSWindow.StyleMask = [
        .titled, .closable, .miniaturizable, .resizable, .fullSizeContentView
    ]
    static let level: NSWindow.Level = .normal
    static let isMovableByWindowBackground = true
}

/// Owns AppKit window lifecycle for app-level windows.
///
/// Behavior stays outside this type: callers provide closures for close-time
/// decisions such as terminating after incomplete onboarding.
@MainActor
final class WindowCoordinator {
    private(set) weak var preferencesWindow: NSWindow?
    let preferencesNavigation = PreferencesNavigation()
    private(set) weak var onboardingWindow: NSWindow?
    private(set) weak var onboardingHandler: OnboardingHandler?

    /// Open fullscreen notification windows, tracked so they can be moved onto
    /// the appropriate screen when the display configuration changes (e.g. an
    /// external monitor is connected or disconnected while the alert is up).
    private var fullscreenNotificationWindows = NSHashTable<NSWindow>.weakObjects()

    /// Whether the coordinator is already observing screen-parameter changes.
    /// The observer is registered lazily on the first fullscreen notification.
    private var isObservingScreenParameters = false

    private var pendingPreferencesContent: NSView?
    private var preferencesActivationObserver: NSObjectProtocol?

    func openOnboardingWindow(
        appModel: AppModel,
        onProviderSelected:
            @escaping @MainActor (EventStoreProvider) async -> ProviderSelectionResult,
        onComplete:
            @escaping @MainActor (EventStoreProvider) async -> ProviderSelectionResult
    ) {
        if let onboardingWindow {
            NSApp.activate(ignoringOtherApps: true)
            onboardingWindow.makeKeyAndOrderFront(nil)
            onboardingWindow.orderFrontRegardless()
            return
        }
        let handler = OnboardingHandler(
            onProviderSelected: onProviderSelected,
            onComplete: onComplete
        )
        handler.appModel = appModel
        onboardingHandler = handler
        let contentView = OnboardingView().environmentObject(handler)
        let onboardingWindow = OnboardingWindow(
            contentRect: OnboardingWindowPresentationPolicy.contentRect,
            styleMask: OnboardingWindowPresentationPolicy.styleMask,
            backing: .buffered,
            defer: false
        )

        onboardingWindow.title = WindowTitles.onboarding
        onboardingWindow.contentView = NSHostingView(rootView: contentView)
        onboardingWindow.minSize = OnboardingWindowPresentationPolicy.minimumSize
        onboardingWindow.isMovableByWindowBackground =
            OnboardingWindowPresentationPolicy.isMovableByWindowBackground
        onboardingWindow.titlebarAppearsTransparent = true
        let controller = NSWindowController(window: onboardingWindow)
        controller.showWindow(self)

        // Standard level: onboarding should open focused, but it must not stay
        // above Chrome or other apps during provider authorization.
        onboardingWindow.level = OnboardingWindowPresentationPolicy.level
        onboardingWindow.center()
        // MeetingBar is a menu-bar agent, so it isn't the active app when the
        // setup window opens. Without activating, the window never becomes key
        // until the user clicks it, and prominent (accent) controls render
        // without their fill — making the Continue button look absent.
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow.makeKeyAndOrderFront(nil)
        // `activate` is async for an accessory app, so force initial ordering
        // only once. The standard window level still lets other apps cover it.
        onboardingWindow.orderFrontRegardless()
        self.onboardingWindow = onboardingWindow
    }

    /// Presents the borderless fullscreen alert for an event on the preferred
    /// screen, and tracks it so it can be moved if the display layout changes
    /// while it is showing.
    func openFullscreenNotificationWindow(event: MBEvent) {
        let screenFrame = preferredFullscreenScreen()?.frame
            ?? NSRect(x: 0, y: 0, width: 800, height: 600)

        let window = FullscreenNotificationWindow(
            contentRect: screenFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.contentView = NSHostingView(
            rootView: FullscreenNotification(event: event, window: window))
        window.appearance = NSAppearance(named: .darkAqua)
        window.collectionBehavior = .moveToActiveSpace

        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.title = "Meetingbar Fullscreen Notification"
        window.level = .screenSaver

        // Track the window and start observing display changes so the alert can
        // be moved onto the right screen if monitors are connected/disconnected
        // while it is showing.
        fullscreenNotificationWindows.add(window)
        startObservingScreenParametersIfNeeded()

        let controller = NSWindowController(window: window)
        controller.showWindow(self)

        window.setFrame(screenFrame, display: true)
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    /// Uses the same precedence whether the window is being opened or
    /// repositioned, so both paths land on the same screen.
    private func preferredFullscreenScreen() -> NSScreen? {
        let screens = NSScreen.screens
        // AppKit already guarantees `NSWindow.screen` / `NSScreen.main` are
        // members of the current `screens` (or nil), but guard explicitly so a
        // disconnected display can never be selected — otherwise we could resize
        // a stranded alert onto another off-screen frame.
        func connected(_ screen: NSScreen?) -> NSScreen? {
            guard let screen, screens.contains(screen) else { return nil }
            return screen
        }
        let mouseScreen = screens.first { $0.frame.contains(NSEvent.mouseLocation) }
        return FullscreenNotificationScreenSelectionPolicy.select(
            keyWindowScreen: connected(NSApp.keyWindow?.screen),
            mainWindowScreen: connected(NSApp.mainWindow?.screen),
            mouseScreen: mouseScreen,
            mainScreen: connected(NSScreen.main),
            screens: screens
        )
    }

    /// Registers the screen-parameter observer on first use. Idempotent, so
    /// repeated fullscreen notifications don't stack duplicate observers.
    private func startObservingScreenParametersIfNeeded() {
        guard !isObservingScreenParameters else { return }
        isObservingScreenParameters = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    /// Moves any open fullscreen notification that the display change left
    /// stranded onto the current preferred screen. Without this, an alert shown
    /// on an external monitor stays at the old geometry after the monitor is
    /// disconnected — leaving it off-screen and impossible to dismiss. Alerts
    /// still fully on a connected screen are left where they are.
    @objc
    private func screenParametersDidChange() {
        let screenFrames = NSScreen.screens.map(\.frame)
        guard let targetFrame = preferredFullscreenScreen()?.frame else { return }
        for case let window as NSWindow in fullscreenNotificationWindows.allObjects {
            guard FullscreenNotificationRepositionPolicy.needsReposition(
                windowFrame: window.frame,
                screenFrames: screenFrames,
                isVisible: window.isVisible
            ) else { continue }
            window.setFrame(targetFrame, display: true)
            window.orderFrontRegardless()
        }
    }

    func openPreferencesWindow(
        appModel: AppModel?,
        calendarSync: CalendarSync?,
        updateChecker: UpdateChecker,
        updateInstaller: UpdateInstaller,
        tab: PreferencesTab? = nil
    ) {
        guard let appModel, let calendarSync else { return }
        if let tab {
            preferencesNavigation.selectedTab = tab
        }
        let contentView = PreferencesView(navigation: preferencesNavigation)
            .environmentObject(appModel)
            .environmentObject(calendarSync)
            .environmentObject(updateChecker)
            .environmentObject(updateInstaller)
            .environment(\.preferencesWindowOpenedAt, Date())

        if let preferencesWindow {
            if preferencesWindow.isMiniaturized {
                preferencesWindow.deminiaturize(nil)
            }
            // Activate the (accessory) app first, then key the existing window,
            // so reopening Preferences brings it to front *and* focused.
            NSApplication.shared.activate(ignoringOtherApps: true)
            preferencesWindow.makeKeyAndOrderFront(nil)
            // `activate` is async for an accessory app, so force the window to
            // the front regardless of when activation lands; otherwise it can
            // be ordered behind other apps' windows.
            preferencesWindow.orderFrontRegardless()
            return
        }

        preferencesNavigation.selectedTab = tab ?? .defaultSelection
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 620),
            styleMask: [.closable, .titled, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = WindowTitles.preferences
        setPreferencesContentOnceActive(NSHostingView(rootView: contentView), in: window)
        // No custom rounded-corner / shadow layer here: this is a standard
        // titled window, so the system draws its own corners and shadow. The
        // full-size content view lets the NavigationSplitView sidebar flow up
        // under the title bar; the active tab name is shown via the detail's
        // `.navigationTitle`. The titlebar stays non-transparent so the toolbar
        // draws its scroll-edge material and scrolled content can't collide
        // with the title.
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        // Standard window level (not .floating): clicking another app should
        // send Preferences behind it, like any normal window.

        let controller = NSWindowController(window: window)
        controller.showWindow(self)
        window.center()

        // This is an LSUIElement accessory app, so it isn't frontmost by
        // default. Activate the app *before* keying the window so Preferences
        // opens focused rather than just ordered to the front.
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        // `activate` is async for an accessory app, so force the window to the
        // front regardless of when activation lands; otherwise it can open
        // behind other apps' windows.
        window.orderFrontRegardless()

        preferencesWindow = window
    }

    /// The timeline popover never activates the app, so Settings opened from it
    /// would draw before activation lands. SwiftUI switches drawn while the app
    /// is inactive keep a stale "on" look (no knob) once it activates, so the
    /// content waits for activation.
    private func setPreferencesContentOnceActive(_ content: NSView, in window: NSWindow) {
        stopWaitingForActivation()
        guard !NSApplication.shared.isActive else {
            window.contentView = content
            return
        }
        pendingPreferencesContent = content
        preferencesActivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self, weak window] _ in
            MainActor.assumeIsolated { self?.installPendingPreferencesContent(in: window) }
        }
        // Activation can be refused; never leave the window empty.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self, weak window] in
            MainActor.assumeIsolated { self?.installPendingPreferencesContent(in: window) }
        }
    }

    private func installPendingPreferencesContent(in window: NSWindow?) {
        guard let window, window === preferencesWindow else { return }
        let content = pendingPreferencesContent
        stopWaitingForActivation()
        if let content {
            window.contentView = content
        }
    }

    private func stopWaitingForActivation() {
        if let preferencesActivationObserver {
            NotificationCenter.default.removeObserver(preferencesActivationObserver)
        }
        preferencesActivationObserver = nil
        pendingPreferencesContent = nil
    }

    func handleWindowClosed(
        _ window: NSWindow?,
        onboardingCompleted: Bool,
        onIncompleteOnboardingClosed: () -> Void
    ) {
        handleWindowClosed(
            title: window?.title,
            onboardingCompleted: onboardingCompleted,
            onIncompleteOnboardingClosed: onIncompleteOnboardingClosed
        )
    }

    func handleWindowClosed(
        title windowTitle: String?,
        onboardingCompleted: Bool,
        onIncompleteOnboardingClosed: () -> Void
    ) {
        guard let windowTitle else { return }

        if windowTitle == WindowTitles.onboarding {
            onboardingWindow = nil
            if !onboardingCompleted {
                onIncompleteOnboardingClosed()
            }
        }
    }
}
