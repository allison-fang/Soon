//
//  StatusBarItemTests.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 28.05.2025.
//  Copyright © 2025 Andrii Leitsius. All rights reserved.
//

import AppKit
import Defaults
import SwiftUI
import XCTest

@testable import MeetingBar

@MainActor
final class StatusBarMenuStateTests: BaseTestCase {
    func testMenuStateMapsHealthyConnectedProvider() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let event = makeFakeEvent(
            id: "next",
            start: now.addingTimeInterval(300),
            end: now.addingTimeInterval(1800),
            withLink: true
        )
        var appState = AppState()
        appState.events = [event]
        appState.selectedCalendarIDs = ["calendar"]
        appState.activeProvider = .googleCalendar
        appState.providerHealth = .success(attempted: now)

        let state = StatusBarMenuState.make(
            from: appState,
            settings: .empty,
            now: now
        )

        XCTAssertEqual(state.nextEvent, event)
        XCTAssertEqual(state.activeProvider, .googleCalendar)
        XCTAssertEqual(state.providerStatus, .connected(lastRefresh: now))
        XCTAssertNil(state.emptyStateReason)
    }

    func testMenuStateMapsGoogleAuthRequired() {
        var appState = AppState()
        appState.activeProvider = .googleCalendar
        appState.providerHealth = ProviderHealth(
            lastErrorDescription: "Reconnect Google Calendar",
            isStale: true,
            authRequired: true
        )

        let state = StatusBarMenuState.make(from: appState, settings: .empty)

        XCTAssertEqual(
            state.providerStatus,
            .authRequired(message: "Reconnect Google Calendar")
        )
        XCTAssertEqual(state.providerWarning, .authRequired)
        XCTAssertEqual(state.emptyStateReason, .authRequired)
    }

    func testMenuStateMapsApplePermissionRequired() {
        var appState = AppState()
        appState.activeProvider = .macOSEventKit
        appState.providerHealth = ProviderHealth(
            lastErrorDescription: "Calendar access denied",
            calendarPermissionRequired: true
        )

        let state = StatusBarMenuState.make(from: appState, settings: .empty)

        XCTAssertEqual(
            state.providerStatus,
            .permissionRequired(message: "Calendar access denied")
        )
        XCTAssertEqual(state.emptyStateReason, .permissionRequired)
    }

    func testMenuStateMapsEventKitPermissionLossAfterSuccessfulRefresh() {
        var appState = AppState()
        appState.activeProvider = .macOSEventKit
        appState.providerHealth = ProviderHealth(
            lastSuccessfulRefresh: Date(timeIntervalSince1970: 1_700_000_000),
            lastErrorDescription: "Calendar access denied",
            isStale: true,
            calendarPermissionRequired: true
        )

        let state = StatusBarMenuState.make(from: appState, settings: .empty)
        XCTAssertEqual(
            state.providerStatus,
            .permissionRequired(message: "Calendar access denied")
        )
        XCTAssertEqual(state.providerWarning, .permissionRequired)
    }

    func testMenuStateMapsNoCalendarsSelected() {
        var appState = AppState()
        appState.providerHealth = .success(attempted: Date())

        let state = StatusBarMenuState.make(from: appState, settings: .empty)

        XCTAssertEqual(state.emptyStateReason, .noCalendarsSelected)
    }

    func testMenuStateMapsNoUpcomingMeetings() {
        var appState = AppState()
        appState.selectedCalendarIDs = ["calendar"]
        appState.providerHealth = .success(attempted: Date())

        let state = StatusBarMenuState.make(from: appState, settings: .empty)

        XCTAssertEqual(state.emptyStateReason, .noUpcomingMeetings)
    }

    func testMenuStateMapsStaleRefreshWithoutHidingKnownEvent() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let event = makeFakeEvent(
            id: "cached",
            start: now.addingTimeInterval(300),
            end: now.addingTimeInterval(1800)
        )
        var appState = AppState()
        appState.events = [event]
        appState.selectedCalendarIDs = ["calendar"]
        appState.providerHealth = ProviderHealth(
            lastSuccessfulRefresh: now.addingTimeInterval(-300),
            lastAttemptedRefresh: now,
            lastErrorDescription: "Network unavailable",
            isStale: true
        )

        let state = StatusBarMenuState.make(
            from: appState,
            settings: .empty,
            now: now
        )

        XCTAssertEqual(
            state.providerStatus,
            .stale(
                lastRefresh: now.addingTimeInterval(-300),
                message: "Network unavailable"
            )
        )
        XCTAssertNil(state.emptyStateReason)
        XCTAssertEqual(state.nextEvent, event)
    }
}

