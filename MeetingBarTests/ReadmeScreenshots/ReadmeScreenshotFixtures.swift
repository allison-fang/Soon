//
//  ReadmeScreenshotFixtures.swift
//  MeetingBarTests
//

import AppKit

@testable import MeetingBar

/// Obviously fictional events for the README screenshots: never real calendar data.
enum ReadmeScreenshotFixtures {
    static let detailsEventID = "staff-meeting"

    /// The day Fry is unfrozen.
    static var now: Date { time(10, 20) }
    static var lastRefresh: Date { time(10, 18) }

    static let planetExpress = MBCalendar(
        title: "Planet Express", id: "planet-express", source: nil, email: nil,
        color: NSColor(srgbRed: 0.475, green: 0.525, blue: 0.796, alpha: 1)
    )
    static let personal = MBCalendar(
        title: "Personal", id: "personal", source: nil, email: nil,
        color: NSColor(srgbRed: 0.937, green: 0.604, blue: 0.290, alpha: 1)
    )
    static let calendars = [planetExpress, personal]

    private static func person(_ name: String) -> String {
        "\(name.lowercased())@planetexpress.example"
    }

    private static func fry(_ status: MBEventAttendeeStatus) -> MBEventAttendee {
        MBEventAttendee(email: person("fry"), name: "Philip J. Fry", status: status, isCurrentUser: true)
    }

    private static let farnsworth = MBEventAttendee(
        email: person("farnsworth"), name: "Professor Farnsworth", status: .accepted
    )
    private static let leela = MBEventAttendee(email: person("leela"), name: "Turanga Leela", status: .accepted)
    private static let bender = MBEventAttendee(email: person("bender"), name: "Bender Rodríguez", status: .accepted)
    private static let amy = MBEventAttendee(email: person("amy"), name: "Amy Wong", status: .accepted, optional: true)
    private static let hermes = MBEventAttendee(email: person("hermes"), name: "Hermes Conrad", status: .tentative)
    private static let scruffy = MBEventAttendee(email: person("scruffy"), name: "Scruffy", status: .pending)
    private static let zoidberg = MBEventAttendee(email: person("zoidberg"), name: "Dr. Zoidberg", status: .declined)

    static var events: [MBEvent] {
        [
            event(
                "new-years-eve", "New Year's Eve, 2999", calendar: personal,
                start: time(0, 0), end: day(offset: 1), isAllDay: true
            ),
            event(
                "unfreezing-day", "Fry's Cryo-Unfreezing Day 🧊", calendar: personal,
                start: time(0, 0), end: day(offset: 1), isAllDay: true
            ),
            event(
                "crew-briefing", "Morning Crew Briefing", calendar: planetExpress,
                start: time(8, 30), end: time(9, 0),
                attendees: [fry(.accepted), farnsworth, leela, bender]
            ),
            event(
                "bending-unit", "Bending Unit Maintenance", calendar: personal,
                start: time(9, 15), end: time(9, 45)
            ),
            event(
                "omicron-briefing", "Delivery Briefing: Omicron Persei 8", calendar: planetExpress,
                start: time(10, 0), end: time(10, 45),
                url: URL(string: "https://zoom.us/j/3000000000"),
                attendees: [fry(.accepted), leela, bender]
            ),
            event(
                detailsEventID, "Planet Express Staff Meeting", calendar: planetExpress,
                start: time(10, 30), end: time(11, 30),
                url: URL(string: "https://meet.google.com/goo-dnew-sev"),
                organizer: MBEventOrganizer(email: farnsworth.email, name: farnsworth.name),
                location: "Conference Room, Planet Express HQ, New New York",
                notes: "Good news, everyone!\n1. Moon delivery\n2. Who drank the Slurm in the fridge?",
                attendees: [fry(.accepted), farnsworth, leela, bender, amy, hermes, scruffy, zoidberg]
            ),
            event(
                "hypnotoad", "Hypnotoad Appreciation Hour", calendar: planetExpress,
                start: time(11, 0), end: time(11, 30),
                attendees: [fry(.pending), amy, hermes]
            ),
            event(
                "elzars", "Lunch at Elzar's", calendar: personal,
                start: time(12, 0), end: time(13, 0)
            ),
            event(
                "bureaucrat-review", "Grade 36 Bureaucrat Review with Hermes", calendar: planetExpress,
                start: time(13, 30), end: time(14, 0),
                attendees: [fry(.tentative), hermes]
            ),
            event(
                "slurm-inspection", "Slurm Factory Safety Inspection", calendar: planetExpress,
                start: time(14, 30), end: time(15, 30),
                attendees: [fry(.declined), leela, bender]
            ),
            event(
                "nibbler", "Feed Nibbler", calendar: personal,
                start: time(16, 0), end: time(16, 30)
            )
        ]
    }

    // MARK: - Helpers

    private static func day(offset: Int) -> Date {
        let components = DateComponents(year: 2999, month: 12, day: 31 + offset)
        return Calendar.current.date(from: components)!
    }

    private static func time(_ hour: Int, _ minute: Int) -> Date {
        Calendar.current.date(byAdding: DateComponents(hour: hour, minute: minute), to: day(offset: 0))!
    }

    private static func event(
        _ id: String,
        _ title: String,
        calendar: MBCalendar,
        start: Date,
        end: Date,
        isAllDay: Bool = false,
        url: URL? = nil,
        organizer: MBEventOrganizer? = nil,
        location: String? = nil,
        notes: String? = nil,
        attendees: [MBEventAttendee] = []
    ) -> MBEvent {
        MBEvent(
            id: id,
            lastModifiedDate: nil,
            title: title,
            status: .confirmed,
            notes: notes,
            location: location,
            url: url,
            calendarOpenURL: URL(string: "https://calendar.example/event/\(id)"),
            organizer: organizer,
            attendees: attendees,
            startDate: start,
            endDate: end,
            isAllDay: isAllDay,
            recurrent: false,
            calendar: calendar
        )
    }
}
