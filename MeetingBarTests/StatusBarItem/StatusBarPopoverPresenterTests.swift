//
//  StatusBarPopoverPresenterTests.swift
//  MeetingBar
//

import Defaults
import XCTest

@testable import MeetingBar

@MainActor
final class StatusBarPopoverPresenterTests: BaseTestCase {
    private let now = Calendar.current.date(
        bySettingHour: 12, minute: 0, second: 0, of: Date()
    )!

    private var calendar: MBCalendar {
        MBCalendar(title: "Work", id: "work", source: nil, email: nil, color: .systemBlue)
    }

    private func meeting(
        id: String = "E",
        startingIn start: TimeInterval = 600,
        duration: TimeInterval = 1800,
        status: MBEventStatus = .confirmed,
        response: MBEventAttendeeStatus? = .accepted,
        guests: [MBEventAttendee] = [],
        location: String? = nil,
        notes: String? = nil,
        isAllDay: Bool = false
    ) -> MBEvent {
        var attendees = guests
        if let response {
            attendees.insert(
                MBEventAttendee(email: "me@acme.co", status: response, isCurrentUser: true),
                at: 0
            )
        }
        let startDate = now.addingTimeInterval(start)
        return MBEvent(
            id: id,
            lastModifiedDate: nil,
            title: "Event \(id)",
            status: status,
            notes: notes,
            location: location,
            url: nil,
            organizer: nil,
            attendees: attendees,
            startDate: startDate,
            endDate: startDate.addingTimeInterval(duration),
            isAllDay: isAllDay,
            recurrent: false,
            calendar: calendar
        )
    }

    private func state(
        _ events: [MBEvent],
        health: ProviderHealth = ProviderHealth(),
        selectedCalendars: [String] = ["work"],
        settings: AppSettings = .current
    ) -> StatusBarMenuState {
        var appState = AppState()
        appState.events = events
        appState.selectedCalendarIDs = selectedCalendars
        appState.providerHealth = health
        return StatusBarMenuState.make(from: appState, settings: settings, now: now)
    }

    private func presentation(
        _ events: [MBEvent],
        health: ProviderHealth = ProviderHealth(),
        selectedCalendars: [String] = ["work"],
        settings: AppSettings = .current
    ) -> StatusBarPopoverPresentation {
        StatusBarPopoverPresenter.presentation(
            for: state(events, health: health, selectedCalendars: selectedCalendars, settings: settings),
            now: now
        )
    }

    private func presented(_ event: MBEvent) throws -> TimelineEventPresentation {
        try XCTUnwrap(presentation([event]).events.first)
    }

    // MARK: Timeline

    func testAllDayEventsSitAboveTheGrid() throws {
        let allDay = meeting(id: "ALL", startingIn: -3600 * 12, duration: 86_400, isAllDay: true)
        let day = try XCTUnwrap(presentation([allDay, meeting(id: "TIMED")]).days.first)

        XCTAssertEqual(day.allDayEvents.map(\.id), ["ALL"])
        XCTAssertEqual(day.timedEvents.map(\.id), ["TIMED"])
    }

    func testNowIndicatorSitsInsideTheGrid() throws {
        let day = try XCTUnwrap(presentation([meeting()]).days.first)
        let indicator = try XCTUnwrap(day.now)

        XCTAssertGreaterThanOrEqual(indicator.offset, 0)
        XCTAssertLessThanOrEqual(indicator.offset, day.gridHeight)
    }

    private func hoursToday() throws -> Double {
        try XCTUnwrap(Calendar.current.dateInterval(of: .day, for: now)).duration / 3600
    }

    func testOneEventStillShowsTheWholeDay() throws {
        let result = presentation([meeting()])
        let day = try XCTUnwrap(result.days.first)

        XCTAssertEqual(day.gridHeight, try hoursToday() * result.zoom.hourHeight)
        XCTAssertEqual(day.hourLabels.first?.offset, 0)
        XCTAssertEqual(day.hourLabels.last?.offset, day.gridHeight)
    }