@MainActor
final class StatusBarTitleRendererTests: BaseTestCase {

    func test_stackedLayoutRendersEmptyAttributedTitle() {
        // The stacked (time-under-title) layout is drawn by
        // `StatusBarStackedTitleView` in an NSHostingView, so the attributed
        // title is intentionally empty for this layout.
        let title = StatusBarTitleRenderer.attributedTitle(
            for: makePresentation(layout: .stacked)
        )

        XCTAssertEqual(title.string, "")
    }

    func test_inlineTitleIncludesTimeAndUnderlineStyle() {
        let title = StatusBarTitleRenderer.attributedTitle(
            for: makePresentation(
                layout: .inline(showTime: true),
                titleStyle: .underlined
            )
        )

        XCTAssertEqual(title.string, "Weekly sync now")
        XCTAssertNotNil(title.attribute(.underlineStyle, at: 0, effectiveRange: nil))
    }

    func test_noneLayoutRendersEmptyTitle() {
        let title = StatusBarTitleRenderer.attributedTitle(
            for: makePresentation(layout: .none)
        )

        XCTAssertEqual(title.string, "")
    }

    private func makePresentation(
        layout: StatusBarTitleLayout,
        titleStyle: StatusBarTitleStyle = .normal
    ) -> StatusBarPresentation {
        StatusBarPresentation(
            mode: .nextEvent,
            title: "Weekly sync",
            time: "now",
            tooltip: "Weekly sync",
            icon: .none,
            layout: layout,
            titleStyle: titleStyle
        )
    }
}

@MainActor
final class StatusBarItemControllerPresentationTests: BaseTestCase {
    private static let calendarID = "status_bar_test_calendar"

    func test_renderStatusBarUsesFallbackImageWhenPresentationIsEmpty() throws {
        let controller = StatusBarItemController()
        defer { NSStatusBar.system.removeStatusItem(controller.statusItem) }

        controller.renderStatusBar(makePresentation(mode: .noUpcoming))

        let button = try XCTUnwrap(controller.statusItem.button)
        XCTAssertNotNil(button.image)
        XCTAssertEqual(button.title, "")
        XCTAssertEqual(button.attributedTitle.string, "")
    }

    func test_renderStatusBarDoesNotAddFallbackWhenTitleIsVisible() throws {
        let controller = StatusBarItemController()
        defer { NSStatusBar.system.removeStatusItem(controller.statusItem) }

        controller.renderStatusBar(makePresentation(
            title: "Visible meeting",
            layout: .inline(showTime: false)
        ))

        let button = try XCTUnwrap(controller.statusItem.button)
        XCTAssertNil(button.image)
        XCTAssertEqual(button.attributedTitle.string, "Visible meeting")
    }

    func test_renderStatusBarDoesNotOverrideExistingIcon() throws {
        let controller = StatusBarItemController()
        defer { NSStatusBar.system.removeStatusItem(controller.statusItem) }

        controller.renderStatusBar(makePresentation(
            mode: .noUpcoming,
            icon: .asset(MenuStyleConstants.calendarCheckmarkIconName)
        ))

        let button = try XCTUnwrap(controller.statusItem.button)
        XCTAssertEqual(
            button.image?.name(),
            MenuStyleConstants.iconNamed(
                MenuStyleConstants.calendarCheckmarkIconName
            ).name()
        )
    }

