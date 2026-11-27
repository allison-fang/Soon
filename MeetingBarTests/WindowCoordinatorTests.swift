//
//  WindowCoordinatorTests.swift
//  MeetingBarTests
//

import XCTest

@testable import MeetingBar

@MainActor
final class WindowCoordinatorTests: XCTestCase {
    func testFullscreenScreenSelectionPrefersKeyThenMainWindowScreen() {
        XCTAssertEqual(
            FullscreenNotificationScreenSelectionPolicy.select(
                keyWindowScreen: "key",
                mainWindowScreen: "main-window",
                mouseScreen: "mouse",
                mainScreen: "main",
                screens: ["first"]
            ),
            "key"
        )
        XCTAssertEqual(
            FullscreenNotificationScreenSelectionPolicy.select(
                keyWindowScreen: nil,
                mainWindowScreen: "main-window",
                mouseScreen: "mouse",
                mainScreen: "main",
                screens: ["first"]
            ),
            "main-window"
        )
    }

    func testFullscreenScreenSelectionUsesMouseScreenFallback() {
        XCTAssertEqual(
            FullscreenNotificationScreenSelectionPolicy.select(
                keyWindowScreen: nil,
                mainWindowScreen: nil,
                mouseScreen: "mouse",
                mainScreen: "main",
                screens: ["first"]
            ),
            "mouse"
        )
    }

    func testFullscreenScreenSelectionUsesMainThenFirstScreenFallback() {
        XCTAssertEqual(
            FullscreenNotificationScreenSelectionPolicy.select(
                keyWindowScreen: nil,
                mainWindowScreen: nil,
                mouseScreen: nil,
                mainScreen: "main",
                screens: ["first"]
            ),
            "main"
        )
        XCTAssertEqual(
            FullscreenNotificationScreenSelectionPolicy.select(
                keyWindowScreen: nil,
                mainWindowScreen: nil,
                mouseScreen: nil,
                mainScreen: nil,
                screens: ["first"]
            ),
            "first"
        )
    }

    func testFullscreenKeyboardPolicyDismissesOnlyForEscape() {
        XCTAssertTrue(
            FullscreenNotificationKeyboardPolicy.shouldDismiss(
                keyCode: FullscreenNotificationKeyboardPolicy.escapeKeyCode
            )
        )
        XCTAssertFalse(FullscreenNotificationKeyboardPolicy.shouldDismiss(keyCode: 36))
    }

    func testClosedFullscreenNotificationWindowIsReleased() throws {
        let coordinator = WindowCoordinator()
        weak var weakWindow: NSWindow?
        weak var weakContentView: NSView?

        autoreleasepool {
            let existingWindows = Set(NSApp.windows.map(ObjectIdentifier.init))
            let now = Date()
            coordinator.openFullscreenNotificationWindow(
                event: makeFakeEvent(
                    id: "fullscreen-leak",
                    start: now.addingTimeInterval(60),
                    end: now.addingTimeInterval(1800),
                    withLink: true
                )
            )
            let createdWindows = NSApp.windows.filter {
                $0 is FullscreenNotificationWindow && !existingWindows.contains(ObjectIdentifier($0))
            }
            XCTAssertEqual(createdWindows.count, 1)
            let window = createdWindows.first
            weakWindow = window
            weakContentView = window?.contentView
        }

        // The alert must stay on screen without the coordinator holding it strongly.
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        try autoreleasepool {
            let window = try XCTUnwrap(weakWindow)
            XCTAssertTrue(window.isVisible)
            window.close()
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))