    func testZoomSetsTheHoursOnScreen() throws {
        var settings = AppSettings.current
        settings.menu.timelineZoom = .fullDay
        let fullDay = presentation([meeting()], settings: settings)
        settings.menu.timelineZoom = .medium
        let medium = presentation([meeting()], settings: settings)

        XCTAssertEqual(fullDay.zoom, .fullDay)
        XCTAssertEqual(try XCTUnwrap(fullDay.days.first).gridHeight, try hoursToday() * 20)
        XCTAssertEqual(try XCTUnwrap(medium.days.first).gridHeight, try hoursToday() * 56)
    }

    func testWithoutAZoomDensityPicksTheScale() throws {
        var settings = AppSettings.current
        settings.menu.timelineZoom = nil
        settings.menu.timelineDensity = .compact
        let compact = presentation([meeting()], settings: settings)
        settings.menu.timelineDensity = .comfortable
        let comfortable = presentation([meeting()], settings: settings)

        XCTAssertEqual(compact.density, .compact)
        XCTAssertEqual(compact.zoom, .close)
        XCTAssertEqual(comfortable.density, .comfortable)
        XCTAssertEqual(comfortable.zoom, .closest)
    }

    func testZoomKeepsDensitysOneLineMinimum() throws {
        var settings = AppSettings.current
        settings.menu.timelineDensity = .compact
        settings.menu.timelineZoom = .fullDay
        let day = try XCTUnwrap(presentation([meeting(duration: 900)], settings: settings).days.first)

        XCTAssertEqual(day.timedEvents.first?.placement.height, TimelineScale.compact.minimumEventHeight)
    }

    func testDensityDefaultsToComfortable() {
        XCTAssertEqual(Defaults[.timelineDensity], .comfortable)
    }

    func testZoomIsUnsetUntilSomeoneZooms() {
        XCTAssertNil(Defaults[.timelineZoom])
        XCTAssertNil(AppSettings.empty.menu.timelineZoom)
    }

    func testSavedZoomReachesTheSettingsSnapshot() {
        Defaults[.timelineZoom] = .wide

        XCTAssertEqual(AppSettings.current.menu.timelineZoom, .wide)
        XCTAssertEqual(presentation([meeting()]).zoom, .wide)
    }

    func testEmptyDayExplainsItself() throws {
        let day = try XCTUnwrap(presentation([]).days.first)

        XCTAssertTrue(day.timedEvents.isEmpty)
        XCTAssertEqual(day.emptyMessage, "🎉 \("status_bar_control_no_upcoming".loco())")
    }

    func testFullyEmptyTodayShowsOnlyItsMessage() throws {
        let day = try XCTUnwrap(presentation([]).days.first)

        XCTAssertEqual(day.gridHeight, 0)
        XCTAssertNil(day.now)
        XCTAssertNotNil(day.emptyMessage)
    }

    func testTodayWithEveryEventHiddenShowsOnlyItsMessage() throws {
        var settings = AppSettings.current
        settings.events.pastEventsAppearance = .hide
        let day = try XCTUnwrap(presentation([meeting(startingIn: -7200)], settings: settings).days.first)

        XCTAssertEqual(day.gridHeight, 0)
        XCTAssertNotNil(day.emptyMessage)
    }

    func testTodayWithOnlyAllDayEventsStillShowsTheDayAndNow() throws {
        let allDay = meeting(id: "ALL", startingIn: -3600 * 12, duration: 86_400, isAllDay: true)
        let result = presentation([allDay])
        let day = try XCTUnwrap(result.days.first)

        XCTAssertEqual(day.gridHeight, try hoursToday() * result.zoom.hourHeight)
        XCTAssertNotNil(day.now)
        XCTAssertNil(day.emptyMessage)
    }