    func test_renderStatusBarUsesFallbackForHiddenEventTitleWithoutIcon() throws {
        let controller = StatusBarItemController()
        defer { NSStatusBar.system.removeStatusItem(controller.statusItem) }

        controller.renderStatusBar(makePresentation())

        let button = try XCTUnwrap(controller.statusItem.button)
        XCTAssertNotNil(button.image)
        XCTAssertEqual(button.attributedTitle.string, "")
    }

    func test_renderStatusBarUsesFallbackWhenSentinelIconIsHidden() throws {
        let controller = StatusBarItemController()
        defer { NSStatusBar.system.removeStatusItem(controller.statusItem) }

        // A next event without a meeting service resolves to the hidden
        // "no_online_session" sentinel (imagePosition == .noImage). With an empty
        // title that would leave the item completely blank, so it must fall back
        // to a visible icon instead.
        controller.renderStatusBar(makePresentation(icon: .meetingService(nil)))

        let button = try XCTUnwrap(controller.statusItem.button)
        XCTAssertEqual(button.imagePosition, .imageLeft)
        XCTAssertNotEqual(button.image?.name(), "no_online_session")
        XCTAssertEqual(button.attributedTitle.string, "")
    }

    func test_updateTitleCompactsLongVisibleTitleWithoutForcingFallbackIcon() throws {
        configureStatusBarDefaults()
        Defaults[.eventTitleIconFormat] = .none
        Defaults[.statusbarEventTitleLength] = statusbarEventTitleLengthLimits.max

        let controller = StatusBarItemController()
        defer { NSStatusBar.system.removeStatusItem(controller.statusItem) }
        let longTitle = String(repeating: "Very long meeting title ", count: 5)

        controller.events = [
            makeStatusEvent(
                title: longTitle,
                url: URL(string: "https://zoom.us/j/5551112222")!
            )
        ]
        controller.updateTitle()

        let button = try XCTUnwrap(controller.statusItem.button)
        XCTAssertNil(button.image)
        XCTAssertEqual(button.imagePosition, .imageLeft)
        XCTAssertTrue(button.attributedTitle.string.contains("..."))
        XCTAssertLessThan(button.attributedTitle.string.count, longTitle.count)
        XCTAssertEqual(button.alignment, .center)
        XCTAssertEqual(button.cell?.lineBreakMode, .byTruncatingTail)
    }

    func test_updateTitleClearsStaleAttributedTitleWhenNoUpcomingEventRemains() throws {
        configureStatusBarDefaults()

        let controller = StatusBarItemController()
        defer { NSStatusBar.system.removeStatusItem(controller.statusItem) }
        controller.events = [makeStatusEvent()]
        controller.updateTitle()

        let button = try XCTUnwrap(controller.statusItem.button)
        XCTAssertFalse(button.attributedTitle.string.isEmpty)

        controller.events = []
        controller.updateTitle()

        XCTAssertEqual(button.title, "")
        XCTAssertEqual(button.attributedTitle.string, "")
        XCTAssertNotNil(button.image)
    }

    func test_updateTitleUsesHostingViewForStackedTimeUnderTitle() throws {
        configureStatusBarDefaults()
        Defaults[.eventTimeFormat] = .show_under_title

        let controller = StatusBarItemController()
        defer { NSStatusBar.system.removeStatusItem(controller.statusItem) }
        controller.events = [makeStatusEvent()]
        controller.updateTitle()

        let button = try XCTUnwrap(controller.statusItem.button)
        // The stacked layout is drawn by a SwiftUI hosting view, so the
        // button's own title is empty and its image is an empty (zero-size)
        // placeholder that keeps the button in its normal drawing mode (so the
        // item dims with the menu bar); the item is sized from the hosting
        // view's intrinsic width.
        XCTAssertEqual(button.attributedTitle.string, "")
        XCTAssertEqual(button.image?.size, NSSize.zero)

        let hostingView = try XCTUnwrap(controller.stackedHostingView)
        XCTAssertFalse(hostingView.rootView.title.isEmpty)
        XCTAssertFalse(hostingView.rootView.time.isEmpty)
        XCTAssertGreaterThan(controller.statusItem.length, 0)
    }