        XCTAssertNil(weakWindow)
        XCTAssertNil(weakContentView)
    }

    func testOnboardingWindowPolicyAllowsNormalMovableResizableWindow() {
        XCTAssertEqual(OnboardingWindowPresentationPolicy.level, .normal)
        XCTAssertTrue(
            OnboardingWindowPresentationPolicy.styleMask.isSuperset(
                of: [.titled, .closable, .miniaturizable, .resizable]
            )
        )
        XCTAssertTrue(OnboardingWindowPresentationPolicy.isMovableByWindowBackground)
        XCTAssertLessThan(
            OnboardingWindowPresentationPolicy.minimumSize.width,
            OnboardingWindowPresentationPolicy.contentRect.width
        )
        XCTAssertLessThan(
            OnboardingWindowPresentationPolicy.minimumSize.height,
            OnboardingWindowPresentationPolicy.contentRect.height
        )
    }

    func testOnboardingWindowHasStandardWindowControls() throws {
        let coordinator = WindowCoordinator()
        let harness = AppModelTestHarness()
        coordinator.openOnboardingWindow(
            appModel: harness.model,
            onComplete: { _ in .success }
        )
        let window = try XCTUnwrap(coordinator.onboardingWindow)
        defer { window.close() }

        XCTAssertTrue(window.isMovable)
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            let control = try XCTUnwrap(window.standardWindowButton(button))
            XCTAssertTrue(control.isEnabled)
            XCTAssertFalse(control.isHidden)
        }
    }

    func testReopeningOnboardingRetainsTheExistingWindowAndFlow() async throws {
        let coordinator = WindowCoordinator()
        let harness = AppModelTestHarness()
        var originalCompletionCount = 0
        coordinator.openOnboardingWindow(
            appModel: harness.model,
            onComplete: { _ in
                originalCompletionCount += 1
                return .success
            }
        )
        let originalWindow = try XCTUnwrap(coordinator.onboardingWindow)
        let originalHandler = try XCTUnwrap(coordinator.onboardingHandler)
        defer { originalWindow.close() }

        coordinator.openOnboardingWindow(
            appModel: harness.model,
            onComplete: { _ in
                XCTFail("Must retain the original flow")
                return .cancelled
            }
        )

        XCTAssertTrue(coordinator.onboardingWindow === originalWindow)
        XCTAssertTrue(coordinator.onboardingHandler === originalHandler)
        XCTAssertTrue(originalWindow.isVisible)
        let result = await originalHandler.onComplete(.macOSEventKit)
        XCTAssertEqual(result, .success)
        XCTAssertEqual(originalCompletionCount, 1)
    }

    func testPreferencesKeepTheUsersTabUnlessOneIsRequested() throws {
        let coordinator = WindowCoordinator()
        let harness = AppModelTestHarness()
        let sync = CalendarSync(provider: FakeEventStore(calendars: [], events: []), refreshInterval: 0)
        defer { sync.stop() }
        let updateChecker = UpdateChecker(dependencies: .init(
            currentVersion: "1.2.0",
            automaticChecksAllowed: false,
            isEnabled: { false },
            lastCheck: { nil },
            setLastCheck: { _ in },
            now: { Date() },
            fetchLatestRelease: { throw URLError(.cancelled) },
            sleep: { _ in }
        ))
        let updateInstaller = UpdateInstaller.live(currentVersion: "1.2.0")
        func open(_ tab: PreferencesTab? = nil) {
            coordinator.openPreferencesWindow(
                appModel: harness.model,
                calendarSync: sync,
                updateChecker: updateChecker,
                updateInstaller: updateInstaller,
                tab: tab
            )
        }

        open()
        let window = try XCTUnwrap(coordinator.preferencesWindow)
        defer { window.close() }
        XCTAssertEqual(coordinator.preferencesNavigation.selectedTab, .general)

        coordinator.preferencesNavigation.selectedTab = .advanced
        open()
        XCTAssertEqual(coordinator.preferencesNavigation.selectedTab, .advanced)

        open(.general)
        XCTAssertTrue(coordinator.preferencesWindow === window)
        XCTAssertEqual(coordinator.preferencesNavigation.selectedTab, .general)
    }

    func testFullscreenPresentationShowsJoinForJoinableEvent() {
        let event = makeFakeEvent(
            id: "joinable",
            start: Date(),
            end: Date().addingTimeInterval(1800),
            withLink: true
        )

        XCTAssertEqual(
            FullscreenNotificationPresentation.make(for: event).actions,
            [.dismiss, .join]
        )
    }

    func testFullscreenPresentationShowsDismissOnlyForNoLinkEvent() {
        let event = makeFakeEvent(
            id: "no-link",
            start: Date(),
            end: Date().addingTimeInterval(1800),
            withLink: false,
            calendarOpenURL: URL(string: "ical://ekevent/no-link")
        )

        XCTAssertEqual(
            FullscreenNotificationPresentation.make(for: event).actions,
            [.dismiss]
        )
    }

    func testOnboardingCloseRunsIncompleteOnboardingClosureOnlyWhenNotCompleted() {
        let coordinator = WindowCoordinator()
        var incompleteCloseCount = 0

        coordinator.handleWindowClosed(
            title: WindowTitles.onboarding,
            onboardingCompleted: false,
            onIncompleteOnboardingClosed: { incompleteCloseCount += 1 }
        )

        XCTAssertEqual(incompleteCloseCount, 1)

        coordinator.handleWindowClosed(
            title: WindowTitles.onboarding,
            onboardingCompleted: true,
            onIncompleteOnboardingClosed: { incompleteCloseCount += 1 }
        )

        XCTAssertEqual(incompleteCloseCount, 1)
    }

    /// An external monitor an alert was shown on is disconnected: its frame no
    /// longer intersects any connected screen, so the alert must be moved.
    func testRepositionNeededWhenAlertScreenDisconnected() {
        let builtIn = CGRect(x: 0, y: 0, width: 1440, height: 900)
        // Alert is sitting on a second display to the right that is now gone.
        let alertOnExternal = CGRect(x: 1440, y: 0, width: 1920, height: 1080)

        XCTAssertTrue(
            FullscreenNotificationRepositionPolicy.needsReposition(
                windowFrame: alertOnExternal,
                screenFrames: [builtIn]
            )
        )
    }

    /// The alert is still fully within a connected screen, so a display change
    /// elsewhere must not yank it to another screen.
    func testRepositionNotNeededWhenAlertStillOnConnectedScreen() {
        let builtIn = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let external = CGRect(x: 1440, y: 0, width: 1920, height: 1080)

        XCTAssertFalse(
            FullscreenNotificationRepositionPolicy.needsReposition(
                windowFrame: builtIn,
                screenFrames: [builtIn, external]
            )
        )
    }

    func testRepositionNotNeededForClosedAlert() {
        let builtIn = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let alertOnDisconnectedScreen = CGRect(x: 1440, y: 0, width: 1920, height: 1080)

        XCTAssertFalse(
            FullscreenNotificationRepositionPolicy.needsReposition(
                windowFrame: alertOnDisconnectedScreen,
                screenFrames: [builtIn],
                isVisible: false
            )
        )
    }

    /// A partially off-screen alert (overlapping a connected screen but not
    /// fully contained) is still considered stranded and is repositioned.
    func testRepositionNeededWhenAlertOnlyPartiallyOnScreen() {
        let builtIn = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let halfOff = CGRect(x: 1000, y: 0, width: 1440, height: 900)

        XCTAssertTrue(
            FullscreenNotificationRepositionPolicy.needsReposition(
                windowFrame: halfOff,
                screenFrames: [builtIn]
            )
        )
    }
}
