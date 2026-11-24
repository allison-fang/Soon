//
//  FakeMultiAccountEventStore.swift
//  MeetingBarTests
//

import Foundation

@testable import MeetingBar

/// A provider with several accounts, each owning its own calendars.
final class FakeMultiAccountEventStore: MultiAccountEventStore {
    nonisolated(unsafe) var stubbedAccounts: [ProviderAccountHealth]
    nonisolated(unsafe) var calendarsByAccount: [String: [MBCalendar]]
    nonisolated(unsafe) var stubbedEvents: [MBEvent]
    nonisolated(unsafe) var fetchDelay: TimeInterval = 0
    /// Added on `addAccount()`.
    nonisolated(unsafe) var pendingAccount: (account: ProviderAccountHealth, calendars: [MBCalendar])?
    nonisolated(unsafe) var addAccountError: Error?
    nonisolated(unsafe) private(set) var revokedAccountIDs: [String] = []
    nonisolated(unsafe) private(set) var fetchCallCount = 0

    init(
        accounts: [ProviderAccountHealth],
        calendarsByAccount: [String: [MBCalendar]],
        events: [MBEvent] = []
    ) {
        stubbedAccounts = accounts
        self.calendarsByAccount = calendarsByAccount
        stubbedEvents = events
    }

    var accounts: [ProviderAccountHealth] { stubbedAccounts }

    func fetchAllCalendars() async throws -> [MBCalendar] {
        fetchCallCount += 1
        if fetchDelay > 0 {
            try await Task.sleep(nanoseconds: UInt64(fetchDelay * 1_000_000_000))
        }
        return currentCalendars
    }

    func fetchEventsForDateRange(for calendars: [MBCalendar], from _: Date, to _: Date) async throws -> [MBEvent] {
        let requested = Set(calendars.map(\.id))
        return stubbedEvents.filter { requested.contains($0.calendar.id) }
    }

    func refreshSources() async {}
    func signIn(forcePrompt _: Bool) async throws {}
    func signOut() async {}

    func addAccount() async throws {
        if let addAccountError { throw addAccountError }
        guard let pendingAccount else { return }
        stubbedAccounts.append(pendingAccount.account)
        calendarsByAccount[pendingAccount.account.id] = pendingAccount.calendars
        self.pendingAccount = nil
    }

    func reconnectAccount(_ id: String) async throws {
        stubbedAccounts = stubbedAccounts.map {
            $0.id == id ? ProviderAccountHealth(id: $0.id, email: $0.email, status: .connected) : $0
        }
    }

    func removeAccount(_ id: String) -> CalendarAccountRemoval {
        let owned = Set((calendarsByAccount[id] ?? []).map(\.id))
        stubbedAccounts.removeAll { $0.id == id }
        calendarsByAccount[id] = nil
        let stillAvailable = Set(currentCalendars.map(\.id))
        return CalendarAccountRemoval(
            calendarIDs: owned,
            orphanedCalendarIDs: owned.subtracting(stillAvailable),
            revokeAccess: { [self] in revokedAccountIDs.append(id) }
        )
    }

    private var currentCalendars: [MBCalendar] {
        var seen = Set<String>()
        return stubbedAccounts.flatMap { calendarsByAccount[$0.id] ?? [] }.filter { seen.insert($0.id).inserted }
    }
}
