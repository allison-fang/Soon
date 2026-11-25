import AppKit
import Foundation

/// Google Calendar's authenticated HTTP results -> calendar/event domain data.
/// GCEventStore retains AppAuth, Keychain, and the real network transport.
@MainActor
struct GoogleCalendarDataReader {
    typealias FetchJSON = @MainActor (_ url: URL, _ calendarID: String?) async throws -> [[String: Any]]

    let userEmail: String?
    let fetchJSON: FetchJSON

    func fetchCalendars() async throws -> [MBCalendar] {
        try await fetchCalendarEntries().map(\.calendar)
    }

    func fetchCalendarEntries() async throws -> [GoogleCalendarListEntry] {
        let url = URL(
            string: "https://www.googleapis.com/calendar/v3/users/me/calendarList?maxResults=250&showHidden=true"
        )!
        let items = try await fetchJSON(url, nil)

        return items.compactMap { item -> GoogleCalendarListEntry? in
            guard let title = item["summary"] as? String,
                  let calendarID = item["id"] as? String,
                  let backgroundColor = item["backgroundColor"] as? String else { return nil }

            return GoogleCalendarListEntry(
                calendar: MBCalendar(
                    title: title,
                    id: calendarID,
                    source: userEmail ?? "google_calendar_account_fallback".loco(),
                    email: userEmail,
                    color: hexStringToUIColor(hex: backgroundColor)
                ),
                accessRole: item["accessRole"] as? String,
                isPrimary: item["primary"] as? Bool ?? false
            )
        }
    }

    func fetchEvents(for calendars: [MBCalendar], from: Date, to: Date) async throws -> [MBEvent] {
        let formatter = ISO8601DateFormatter()
        let timeMin = formatter.string(from: from)
        let timeMax = formatter.string(from: to)
        var events: [MBEvent] = []
        var forbiddenErrors: [Error] = []
        var successfulCalendars = 0

        for calendar in calendars {
            do {
                let url = try GCEventStore.eventsURL(
                    calendarID: calendar.id,
                    timeMin: timeMin,
                    timeMax: timeMax
                )
                let items = try await fetchJSON(url, calendar.id)
                events.append(contentsOf: items.compactMap {
                    GCEventStore.GCParser.event(from: $0, calendar: calendar)
                })
                successfulCalendars += 1
            } catch let error as GoogleCalendarError {
                switch error {
                case .forbiddenCalendar:
                    MeetingBarLogger.calendar.warning(
                        "Skipping inaccessible Google calendar \(calendar.id, privacy: .private): \(error.localizedDescription, privacy: .private)"
                    )
                    forbiddenErrors.append(error)
                default:
                    throw error
                }
            } catch {
                throw error
            }
        }

        return try GoogleCalendarBatchPolicy.finish(
            events: events.deduplicatedPreferringResolvedAttendee(),
            successfulCalendars: successfulCalendars,
            forbiddenErrors: forbiddenErrors
        )
    }
}

struct GoogleCalendarListEntry: Sendable {
    let calendar: MBCalendar
    let accessRole: String?
    let isPrimary: Bool

    func withAccountEmail(_ email: String) -> GoogleCalendarListEntry {
        GoogleCalendarListEntry(
            calendar: MBCalendar(
                title: calendar.title,
                id: calendar.id,
                source: email,
                email: email,
                color: calendar.color
            ),
            accessRole: accessRole,
            isPrimary: isPrimary
        )
    }
}