    func testTomorrowWithoutTimedEventsKeepsItsMessageInsteadOfAGrid() throws {
        var settings = AppSettings.current
        settings.events.showEventsForPeriod = .today_n_tomorrow
        let tomorrow = try XCTUnwrap(presentation([meeting()], settings: settings).days.last)

        XCTAssertEqual(tomorrow.gridHeight, 0)
        XCTAssertNotNil(tomorrow.emptyMessage)
    }

    func testTomorrowWithEventsShowsItsWholeDay() throws {
        var settings = AppSettings.current
        settings.events.showEventsForPeriod = .today_n_tomorrow
        let result = presentation([meeting(id: "TMRW", startingIn: 86_400)], settings: settings)
        let tomorrow = try XCTUnwrap(result.days.last)
        let start = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)))
        let hours = try XCTUnwrap(Calendar.current.dateInterval(of: .day, for: start)).duration / 3600

        XCTAssertEqual(tomorrow.gridHeight, hours * result.zoom.hourHeight)
        XCTAssertNil(tomorrow.now)
    }

    func testTomorrowFollowsTodayOnlyWhenEnabled() {
        var settings = AppSettings.current
        settings.events.showEventsForPeriod = .today
        XCTAssertEqual(presentation([meeting()], settings: settings).days.count, 1)

        settings.events.showEventsForPeriod = .today_n_tomorrow
        let days = presentation(
            [meeting(), meeting(id: "TMRW", startingIn: 86_400)],
            settings: settings
        ).days
        XCTAssertEqual(days.map(\.title), [
            "status_bar_section_today".loco(),
            "status_bar_section_tomorrow".loco()
        ])
        XCTAssertEqual(days.last?.timedEvents.map(\.id), ["TMRW"])
    }

    func testHideSettingsStillRemoveEvents() {
        var settings = AppSettings.current
        settings.events.declinedEventsAppearance = .hide
        settings.events.pastEventsAppearance = .hide
        settings.events.personalEventsAppearance = .hide

        let events = presentation(
            [
                meeting(id: "DECLINED", response: .declined),
                meeting(id: "PAST", startingIn: -7200),
                meeting(id: "PERSONAL", response: nil),
                meeting(id: "KEPT")
            ],
            settings: settings
        ).events

        XCTAssertEqual(events.map(\.id), ["KEPT"])
    }

    // MARK: Response and phase

    func testResponsesMapToGoogleCalendarCues() throws {
        XCTAssertEqual(try presented(meeting(response: .accepted)).response, .accepted)
        XCTAssertEqual(try presented(meeting(response: nil)).response, .accepted)
        XCTAssertEqual(try presented(meeting(response: .pending)).response, .pending)
        XCTAssertEqual(try presented(meeting(response: .tentative)).response, .tentative)
        XCTAssertEqual(try presented(meeting(response: .declined)).response, .declined)
    }

    func testCanceledEventsLookDeclinedWhateverTheResponse() throws {
        let event = try presented(meeting(status: .canceled, response: .accepted))

        XCTAssertEqual(event.response, .declined)
        XCTAssertTrue(event.isCanceled)
    }

    func testCanceledMeetingsWithALinkCanStillBeJoined() throws {
        let event = try presented(meeting(
            status: .canceled,
            location: "https://zoom.us/j/5551112222"
        ))

        XCTAssertTrue(event.canJoin)
        XCTAssertNotNil(event.linkPreview)
    }

    func testDeclinedMeetingsCanStillBeJoined() throws {
        let event = try presented(meeting(
            response: .declined,
            location: "https://zoom.us/j/5551112222"
        ))

        XCTAssertTrue(event.canJoin)
    }

    func testDeclinedAndCanceledEventsStayVisible() {
        let events = presentation([
            meeting(id: "DECLINED", response: .declined),
            meeting(id: "CANCELED", status: .canceled)
        ]).events

        XCTAssertEqual(Set(events.map(\.id)), ["DECLINED", "CANCELED"])
    }

    func testPhaseFollowsTheClock() throws {
        XCTAssertEqual(try presented(meeting(startingIn: -7200)).phase, .past)
        XCTAssertEqual(try presented(meeting(startingIn: -600)).phase, .current)
        XCTAssertEqual(try presented(meeting(startingIn: 600)).phase, .upcoming)
    }

    func testNextEventMatchesTheStatusBarSelection() {
        let events = presentation([
            meeting(id: "FIRST", startingIn: 600),
            meeting(id: "SECOND", startingIn: 7200)
        ]).events

        XCTAssertEqual(events.filter(\.isNext).map(\.id), ["FIRST"])
        XCTAssertNotNil(events.first { $0.id == "FIRST" }?.countdown)
        XCTAssertNil(events.first { $0.id == "SECOND" }?.countdown)
    }

    func testDismissedEventStaysOnTheTimelineButIsNotNext() throws {
        var settings = AppSettings.current
        let event = meeting(id: "SKIP")
        settings.events.dismissedEvents = [
            ProcessedEvent(id: event.id, lastModifiedDate: nil, eventEndDate: event.endDate)
        ]

        let presented = try XCTUnwrap(presentation([event], settings: settings).events.first)

        XCTAssertTrue(presented.isDismissed)
        XCTAssertFalse(presented.isNext)
    }

    // MARK: Card content

    func testLinkPreviewDropsTheQueryWithItsPassword() throws {
        let event = try presented(meeting(location: "https://zoom.us/j/5551112222?pwd=secret"))

        XCTAssertEqual(event.linkPreview, "zoom.us/j/5551112222")
    }

    func testLinkPreviewShowsOnlyTheHostForLongPaths() throws {
        let event = try presented(meeting(
            location: "https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc/0"
        ))

        XCTAssertEqual(event.linkPreview, "teams.microsoft.com")
    }

    func testEventWithoutLinkCannotJoin() throws {
        let event = try presented(meeting())

        XCTAssertNil(event.linkPreview)
        XCTAssertFalse(event.canJoin)
    }

    func testDescriptionPreviewIsTheFirstReadableLine() throws {
        let event = try presented(meeting(
            notes: "\n  https://acme.co/doc\nAgenda: pricing review\nSecond line"
        ))

        XCTAssertEqual(event.descriptionPreview, "Agenda: pricing review")
    }

    func testGuestsLeaveOutRoomsAndListAcceptedFirst() throws {
        let event = try presented(meeting(guests: [
            MBEventAttendee(email: "no@acme.co", name: "Nora", status: .declined),
            MBEventAttendee(email: "room@resource.calendar.google.com", name: "Room", status: .accepted),
            MBEventAttendee(email: "yes@acme.co", name: "Yuki", status: .accepted)
        ]))

        XCTAssertEqual(event.guests.filter { !$0.isCurrentUser }.map(\.name), ["Yuki", "Nora"])
    }

    func testGuestInitialUsesTheFirstLetter() {
        XCTAssertEqual(StatusBarPopoverPresenter.initial(for: "priya natarajan"), "P")
        XCTAssertEqual(StatusBarPopoverPresenter.initial(for: "(Ana) Ruiz"), "A")
        XCTAssertEqual(StatusBarPopoverPresenter.initial(for: "…"), "?")
    }

    // MARK: Failure states

    func testHealthyProviderHasNoNotice() {
        XCTAssertNil(presentation([meeting()], health: ProviderHealth(lastSuccessfulRefresh: now)).notice)
    }

    func testAuthFailureOffersReconnectAlongsideKnownEvents() throws {
        var health = ProviderHealth(lastSuccessfulRefresh: now)
        health.authRequired = true

        let popover = presentation([meeting()], health: health)

        XCTAssertEqual(popover.notice?.action, .reconnect)
        XCTAssertEqual(popover.events.count, 1)
    }

    func testOneAccountLosingAccessOffersToReconnectItAlongsideOtherMeetings() {
        let health = ProviderHealth(lastSuccessfulRefresh: now).applyingAccounts([
            ProviderAccountHealth(id: "work@example.com", email: "work@example.com", status: .authRequired)
        ])

        let popover = presentation([meeting()], health: health)

        XCTAssertEqual(popover.notice?.action, .reconnectAccount("work@example.com"))
        XCTAssertEqual(popover.notice?.title, "work@example.com needs to be reconnected")
        XCTAssertEqual(popover.events.count, 1)
    }

    func testPermissionLossOffersSettings() {
        var health = ProviderHealth()
        health.calendarPermissionRequired = true

        XCTAssertEqual(presentation([], health: health).notice?.action, .grantPermission)
    }

    func testStaleDataWarnsWithoutHidingTheNextMeeting() throws {
        var health = ProviderHealth(lastSuccessfulRefresh: now)
        health.isStale = true

        let popover = presentation([meeting()], health: health)

        XCTAssertEqual(popover.notice?.title, "status_bar_control_stale".loco())
        XCTAssertEqual(popover.notice?.action, .refresh)
        XCTAssertEqual(popover.events.filter(\.isNext).count, 1)
    }

    func testNoCalendarsSelectedPointsToPreferencesInsteadOfAnEmptyDay() {
        let popover = presentation([], selectedCalendars: [])

        XCTAssertEqual(popover.notice?.action, .openPreferences)
        XCTAssertTrue(popover.days.isEmpty)
    }

    func testFailureWithoutEventsNeverClaimsTheDayIsEmpty() {
        var health = ProviderHealth()
        health.calendarPermissionRequired = true
        XCTAssertTrue(presentation([], health: health).days.isEmpty)

        var failed = ProviderHealth()
        failed.lastErrorDescription = "Network"
        XCTAssertTrue(presentation([], health: failed).days.isEmpty)
    }

    func testEmptyCalendarIsNotReportedAsAFailure() {
        XCTAssertNil(presentation([], health: ProviderHealth(lastSuccessfulRefresh: now)).notice)
    }

    // MARK: Footer

    func testLastUpdatedComesFromTheLastSuccessfulRefresh() {
        XCTAssertNil(presentation([]).lastUpdatedText)
        XCTAssertNotNil(presentation([], health: ProviderHealth(lastSuccessfulRefresh: now)).lastUpdatedText)
    }

    func testLastUpdatedUsesTwelveHourClockEvenWithTwentyFourHourSetting() throws {
        Defaults[.timeFormat] = .military
        let refresh = try XCTUnwrap(Calendar.current.date(bySettingHour: 23, minute: 7, second: 0, of: now))
        let text = try XCTUnwrap(presentation([], health: ProviderHealth(lastSuccessfulRefresh: refresh)).lastUpdatedText)
        XCTAssertTrue(text.contains("11:07"), text)
        XCTAssertFalse(text.contains("23:07"), text)
    }

    func testAvailableUpdateShowsInFooterWithoutReplacingWarnings() {
        var appState = AppState()
        appState.selectedCalendarIDs = ["work"]
        var failed = ProviderHealth()
        failed.lastErrorDescription = "Network"
        appState.providerHealth = failed
        XCTAssertNil(
            StatusBarPopoverPresenter.presentation(
                for: StatusBarMenuState.make(from: appState, now: now), now: now
            ).updateAvailableText
        )

        appState.availableUpdate = AvailableUpdate(
            version: "1.3.0",
            releaseURL: URL(string: "https://github.com/allison-fang/Soon/releases/tag/v1.3.0")!
        )
        let updated = StatusBarPopoverPresenter.presentation(
            for: StatusBarMenuState.make(from: appState, now: now), now: now
        )
        XCTAssertEqual(updated.updateAvailableText, "status_bar_popover_update_available".loco())
        XCTAssertNotNil(updated.notice)
    }
}
