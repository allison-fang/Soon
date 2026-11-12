//
//  StatusBarItemController.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 12.06.2020.
//  Copyright © 2020 Andrii Leitsius. All rights reserved.
//

import Cocoa
import Combine
import Defaults
import KeyboardShortcuts
import SwiftUI

enum MenuStyleConstants {
    static let defaultFontSize: CGFloat = 13
    static let appIconName = "AppIcon"
    static let calendarCheckmarkIconName = "iconCalendarCheckmark"
    static let calendarIconName = "iconCalendar"
    static let iconSize: NSSize = .init(width: 16, height: 16)

    /// Loads a named asset; if the asset is missing or has been renamed,
    /// falls back to the bundle's runtime app icon and finally to a 1x1
    /// placeholder so the menu bar never crashes on a misconfigured Defaults
    /// value or a renamed asset.
    static func iconNamed(_ name: String) -> NSImage {
        if let image = NSImage(named: name) {
            return image
        }
        if let appIcon = NSImage(named: NSImage.applicationIconName) {
            return appIcon
        }
        return NSImage(size: NSSize(width: 1, height: 1))
    }
}

struct StatusBarDependencies {
    var states: AnyPublisher<AppState, Never> = Empty().eraseToAnyPublisher()
    var appState: @MainActor () -> AppState = { AppState() }
    var events: @MainActor () -> [MBEvent] = { [] }
    var send: @MainActor (AppAction) -> Void = { _ in }
    var openPreferences: @MainActor () -> Void = {}
    var quit: @MainActor () -> Void = {}
}

/// creates the item in the system status bar, presents the timeline popover and controls the whole lifecycle.
@MainActor
final class StatusBarItemController {
    var statusItem: NSStatusItem!
    let popover = StatusBarPopoverController()

    /// Current event list, driven by the AppModel state.
    /// A non-nil `_eventsOverride` takes precedence (used by tests to inject
    /// events without wiring up the full app model chain).
    private var _eventsOverride: [MBEvent]?
    var events: [MBEvent] {
        get { _eventsOverride ?? dependencies.events() }
        set { _eventsOverride = newValue }
    }

    /// Hosting view used to render the stacked (time-under-title) layout. Kept
    /// around so successive updates reuse the same view (and its Auto Layout
    /// constraints) instead of re-adding a subview on every refresh.
    var stackedHostingView: NSHostingView<StatusBarStackedTitleView>?

    private var dependencies = StatusBarDependencies()

    private var cancellables = Set<AnyCancellable>()
    private var stateCancellable: AnyCancellable?