    func test_updateTitleRemovesHostingViewWhenLeavingStackedLayout() throws {
        configureStatusBarDefaults()
        Defaults[.eventTimeFormat] = .show_under_title

        let controller = StatusBarItemController()
        defer { NSStatusBar.system.removeStatusItem(controller.statusItem) }
        controller.events = [makeStatusEvent()]
        controller.updateTitle()
        XCTAssertNotNil(controller.stackedHostingView)

        // Switch to an inline layout: the hosting view must be torn down and
        // the status item returned to its automatic (variable) width.
        Defaults[.eventTimeFormat] = .show
        controller.updateTitle()

        XCTAssertNil(controller.stackedHostingView)
        XCTAssertEqual(controller.statusItem.length, NSStatusItem.variableLength)
        let button = try XCTUnwrap(controller.statusItem.button)
        XCTAssertFalse(button.attributedTitle.string.isEmpty)
    }

    func test_stackedViewReusesItsHostAndLeavesClicksOnTheNativeButton() throws {
        let controller = StatusBarItemController()
        defer { NSStatusBar.system.removeStatusItem(controller.statusItem) }
        let button = try XCTUnwrap(controller.statusItem.button)
        let action = button.action

        controller.renderStatusBar(makePresentation(title: "First", time: "in 5m", layout: .stacked))
        let host = try XCTUnwrap(controller.stackedHostingView)
        let subviewCount = button.subviews.count
        XCTAssertNil(host.hitTest(NSPoint(x: 1, y: 1)))
        XCTAssertTrue(button.target === controller)
        XCTAssertEqual(button.action, action)

        controller.renderStatusBar(makePresentation(title: "Second", time: "in 4m", layout: .stacked))
        XCTAssertTrue(controller.stackedHostingView === host)
        XCTAssertEqual(host.rootView.title, "Second")
        XCTAssertEqual(button.subviews.count, subviewCount)
    }

    func test_stackedViewExposesFullTitleAndTimeForAccessibility() throws {
        let controller = StatusBarItemController()
        defer { NSStatusBar.system.removeStatusItem(controller.statusItem) }
        controller.renderStatusBar(makePresentation(
            title: "Short title", time: "in 5m", tooltip: "Full untruncated meeting title", layout: .stacked
        ))
        let button = try XCTUnwrap(controller.statusItem.button)
        XCTAssertEqual(button.accessibilityLabel(), "Full untruncated meeting title")
        XCTAssertEqual(button.accessibilityValue() as? String, "in 5m")

        controller.renderStatusBar(makePresentation(title: "Another", layout: .inline(showTime: false)))
        XCTAssertNotEqual(button.accessibilityLabel(), "Full untruncated meeting title")
        XCTAssertNotEqual(button.accessibilityValue() as? String, "in 5m")
    }

    func test_stackedViewIsRemovedForNonEventStates() throws {
        let controller = StatusBarItemController()
        defer { NSStatusBar.system.removeStatusItem(controller.statusItem) }
        for mode in [StatusBarTitleMode.idle, .noUpcoming, .afterThreshold] {
            controller.renderStatusBar(makePresentation(title: "Meeting", time: "now", layout: .stacked))
            XCTAssertNotNil(controller.stackedHostingView)
            controller.renderStatusBar(makePresentation(mode: mode))
            XCTAssertNil(controller.stackedHostingView)
            XCTAssertEqual(controller.statusItem.length, NSStatusItem.variableLength)
            XCTAssertNotNil(controller.statusItem.button?.image)
        }
    }

    func test_emptyStackedPresentationKeepsTheVisibleFallback() throws {
        let controller = StatusBarItemController()
        defer { NSStatusBar.system.removeStatusItem(controller.statusItem) }
        controller.renderStatusBar(makePresentation(layout: .stacked))
        XCTAssertNil(controller.stackedHostingView)
        XCTAssertNotNil(controller.statusItem.button?.image)
        XCTAssertEqual(controller.statusItem.button?.imagePosition, .imageLeft)
    }

