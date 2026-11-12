//
//  StatusBarPopoverPresentation.swift
//  MeetingBar
//

import AppKit
import Foundation

enum TimelineEventPhase: Equatable {
    case past
    case current
    case upcoming
}

struct TimelineGuest: Identifiable, Equatable {
    let id: String
    let name: String
    let email: String?
    let initial: String
    let status: MBEventAttendeeStatus
    let isOptional: Bool
    let isCurrentUser: Bool
}

struct TimelineEventPresentation: Identifiable, Equatable {
    let event: MBEvent
    let title: String
    let phase: TimelineEventPhase
    let response: TimelineEventResponse
    let isNext: Bool
    let isDismissed: Bool
    let countdown: String?
    /// What a card calls the meeting: the service name, or the host for an
    /// unrecognized link.
    let linkLabel: String?
    /// The readable part of the meeting URL, for the details panel.
    let linkPreview: String?
    let descriptionPreview: String?
    /// Attendees without meeting rooms, most committed first.
    let guests: [TimelineGuest]

    var id: String { event.id }
    var isCanceled: Bool { event.status == .canceled }
    var canJoin: Bool { event.meetingLink != nil && !isCanceled }
}

struct TimelinePlacedEvent: Identifiable, Equatable {
    let event: TimelineEventPresentation
    let placement: TimelinePlacement

    var id: String { event.id }
}

struct TimelineHourLabel: Identifiable, Equatable {
    let offset: Double
    let text: String

    var id: Double { offset }
}

struct TimelineNowIndicator: Equatable {
    let offset: Double
    let text: String
}

struct TimelineDayPresentation: Identifiable, Equatable {
    let id: Date
    let title: String
    let dateText: String
    let allDayEvents: [TimelineEventPresentation]
    let timedEvents: [TimelinePlacedEvent]
    let gridHeight: Double
    let hourLabels: [TimelineHourLabel]
    let now: TimelineNowIndicator?
    let emptyMessage: String?
}

enum StatusBarNoticeAction: Equatable {
    case reconnect
    case grantPermission
    case refresh
    case openPreferences
}

struct StatusBarNotice: Equatable {
    let title: String
    let actionTitle: String
    let action: StatusBarNoticeAction
}

struct StatusBarPopoverPresentation: Equatable {
    var density: TimelineDensity = .comfortable
    var title = ""
    var dateText = ""
    var notice: StatusBarNotice?
    var days: [TimelineDayPresentation] = []
    var bookmarks: [Bookmark] = []
    var lastUpdatedText: String?

    /// Display order, used for arrow-key navigation.
    var events: [TimelineEventPresentation] {
        days.flatMap { day in day.allDayEvents + day.timedEvents.map(\.event) }
    }

    var timelineHeight: Double {
        days.reduce(0) { $0 + $1.gridHeight }
    }
}

@MainActor
struct StatusBarPopoverPresenter {
    private static let maxPreviewLength = 120

    let state: StatusBarMenuState
    let now: Date
    var calendar: Calendar = .current

    static func presentation(
        for state: StatusBarMenuState,
        now: Date
    ) -> StatusBarPopoverPresentation {
        StatusBarPopoverPresenter(state: state, now: now).make()
    }

