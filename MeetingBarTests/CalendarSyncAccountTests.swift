//
//  CalendarSyncAccountTests.swift
//  MeetingBarTests
//

import Combine
import Defaults
import XCTest

@testable import MeetingBar

@MainActor
final class CalendarSyncAccountTests: BaseTestCase {
    private var cancellables = Set<AnyCancellable>()
    private let soon = Date().addingTimeInterval(600)

    private func calendar(_ id: String, account: String) -> MBCalendar {
        MBCalendar(title: id, id: id, source: account, email: account, color: .black)
    }

    private func event(_ id: String, on calendar: MBCalendar) -> MBEvent {
        MBEvent(
            id: id,
            lastModifiedDate: nil,
            title: id,
            status: .confirmed,
            notes: nil,
            location: nil,
            url: nil,
            organizer: nil,
            startDate: soon,
            endDate: soon.addingTimeInterval(1800),
            isAllDay: false,
            recurrent: false,
            calendar: calendar
        )
    }

    private func makeSync(
        _ store: FakeMultiAccountEventStore,
        selected: [String]
    ) -> CalendarSync {
        Defaults[.eventStoreProvider] = .googleCalendar
        Defaults[.selectedCalendarIDsByProvider] = [EventStoreProvider.googleCalendar.rawValue: selected]
        Defaults[.selectedCalendarIDs] = selected
        Defaults[.selectedCalendarIDsByProviderMigrated] = true
        let repository = CalendarRepository(providerName: .googleCalendar) { _ in store }
        return CalendarSync(repository: repository, refreshInterval: 0)
    }

    private func waitForEvents(
        _ sync: CalendarSync,
        _ description: String,
        _ predicate: @escaping ([MBEvent]) -> Bool
    ) async {
        let exp = expectation(description: description)
        sync.$events
            .first(where: predicate)
            .sink { _ in exp.fulfill() }
            .store(in: &cancellables)
        await fulfillment(of: [exp], timeout: 2)
    }

    private func workAndPersonal() -> (FakeMultiAccountEventStore, work: MBCalendar, personal: MBCalendar, shared: MBCalendar) {
        let work = calendar("work-cal", account: "work@example.com")
        let personal = calendar("me-cal", account: "me@example.com")
        let shared = calendar("family", account: "me@example.com")
        let store = FakeMultiAccountEventStore(
            accounts: [
                ProviderAccountHealth(id: "work@example.com", email: "work@example.com", status: .connected),
                ProviderAccountHealth(id: "me@example.com", email: "me@example.com", status: .connected)
            ],
            calendarsByAccount: [
                "work@example.com": [work, shared],
                "me@example.com": [personal, shared]
            ],
            events: [event("standup", on: work), event("gym", on: personal), event("dinner", on: shared)]
        )
        return (store, work, personal, shared)
    }

    func testOneAccountNeedingReconnectLeavesTheOthersMeetingsShowing() async {
        let (store, work, personal, shared) = workAndPersonal()
        store.stubbedAccounts[0].status = .authRequired
        let sync = makeSync(store, selected: [work.id, personal.id, shared.id])

        await waitForEvents(sync, "meetings from both accounts") { $0.count == 3 }

        XCTAssertFalse(sync.providerHealth.authRequired)
        XCTAssertTrue(sync.providerHealth.isStale)
        XCTAssertEqual(sync.providerHealth.firstAccountNeedingReconnect?.id, "work@example.com")
        XCTAssertEqual(sync.providerHealth.accounts.map(\.id), ["work@example.com", "me@example.com"])
    }

    func testRemovingAnAccountDropsItsMeetingsAtOnceAndUnticksOnlyItsCalendars() async {
        let (store, work, personal, shared) = workAndPersonal()
        let sync = makeSync(store, selected: [work.id, personal.id, shared.id])
        await waitForEvents(sync, "initial meetings") { $0.count == 3 }

        await sync.removeAccount("work@example.com")

        XCTAssertFalse(sync.events.contains { $0.id == "standup" })
        XCTAssertFalse(sync.calendars.contains { $0.id == work.id })
        XCTAssertEqual(AppSettings.selectedCalendarIDs(for: .googleCalendar), [personal.id, shared.id])
        XCTAssertEqual(store.revokedAccountIDs, ["work@example.com"])
        XCTAssertEqual(sync.providerHealth.accounts.map(\.id), ["me@example.com"])

        await waitForEvents(sync, "the shared calendar comes back through the other account") {
            Set($0.map(\.id)) == ["gym", "dinner"]
        }
    }

    func testRefreshStartedBeforeARemovalCannotBringTheAccountBack() async throws {
        let (store, work, personal, shared) = workAndPersonal()
        let sync = makeSync(store, selected: [work.id, personal.id, shared.id])
        await waitForEvents(sync, "initial meetings") { $0.count == 3 }

        store.fetchDelay = 0.3
        try await Task.sleep(nanoseconds: 250_000_000)
        try await sync.refreshSources()
        try await Task.sleep(nanoseconds: 50_000_000)
        var publishedAfterRemoval: [[String]] = []
        await sync.removeAccount("work@example.com")
        sync.$events
            .sink { publishedAfterRemoval.append($0.map(\.id)) }
            .store(in: &cancellables)

        await waitForEvents(sync, "refresh after removal") { Set($0.map(\.id)) == ["gym", "dinner"] }
        XCTAssertFalse(publishedAfterRemoval.joined().contains("standup"))
    }

    func testAddingAnAccountDuringARefreshShowsItsCalendars() async throws {
        let (store, work, personal, shared) = workAndPersonal()
        let sync = makeSync(store, selected: [work.id, personal.id, shared.id])
        await waitForEvents(sync, "initial meetings") { $0.count == 3 }
        let school = calendar("school-cal", account: "school@example.com")
        store.pendingAccount = (
            ProviderAccountHealth(id: "school@example.com", email: "school@example.com", status: .connected),
            [school]
        )

        store.fetchDelay = 0.2
        try await Task.sleep(nanoseconds: 250_000_000)
        try await sync.refreshSources()
        let result = await sync.addAccount()

        XCTAssertEqual(result, .success)
        XCTAssertEqual(sync.providerHealth.accounts.last?.id, "school@example.com")
        let exp = expectation(description: "new account's calendars listed")
        sync.$calendars
            .first { $0.contains { $0.id == school.id } }
            .sink { _ in exp.fulfill() }
            .store(in: &cancellables)
        await fulfillment(of: [exp], timeout: 2)
    }

    func testFailedAddLeavesTheConnectedAccountsAlone() async {
        let (store, work, personal, shared) = workAndPersonal()
        let sync = makeSync(store, selected: [work.id, personal.id, shared.id])
        await waitForEvents(sync, "initial meetings") { $0.count == 3 }
        let healthBefore = sync.providerHealth
        store.addAccountError = AuthError.temporarilyUnavailable(underlying: URLError(.notConnectedToInternet))

        let result = await sync.addAccount()

        guard case .failed = result else { return XCTFail("Expected a failure, got \(result)") }
        XCTAssertEqual(sync.providerHealth, healthBefore)
        XCTAssertEqual(sync.events.count, 3)
    }
}