    func test_stackedLayoutFitsTheMenuBarWithTemplateAndServiceIcons() throws {
        let controller = StatusBarItemController()
        defer { NSStatusBar.system.removeStatusItem(controller.statusItem) }
        for icon in [StatusBarIcon.asset(MenuStyleConstants.calendarIconName), .meetingService(.zoom), .meetingService(nil)] {
            for style in [StatusBarTitleStyle.normal, .inactive, .underlined] {
                controller.renderStatusBar(makePresentation(
                    title: "Meeting", time: "in 5m", icon: icon, layout: .stacked, titleStyle: style
                ))
                let host = try XCTUnwrap(controller.stackedHostingView)
                XCTAssertGreaterThan(host.intrinsicContentSize.width, 0)
                XCTAssertLessThanOrEqual(host.intrinsicContentSize.height, NSStatusBar.system.thickness)
                XCTAssertEqual(controller.statusItem.button?.imagePosition, .imageLeft)
            }
        }
    }

    func test_stackedLongTitleKeepsTruncationAndFullAccessibilityLabel() throws {
        configureStatusBarDefaults()
        Defaults[.eventTimeFormat] = .show_under_title
        let controller = StatusBarItemController()
        defer { NSStatusBar.system.removeStatusItem(controller.statusItem) }
        let fullTitle = String(repeating: "Very long meeting title ", count: 5)
        controller.events = [makeStatusEvent(title: fullTitle)]
        controller.updateTitle()
        let host = try XCTUnwrap(controller.stackedHostingView)
        XCTAssertLessThan(host.rootView.title.count, fullTitle.count)
        XCTAssertEqual(controller.statusItem.button?.accessibilityLabel(), fullTitle)
        XCTAssertGreaterThan(controller.statusItem.length, 0)
    }

    func test_actionsUseInjectedAppActionSender() {
        configureStatusBarDefaults()
        let controller = StatusBarItemController()
        defer { NSStatusBar.system.removeStatusItem(controller.statusItem) }
        let event = makeStatusEvent()
        var joinedEventIDs: [String] = []
        var dismissedEventIDs: [String] = []
        var undismissedEventIDs: [String] = []
        var didRefresh = false

        controller.configure(dependencies: StatusBarDependencies(
            send: { action in
                switch action {
                case .joinMeeting(let eventID):
                    joinedEventIDs.append(eventID)
                case .dismissMeeting(let eventID):
                    dismissedEventIDs.append(eventID)
                case .undismissMeeting(let eventID):
                    undismissedEventIDs.append(eventID)
                case .refreshCalendars:
                    didRefresh = true
                default:
                    break
                }
            }
        ))
        controller.events = [event]

        let actions = controller.popover.model.actions
        controller.joinNextMeeting()
        actions.join(event)
        actions.dismiss(event)
        actions.undismiss(event)
        actions.refresh()

        XCTAssertEqual(joinedEventIDs, [event.id, event.id])
        XCTAssertEqual(dismissedEventIDs, [event.id])
        XCTAssertEqual(undismissedEventIDs, [event.id])
        XCTAssertTrue(didRefresh)
    }

    func test_copyMeetingLinkPutsTheFullUrlOnThePasteboard() throws {
        configureStatusBarDefaults()
        let controller = StatusBarItemController()
        defer { NSStatusBar.system.removeStatusItem(controller.statusItem) }
        let event = makeStatusEvent()
        let link = try XCTUnwrap(event.meetingLink)

        controller.popover.model.actions.copyLink(event)

        XCTAssertEqual(NSPasteboard.general.string(forType: .string), link.url.absoluteString)
    }

    func test_openMenuTogglesThePopover() throws {
        configureStatusBarDefaults()
        let controller = StatusBarItemController()
        defer {
            controller.popover.close()
            NSStatusBar.system.removeStatusItem(controller.statusItem)
        }
        controller.configure(dependencies: StatusBarDependencies(
            appState: {
                var state = AppState()
                state.selectedCalendarIDs = [Self.calendarID]
                return state
            }
        ))
        controller.events = [makeStatusEvent()]

        controller.openMenu()
        XCTAssertTrue(controller.popover.isOpen)
        XCTAssertEqual(controller.popover.model.presentation.events.count, 1)

        controller.openMenu()
        XCTAssertFalse(controller.popover.isOpen)
    }