    func make() -> StatusBarPopoverPresentation {
        var presentation = StatusBarPopoverPresentation(
            density: state.menu.timelineDensity,
            title: "status_bar_section_today".loco(),
            dateText: dayFormatter.string(from: calendar.startOfDay(for: now)),
            notice: notice(),
            bookmarks: state.meetings.bookmarks,
            lastUpdatedText: state.providerHealth.lastSuccessfulRefresh.map {
                "status_bar_popover_updated".loco(timeFormatter.string(from: $0))
            }
        )
        guard state.hasSelectedCalendars, !hidesEmptyDays(for: presentation.notice) else {
            return presentation
        }

        let today = calendar.startOfDay(for: now)
        presentation.days.append(
            day(start: today, title: "status_bar_section_today".loco(), events: state.todayEvents, isToday: true)
        )
        if state.events.showEventsForPeriod == .today_n_tomorrow,
           let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) {
            presentation.days.append(
                day(
                    start: tomorrow,
                    title: "status_bar_section_tomorrow".loco(),
                    events: state.tomorrowEvents
                )
            )
        }
        return presentation
    }

    // MARK: - Notices

    /// With a failure showing, an empty day means "unknown", not "free".
    private func hidesEmptyDays(for notice: StatusBarNotice?) -> Bool {
        notice != nil && state.todayEvents.isEmpty && state.tomorrowEvents.isEmpty
    }

    func notice() -> StatusBarNotice? {
        if let warning = state.providerWarning {
            return notice(for: warning)
        }
        switch state.emptyStateReason {
        case .authRequired:
            return notice(for: .authRequired)
        case .permissionRequired:
            return notice(for: .permissionRequired)
        case .refreshFailed:
            return notice(for: .refreshFailed)
        case .noCalendarsSelected:
            return StatusBarNotice(
                title: "status_bar_control_no_calendars".loco(),
                actionTitle: "status_bar_control_select_calendars".loco(),
                action: .openPreferences
            )
        case .noUpcomingMeetings, nil:
            return nil
        }
    }

    private func notice(for warning: StatusBarProviderWarning) -> StatusBarNotice {
        switch warning {
        case .authRequired:
            StatusBarNotice(
                title: "status_bar_control_auth_required".loco(),
                actionTitle: "status_bar_control_reconnect".loco(),
                action: .reconnect
            )
        case .permissionRequired:
            StatusBarNotice(
                title: "status_bar_control_permission_required".loco(),
                actionTitle: "status_bar_control_grant_permission".loco(),
                action: .grantPermission
            )
        case .stale:
            StatusBarNotice(
                title: "status_bar_control_stale".loco(),
                actionTitle: "general_refresh".loco(),
                action: .refresh
            )
        case .refreshFailed:
            StatusBarNotice(
                title: "status_bar_control_refresh_failed".loco(),
                actionTitle: "general_refresh".loco(),
                action: .refresh
            )
        }
    }

    // MARK: - Days

    private func day(
        start: Date,
        title: String,
        events: [MBEvent],
        isToday: Bool = false
    ) -> TimelineDayPresentation {
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        let interval = DateInterval(start: start, end: end)
        let visible = events
            .filter(shouldRender)
            .sorted { $0.startDate < $1.startDate }
        let timed = visible.filter { !$0.isAllDay }
        let layoutEvents = timed.map {
            TimelineLayoutEvent(id: $0.id, start: $0.startDate, end: $0.endDate)
        }

        let window = timed.isEmpty
            ? nil
            : TimelineLayout.window(
                for: layoutEvents,
                now: now,
                day: interval,
                calendar: calendar,
                scale: scale
            )
        let placed = window.map { window in
            TimelineLayout.placements(for: layoutEvents, in: window).compactMap { placement in
                timed.first { $0.id == placement.id }.map {
                    TimelinePlacedEvent(event: event($0), placement: placement)
                }
            }
        } ?? []

        return TimelineDayPresentation(
            id: start,
            title: title,
            dateText: dayFormatter.string(from: start),
            allDayEvents: visible.filter(\.isAllDay).map(event),
            timedEvents: placed,
            gridHeight: window?.height ?? 0,
            hourLabels: window.map(hourLabels) ?? [],
            now: window.flatMap(nowIndicator),
            emptyMessage: visible.isEmpty ? emptyMessage(title: title, isToday: isToday) : nil
        )
    }

    private var scale: TimelineScale {
        state.menu.timelineDensity == .compact ? .compact : .comfortable
    }

    private func emptyMessage(title: String, isToday: Bool) -> String {
        isToday && state.emptyStateReason == .noUpcomingMeetings
            ? "🎉 \("status_bar_control_no_upcoming".loco())"
            : "status_bar_section_date_nothing".loco(title.lowercased())
    }

    private func hourLabels(in window: TimelineWindow) -> [TimelineHourLabel] {
        TimelineLayout.hourTicks(in: window, calendar: calendar).map {
            TimelineHourLabel(offset: window.offset(of: $0), text: hourFormatter.string(from: $0))
        }
    }

    private func nowIndicator(in window: TimelineWindow) -> TimelineNowIndicator? {
        guard window.contains(now) else { return nil }
        return TimelineNowIndicator(
            offset: window.offset(of: now),
            text: nowFormatter.string(from: now)
        )
    }

    private func shouldRender(_ event: MBEvent) -> Bool {
        if event.participationStatus == .declined || event.status == .canceled,
           state.events.declinedEventsAppearance == .hide {
            return false
        }
        if event.endDate < now, state.events.pastEventsAppearance == .hide {
            return false
        }
        if event.attendees.isEmpty, state.events.personalEventsAppearance == .hide {
            return false
        }
        return true
    }

    // MARK: - Events

    func event(_ event: MBEvent) -> TimelineEventPresentation {
        let phase = phase(of: event)
        let isNext = event.id == state.nextEvent?.id
        return TimelineEventPresentation(
            event: event,
            title: event.title.isEmpty ? "status_bar_no_title".loco() : event.title,
            phase: phase,
            response: response(to: event),
            isNext: isNext,
            isDismissed: state.events.dismissedEvents.contains { $0.id == event.id },
            countdown: isNext && phase == .upcoming ? countdown(to: event) : nil,
            linkLabel: event.meetingLink.map { linkLabel(for: $0) },
            linkPreview: event.meetingLink.map { linkPreview(for: $0) },
            descriptionPreview: descriptionPreview(for: event),
            guests: guests(of: event)
        )
    }

    private func phase(of event: MBEvent) -> TimelineEventPhase {
        if event.endDate <= now { return .past }
        return event.startDate <= now ? .current : .upcoming
    }

    private func response(to event: MBEvent) -> TimelineEventResponse {
        if event.status == .canceled { return .declined }
        switch event.participationStatus {
        case .declined:
            return .declined
        case .pending:
            return .pending
        case .tentative:
            return .tentative
        default:
            return event.status == .tentative ? .tentative : .accepted
        }
    }

    private func countdown(to event: MBEvent) -> String? {
        let timeLeft = StatusBarTitlePolicy.formattedTimeLeft(
            from: now,
            to: event.startDate,
            calendar: calendar
        )
        return timeLeft.isEmpty ? nil : "status_bar_event_status_in".loco(timeLeft)
    }

    private func linkLabel(for link: MeetingLink) -> String {
        link.service.flatMap(MeetingProvider.provider(for:))?.displayName
            ?? trimmedHost(of: link.url)
            ?? link.url.absoluteString
    }

    /// Host and short path only: query strings can carry meeting passwords.
    private func linkPreview(for link: MeetingLink) -> String {
        guard let host = trimmedHost(of: link.url) else { return linkLabel(for: link) }
        let path = link.url.path
        return path.count > 1 && path.count <= 24 ? host + path : host
    }

    private func trimmedHost(of url: URL) -> String? {
        url.host.map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 }
    }

    private func descriptionPreview(for event: MBEvent) -> String? {
        guard let notes = event.notes else { return nil }
        let line = cleanUpNotes(notes)
            .components(separatedBy: .newlines)
            .lazy
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && !$0.contains("://") }
        return line.map { String($0.prefix(Self.maxPreviewLength)) }
    }

    private func guests(of event: MBEvent) -> [TimelineGuest] {
        event.attendees
            .filter { !isRoom($0) }
            .sorted { guestRank($0) < guestRank($1) }
            .map { attendee in
                let identity = attendee.email ?? attendee.name
                return TimelineGuest(
                    id: identity,
                    name: attendee.name,
                    email: attendee.email,
                    initial: Self.initial(for: attendee.name),
                    status: attendee.status,
                    isOptional: attendee.optional,
                    isCurrentUser: attendee.isCurrentUser
                )
            }
    }

    private func isRoom(_ attendee: MBEventAttendee) -> Bool {
        attendee.email?.hasSuffix("@resource.calendar.google.com") ?? false
    }

    private func guestRank(_ attendee: MBEventAttendee) -> Int {
        switch attendee.status {
        case .accepted: 0
        case .tentative: 1
        case .declined: 3
        default: 2
        }
    }

    static func initial(for name: String) -> String {
        name.first { $0.isLetter || $0.isNumber }.map { String($0).uppercased() } ?? "?"
    }

    // MARK: - Formatting

    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = I18N.instance.locale
        formatter.dateFormat = state.timeFormat == .am_pm ? "h:mm a" : "HH:mm"
        return formatter
    }

    /// Sits in the hour gutter, where the surrounding labels already give AM/PM.
    private var nowFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = I18N.instance.locale
        formatter.dateFormat = state.timeFormat == .am_pm ? "h:mm" : "HH:mm"
        return formatter
    }

    private var hourFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = I18N.instance.locale
        formatter.dateFormat = state.timeFormat == .am_pm ? "h a" : "HH:mm"
        return formatter
    }

    private var dayFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = I18N.instance.locale
        formatter.setLocalizedDateFormatFromTemplate("EEEdMMM")
        return formatter
    }
}