    init() {
        statusItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.variableLength
        )

        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusMenuBarAction)
        // Mouse down only: the popover toggles, so also acting on mouse up
        // would close it again within the same click.
        statusItem.button?.sendAction(on: [
            NSEvent.EventTypeMask.rightMouseDown, NSEvent.EventTypeMask.leftMouseDown
        ])

        // Temporary icon before app delegate setup
        statusItem.button?.image = MenuStyleConstants.iconNamed(MenuStyleConstants.appIconName)
        statusItem.button?.image?.size = MenuStyleConstants.iconSize
        statusItem.button?.imagePosition = .imageLeft

        popover.model.actions = popoverActions()
        popover.onClockTick = { [weak self] in self?.updateMenu() }

        setupDefaultsObservers()
        setupKeyboardShortcuts()
    }

    private func setupDefaultsObservers() {
        // For all these keys, just redraw:
        Defaults.publisher(
            keys: .statusbarEventTitleLength, .eventTimeFormat,
            .eventTitleIconFormat, .showEventMaxTimeUntilEventThreshold,
            .showEventMaxTimeUntilEventEnabled, .showEventDetails,
            .shortenEventTitle, .menuEventTitleLength,
            .showEventEndTime, .showMeetingServiceIcon,
            .showEventCalendarColor,
            .timeFormat, .bookmarks, .timelineDensity,
            .pastEventsAppereance, .declinedEventsAppereance,
            .showTimelineInMenu, .eventTitleFormat,
            options: []
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
            self?.updateTitle()
            self?.updateMenu()
        }
        .store(in: &cancellables)
    }

    private func setupKeyboardShortcuts() {
        KeyboardShortcuts.onKeyUp(for: .createMeetingShortcut, action: createMeeting)

        KeyboardShortcuts.onKeyUp(for: .joinEventShortcut) {
            Task { @MainActor in self.joinNextMeeting() }
        }

        KeyboardShortcuts.onKeyUp(for: .openMenuShortcut) {
            Task { @MainActor in self.openMenu() }
        }

        KeyboardShortcuts.onKeyUp(for: .openClipboardShortcut, action: openLinkFromClipboard)

        KeyboardShortcuts.onKeyUp(for: .toggleMeetingTitleVisibilityShortcut) {
            Task { @MainActor in self.dependencies.send(.toggleMeetingTitleVisibility) }
        }
    }

    @objc
    func statusMenuBarAction(sender _: NSStatusItem) {
        let event = NSApp.currentEvent

        if event?.type == .rightMouseUp {
            // Right button click
            joinNextMeeting()
        } else if event == nil || event?.type == .leftMouseDown {
            openMenu()
        }
    }

    func openMenu() {
        guard !popover.isOpen else {
            popover.close()
            return
        }
        guard let button = statusItem.button else { return }

        let state = menuState()
        popover.timeFormat = state.timeFormat
        popover.isFantasticalInstalled = checkIsFantasticalInstalled()
        popover.update(StatusBarPopoverPresenter.presentation(for: state, now: Date()))
        popover.open(relativeTo: button)
    }

    func configure(dependencies: StatusBarDependencies) {
        self.dependencies = dependencies
        stateCancellable = dependencies.states
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateTitle()
                self?.updateMenu()
            }
    }

    func updateTitle() {
        let now = Date()
        let presentation = StatusBarPresenter.presentation(
            nextEvent: events.nextEvent(settings: .current, now: now).map(StatusBarEventPresentationInput.init),
            settings: .current,
            now: now,
            calendar: statusBarCalendar()
        )

        renderStatusBar(presentation)
    }

    func renderStatusBar(_ presentation: StatusBarPresentation) {
        guard let button = statusItem.button else { return }

        button.image = nil
        button.title = ""
        button.attributedTitle = NSAttributedString(string: "")
        button.toolTip = nil
        button.setAccessibilityLabel(nil)
        button.setAccessibilityValue(nil)
        button.alignment = .center
        button.cell?.lineBreakMode = .byTruncatingTail

        // The stacked (time-under-title) layout is drawn by a SwiftUI hosting
        // view for crisp two-line rendering; every other layout uses the
        // button's own image + (attributed) title.
        if presentation.mode == .nextEvent, presentation.layout == .stacked,
           !presentation.title.isEmpty || !presentation.time.isEmpty {
            renderStackedTitle(presentation, button: button)
            return
        }

        removeStackedHostingView()

        switch presentation.icon {
        case .asset(let name):
            button.image = MenuStyleConstants.iconNamed(name)
            button.image?.size = MenuStyleConstants.iconSize
        case .meetingService(let service):
            button.image = getIconForMeetingService(service)
        case .none:
            break
        }
        button.imagePosition = button.image?.name() == "no_online_session" ? .noImage : .imageLeft

        if presentation.mode == .nextEvent {
            button.attributedTitle = StatusBarTitleRenderer.attributedTitle(for: presentation)
            button.toolTip = presentation.tooltip
        }

        ensureStatusBarButtonIsVisible(button)
    }

    /// Renders the stacked layout into an `NSHostingView` centered in the
    /// status button. Because the hosting view carries the whole visual (icon
    /// + both text lines), the button's own image/title are left empty and the
    /// status item is sized from the hosting view's intrinsic width.
    private func renderStackedTitle(_ presentation: StatusBarPresentation, button: NSStatusBarButton) {
        let rootView = StatusBarStackedTitleView(
            icon: stackedIcon(for: presentation.icon),
            title: presentation.title,
            time: presentation.time,
            style: presentation.titleStyle
        )

        let hostingView: NSHostingView<StatusBarStackedTitleView>
        if let existing = stackedHostingView {
            hostingView = existing
            hostingView.rootView = rootView
            hostingView.isHidden = false
        } else {
            hostingView = StatusBarStackedHostingView(rootView: rootView)
            hostingView.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(hostingView)
            NSLayoutConstraint.activate([
                hostingView.centerXAnchor.constraint(equalTo: button.centerXAnchor),
                hostingView.centerYAnchor.constraint(equalTo: button.centerYAnchor)
            ])
            stackedHostingView = hostingView
        }

        // Keep an empty (zero-size) image rather than clearing it to nil. A
        // status button that hosts a custom subview but has a nil image does
        // not pick up the menu bar's inactive-display dimming, so its content
        // stays bright on secondary monitors; an empty image keeps the button
        // in its normal image-drawing mode (matching how SpotMenu configures
        // its hosting-view status item) so the whole item dims like native ones.
        button.image = NSImage()
        button.imagePosition = .imageLeft
        button.toolTip = presentation.tooltip
        button.setAccessibilityLabel(presentation.tooltip ?? presentation.title)
        button.setAccessibilityValue(presentation.time)

        hostingView.layoutSubtreeIfNeeded()
        statusItem.length = hostingView.intrinsicContentSize.width
    }

    /// Resolves the icon shown alongside the stacked title. Returns `nil` for
    /// the "no icon" case and for the hidden `no_online_session` sentinel, so
    /// the hosting view simply omits the image.
    private func stackedIcon(for icon: StatusBarIcon) -> NSImage? {
        let image: NSImage?
        switch icon {
        case .asset(let name):
            let asset = MenuStyleConstants.iconNamed(name)
            asset.size = MenuStyleConstants.iconSize
            image = asset
        case .meetingService(let service):
            image = getIconForMeetingService(service)
        case .none:
            image = nil
        }
        return image?.name() == "no_online_session" ? nil : image
    }

    private func removeStackedHostingView() {
        guard stackedHostingView != nil else { return }
        stackedHostingView?.removeFromSuperview()
        stackedHostingView = nil
        statusItem.length = NSStatusItem.variableLength
    }

    private func ensureStatusBarButtonIsVisible(_ button: NSStatusBarButton) {
        // A set-but-suppressed image (imagePosition == .noImage, e.g. the
        // "no_online_session" sentinel) is not visible, so treat it the same as a
        // missing image — otherwise the status item can render completely blank.
        guard button.image == nil || button.imagePosition == .noImage,
              button.title.isEmpty,
              button.attributedTitle.string.isEmpty
        else { return }

        button.image = MenuStyleConstants.iconNamed(MenuStyleConstants.appIconName)
        button.image?.size = MenuStyleConstants.iconSize
        button.imagePosition = .imageLeft
    }

    /*
     * -----------------------
     * MARK: - POPOVER
     * ------------------------
     */

    func updateMenu() {
        guard popover.isOpen else { return }
        popover.update(popoverPresentation())
    }

    func popoverPresentation(now: Date = Date()) -> StatusBarPopoverPresentation {
        StatusBarPopoverPresenter.presentation(for: menuState(now: now), now: now)
    }

    private func menuState(now: Date = Date()) -> StatusBarMenuState {
        var appState = dependencies.appState()
        appState.events = events
        return StatusBarMenuState.make(from: appState, now: now)
    }

    private func popoverActions() -> StatusBarPopoverActions {
        StatusBarPopoverActions(
            join: { [weak self] event in
                self?.popover.close()
                self?.dependencies.send(.joinMeeting(eventID: event.id))
            },
            joinCandidate: { [weak self] candidate in
                self?.popover.close()
                MeetingOpener.open(
                    meetingLink: MeetingLink(service: candidate.service, url: candidate.url))
            },
            joinBookmark: { [weak self] bookmark in
                self?.popover.close()
                MeetingOpener.open(
                    meetingLink: MeetingLink(
                        service: MeetingServices(rawValue: bookmark.service),
                        url: bookmark.url
                    ))
            },
            copyLink: { [weak self] event in
                self?.popover.close()
                self?.copyMeetingLink(of: event)
            },
            dismiss: { [weak self] event in self?.dismiss(event: event) },
            undismiss: { [weak self] event in
                self?.dependencies.send(.undismissMeeting(eventID: event.id))
            },
            openInCalendar: { [weak self] url in
                self?.popover.close()
                url.openInDefaultBrowser()
            },
            openInFantastical: { [weak self] event in
                self?.popover.close()
                openInFantastical(startDate: event.startDate, title: event.title)
            },
            performNotice: { [weak self] action in self?.perform(action) },
            refresh: { [weak self] in self?.dependencies.send(.refreshCalendars) },
            openPreferences: { [weak self] in
                self?.popover.close()
                self?.dependencies.openPreferences()
            },
            quit: { [weak self] in
                self?.popover.close()
                self?.dependencies.quit()
            }
        )
    }

    /*
     * -----------------------
     * MARK: - Actions
     * ------------------------
     */

    @objc
    func joinNextMeeting() {
        if let nextEvent = events.nextEvent(settings: .current, now: Date()) {
            dependencies.send(.joinMeeting(eventID: nextEvent.id))
        } else {
            AppMessageCenter.shared.post(.nextMeetingMissing)
        }
    }

    func dismiss(event: MBEvent) {
        dependencies.send(.dismissMeeting(eventID: event.id))
    }

    func copyMeetingLink(of event: MBEvent) {
        if let meetingLink = event.meetingLink {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(meetingLink.url.absoluteString, forType: .string)
        } else {
            AppMessageCenter.shared.post(.meetingLinkMissing(title: event.title))
        }
    }

    private func perform(_ action: StatusBarNoticeAction) {
        switch action {
        case .reconnect:
            popover.close()
            dependencies.send(.changeProvider(dependencies.appState().activeProvider, signOut: true))
        case .grantPermission:
            popover.close()
            NSWorkspace.shared.open(Links.calendarPreferences)
        case .refresh:
            dependencies.send(.refreshCalendars)
        case .openPreferences:
            popover.close()
            dependencies.openPreferences()
        }
    }
}