    func test_popoverCloseActionsCloseBeforeHandingOff() throws {
        configureStatusBarDefaults()
        let controller = StatusBarItemController()
        defer {
            controller.popover.close()
            NSStatusBar.system.removeStatusItem(controller.statusItem)
        }
        var wasOpenWhenPreferencesOpened = true
        controller.configure(dependencies: StatusBarDependencies(
            openPreferences: { wasOpenWhenPreferencesOpened = controller.popover.isOpen }
        ))
        controller.openMenu()

        controller.popover.model.actions.openPreferences()

        XCTAssertFalse(wasOpenWhenPreferencesOpened)
    }

    func test_windowActionsUseInjectedClosures() {
        let controller = StatusBarItemController()
        defer { NSStatusBar.system.removeStatusItem(controller.statusItem) }
        var didOpenPreferences = false
        var didQuit = false

        controller.configure(dependencies: StatusBarDependencies(
            openPreferences: { didOpenPreferences = true },
            quit: { didQuit = true }
        ))

        let actions = controller.popover.model.actions
        actions.openPreferences()
        actions.quit()

        XCTAssertTrue(didOpenPreferences)
        XCTAssertTrue(didQuit)
    }

    private func configureStatusBarDefaults() {
        Defaults[.selectedCalendarIDs] = [Self.calendarID]
        Defaults[.showEventsForPeriod] = .today_n_tomorrow
        Defaults[.eventTitleFormat] = .show
        Defaults[.eventTimeFormat] = .show
        Defaults[.eventTitleIconFormat] = .none
        Defaults[.statusbarEventTitleLength] = statusbarEventTitleLengthLimits.max
        Defaults[.personalEventsAppereance] = .show_active
        Defaults[.nonAllDayEvents] = .show
    }

    func test_renderStatusBarPreservesProviderIconSize() throws {
        let controller = StatusBarItemController()
        defer { NSStatusBar.system.removeStatusItem(controller.statusItem) }

        for provider in MeetingProvider.all {
            guard let service = MeetingServices(rawValue: provider.id) else { continue }

            controller.renderStatusBar(makePresentation(icon: .meetingService(service)))

            let button = try XCTUnwrap(controller.statusItem.button)
            let expected = NSSize(width: provider.iconWidth, height: provider.iconHeight)
            XCTAssertEqual(button.image?.size, expected)
            XCTAssertEqual(getIconForMeetingService(service).size, expected)
        }
    }

    private func makePresentation(
        mode: StatusBarTitleMode = .nextEvent,
        title: String = "",
        time: String = "",
        tooltip: String? = nil,
        icon: StatusBarIcon = .none,
        layout: StatusBarTitleLayout = .none,
        titleStyle: StatusBarTitleStyle = .normal
    ) -> StatusBarPresentation {
        StatusBarPresentation(
            mode: mode,
            title: title,
            time: time,
            tooltip: tooltip,
            icon: icon,
            layout: layout,
            titleStyle: titleStyle
        )
    }

    private func makeStatusEvent(
        title: String = "Weekly sync",
        url: URL? = URL(string: "https://zoom.us/j/5551112222")!,
        participationStatus: MBEventAttendeeStatus = .accepted
    ) -> MBEvent {
        let now = Date()
        let calendar = MBCalendar(
            title: "Status Bar Test Calendar",
            id: Self.calendarID,
            source: nil,
            email: nil,
            color: .black
        )
        var event = MBEvent(
            id: UUID().uuidString,
            lastModifiedDate: now,
            title: title,
            status: .confirmed,
            notes: nil,
            location: nil,
            url: url,
            organizer: nil,
            startDate: now.addingTimeInterval(-60),
            endDate: now.addingTimeInterval(3600),
            isAllDay: false,
            recurrent: false,
            calendar: calendar
        )
        event.participationStatus = participationStatus
        return event
    }
}