@MainActor
enum StatusBarTitleRenderer {
    static func attributedTitle(for presentation: StatusBarPresentation) -> NSAttributedString {
        switch presentation.layout {
        case .none:
            return NSAttributedString(string: "")
        case .inline(let showTime):
            var eventTitle = presentation.title
            if showTime {
                eventTitle += " " + presentation.time
            }
            return NSAttributedString(
                string: eventTitle,
                attributes: titleAttributes(
                    style: presentation.titleStyle,
                    font: NSFont.systemFont(ofSize: MenuStyleConstants.defaultFontSize)
                )
            )
        case .stacked:
            // The stacked layout is rendered by `StatusBarStackedTitleView`
            // through an NSHostingView (see `StatusBarItemController`), so the
            // attributed title is intentionally empty here.
            return NSAttributedString(string: "")
        }
    }

    private static func titleAttributes(
        style: StatusBarTitleStyle,
        font: NSFont
    ) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font
        ]
        switch style {
        case .normal:
            break
        case .inactive:
            attributes[.foregroundColor] = NSColor.disabledControlTextColor
        case .underlined:
            attributes[.underlineStyle] =
                NSUnderlineStyle.single.rawValue
                | NSUnderlineStyle.patternDot.rawValue
                | NSUnderlineStyle.byWord.rawValue
        }
        return attributes
    }
}

private func statusBarCalendar() -> Calendar {
    var calendar = Calendar.current
    calendar.locale = I18N.instance.locale
    return calendar
}

enum NextEventState {
    case none
    case afterThreshold(MBEvent)
    case nextEvent(MBEvent)
}
