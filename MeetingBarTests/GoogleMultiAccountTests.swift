//
//  GoogleMultiAccountTests.swift
//  MeetingBarTests
//

import XCTest

@testable import MeetingBar

/// A fake Google account: its calendar list, events per calendar, and a switch
/// that makes Google reject its token.
@MainActor
private final class FakeGoogleAccount {
    let key: String
    let email: String?
    var calendarList: String
    var eventsByCalendar: [String: String] = [:]
    var rejectsToken = false
    var isCurrent = true
    private(set) var requestedEventCalendarIDs: [String] = []

    init(email: String?, key: String? = nil, calendarList: String) {
        self.email = email
        self.key = key ?? email.map(GoogleAccountKey.make(email:)) ?? GoogleAccountKey.placeholder()
        self.calendarList = calendarList
    }

    var readerAccount: GoogleCalendarAccountsReader.Account {
        let client = GoogleCalendarHTTPClient(
            transport: { [self] request in
                let (status, body) = respond(to: request)
                return (
                    Data(body.utf8),
                    HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
                )
            },
            accessToken: { _ in "fixture-token" }
        )
        return GoogleCalendarAccountsReader.Account(
            key: key,
            email: email,
            isUsable: true,
            reader: GoogleCalendarDataReader(userEmail: email) { url, calendarID in
                try await client.fetchJSON(url, calendarID: calendarID)
            },
            isCurrent: { [self] in isCurrent }
        )
    }

    private func respond(to request: URLRequest) -> (Int, String) {
        if rejectsToken { return (401, #"{"error":{"code":401}}"#) }
        let path = request.url!.path
        if path.contains("calendarList") { return (200, calendarList) }
        let calendarID = path
            .replacingOccurrences(of: "/calendar/v3/calendars/", with: "")
            .replacingOccurrences(of: "/events", with: "")
        requestedEventCalendarIDs.append(calendarID)
        return (200, eventsByCalendar[calendarID] ?? #"{"items":[]}"#)
    }
}

private func calendarList(_ entries: [(id: String, role: String, primary: Bool)]) -> String {
    let items = entries.map {
        ##"{"id":"\##($0.id)","summary":"\##($0.id)","backgroundColor":"#ff0000","accessRole":"\##($0.role)","primary":\##($0.primary)}"##
    }
    return #"{"items":[\#(items.joined(separator: ","))]}"#
}

private func events(_ ids: [String]) -> String {
    let items = ids.map {
        #"{"id":"\#($0)","summary":"\#($0)","status":"confirmed","start":{"dateTime":"2026-10-18T09:00:00Z"},"end":{"dateTime":"2026-10-18T09:30:00Z"}}"#
    }
    return #"{"items":[\#(items.joined(separator: ","))]}"#
}

@MainActor
final class GoogleMultiAccountTests: BaseTestCase {
    private let start = ISO8601DateFormatter().date(from: "2026-10-18T00:00:00Z")!
    private let end = ISO8601DateFormatter().date(from: "2026-10-19T00:00:00Z")!

    private func makeWorkAndPersonal() -> (work: FakeGoogleAccount, personal: FakeGoogleAccount) {
        let work = FakeGoogleAccount(
            email: "work@example.com",
            calendarList: calendarList([
                ("work@example.com", "owner", true),
                ("family", "reader", false)
            ])
        )
        work.eventsByCalendar["work@example.com"] = events(["standup"])
        work.eventsByCalendar["family"] = events(["dinner"])
        let personal = FakeGoogleAccount(
            email: "me@example.com",
            calendarList: calendarList([
                ("me@example.com", "owner", true),
                ("family", "owner", false)
            ])
        )
        personal.eventsByCalendar["me@example.com"] = events(["gym"])
        personal.eventsByCalendar["family"] = events(["dinner"])
        return (work, personal)
    }

    func testCalendarsFromTwoAccountsAreListedTogetherAndSharedOnesOnce() async throws {
        let (work, personal) = makeWorkAndPersonal()
        let reader = GoogleCalendarAccountsReader()

        let calendars = try await reader.fetchCalendars(from: [work.readerAccount, personal.readerAccount])

        XCTAssertEqual(calendars.map(\.id), ["work@example.com", "family", "me@example.com"])
        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: calendars.map { ($0.id, $0.source) }),
            ["work@example.com": "work@example.com", "family": "me@example.com", "me@example.com": "me@example.com"],
            "The shared calendar belongs to the account that owns it"
        )
    }

    func testEachCalendarsEventsAreFetchedOnceThroughTheAccountThatListedIt() async throws {
        let (work, personal) = makeWorkAndPersonal()
        let reader = GoogleCalendarAccountsReader()
        let accounts = [work.readerAccount, personal.readerAccount]
        let calendars = try await reader.fetchCalendars(from: accounts)

        let fetched = try await reader.fetchEvents(from: accounts, for: calendars, from: start, to: end)

        XCTAssertEqual(Set(fetched.map(\.id)), ["standup", "dinner", "gym"])
        XCTAssertEqual(work.requestedEventCalendarIDs, ["work@example.com"])
        XCTAssertEqual(personal.requestedEventCalendarIDs.sorted(), ["family", "me@example.com"])
    }

    func testOneExpiredAccountKeepsItsLastMeetingsAndTheOtherStaysFresh() async throws {
        let (work, personal) = makeWorkAndPersonal()
        let reader = GoogleCalendarAccountsReader()
        let accounts = [work.readerAccount, personal.readerAccount]
        let calendars = try await reader.fetchCalendars(from: accounts)
        _ = try await reader.fetchEvents(from: accounts, for: calendars, from: start, to: end)

        work.rejectsToken = true
        personal.eventsByCalendar["me@example.com"] = events(["gym", "yoga"])
        let refreshedCalendars = try await reader.fetchCalendars(from: accounts)
        let refreshed = try await reader.fetchEvents(
            from: accounts, for: refreshedCalendars, from: start, to: end
        )

        XCTAssertEqual(refreshedCalendars.map(\.id), calendars.map(\.id))
        XCTAssertEqual(Set(refreshed.map(\.id)), ["standup", "dinner", "gym", "yoga"])
        XCTAssertEqual(reader.statuses["work@example.com"], .authRequired)
        XCTAssertEqual(reader.statuses["me@example.com"], .connected)
    }

    func testEveryAccountFailingIsAProviderFailure() async {
        let (work, personal) = makeWorkAndPersonal()
        work.rejectsToken = true
        personal.rejectsToken = true
        let reader = GoogleCalendarAccountsReader()

        do {
            _ = try await reader.fetchCalendars(from: [work.readerAccount, personal.readerAccount])
            XCTFail("Expected the refresh to fail")
        } catch {
            XCTAssertTrue(GoogleAccountErrorPolicy.requiresReauthorization(error))
        }
    }

    func testRemovedAccountsLateResultsAreIgnored() async throws {
        let (work, personal) = makeWorkAndPersonal()
        work.isCurrent = false
        let reader = GoogleCalendarAccountsReader()

        let calendars = try await reader.fetchCalendars(from: [work.readerAccount, personal.readerAccount])

        XCTAssertEqual(calendars.map(\.id), ["me@example.com", "family"])
        XCTAssertNil(reader.statuses["work@example.com"])
    }

    func testForgettingAnAccountReportsWhichSelectionsNoOtherAccountCanShow() async throws {
        let (work, personal) = makeWorkAndPersonal()
        let reader = GoogleCalendarAccountsReader()
        _ = try await reader.fetchCalendars(from: [work.readerAccount, personal.readerAccount])

        let removedPersonal = reader.forget("me@example.com")

        XCTAssertEqual(removedPersonal.calendarIDs, ["me@example.com", "family"])
        XCTAssertEqual(removedPersonal.orphanedCalendarIDs, ["me@example.com"])
        XCTAssertNil(reader.statuses["me@example.com"])
    }

    func testLoginWithoutAKnownEmailLearnsItFromItsPrimaryCalendar() async throws {
        let unknown = FakeGoogleAccount(
            email: nil,
            calendarList: calendarList([("old@example.com", "owner", true)])
        )
        let reader = GoogleCalendarAccountsReader()
        var discovered: [(String, String)] = []
        reader.onEmailDiscovered = { key, email in
            discovered.append((key, email))
            return GoogleAccountKey.make(email: email)
        }

        let calendars = try await reader.fetchCalendars(from: [unknown.readerAccount])

        XCTAssertEqual(discovered.map(\.1), ["old@example.com"])
        XCTAssertEqual(discovered.map(\.0), [unknown.key])
        XCTAssertEqual(calendars.first?.source, "old@example.com")
        XCTAssertEqual(calendars.first?.email, "old@example.com")
        XCTAssertEqual(reader.statuses["old@example.com"], .connected)
    }

    func testDuplicateLoginFoundByItsPrimaryCalendarIsDropped() async throws {
        let unknown = FakeGoogleAccount(
            email: nil,
            calendarList: calendarList([("me@example.com", "owner", true)])
        )
        let (_, personal) = makeWorkAndPersonal()
        let reader = GoogleCalendarAccountsReader()
        reader.onEmailDiscovered = { _, _ in nil }

        let calendars = try await reader.fetchCalendars(from: [unknown.readerAccount, personal.readerAccount])

        XCTAssertEqual(calendars.map(\.id), ["me@example.com", "family"])
        XCTAssertEqual(calendars.first?.source, "me@example.com")
    }
}

@MainActor
final class GoogleAccountHealthTests: XCTestCase {
    func testOneAccountLeftBehindMakesASuccessfulRefreshStale() {
        let health = ProviderHealth.success(attempted: Date()).applyingAccounts([
            ProviderAccountHealth(id: "work", email: "work@example.com", status: .authRequired),
            ProviderAccountHealth(id: "me", email: "me@example.com", status: .connected)
        ])

        XCTAssertTrue(health.isStale)
        XCTAssertFalse(health.authRequired, "The other account still works")
        XCTAssertEqual(health.firstAccountNeedingReconnect?.id, "work")
        XCTAssertNotNil(health.lastErrorDescription)
    }

    func testAllAccountsConnectedStaysUpToDate() {
        let health = ProviderHealth.success(attempted: Date()).applyingAccounts([
            ProviderAccountHealth(id: "me", email: "me@example.com", status: .connected)
        ])

        XCTAssertFalse(health.isStale)
        XCTAssertNil(health.lastErrorDescription)
        XCTAssertNil(health.firstAccountNeedingReconnect)
    }

    func testKeychainAccountQueriesAreScopedToOneAccount() {
        let save = KeychainQueryFactory.saveQuery(data: Data(), service: "google.accounts", account: "me@example.com")
        let load = KeychainQueryFactory.loadQuery(service: "google.accounts", account: "me@example.com")
        let delete = KeychainQueryFactory.deleteQuery(service: "google.accounts", account: "me@example.com")
        let list = KeychainQueryFactory.listAccountsQuery(service: "google.accounts")

        for query in [save, load, delete] {
            XCTAssertEqual(query[kSecAttrAccount as String] as? String, "me@example.com")
            XCTAssertEqual(query[kSecAttrService as String] as? String, "google.accounts")
        }
        XCTAssertNil(KeychainQueryFactory.deleteQuery(service: "google")[kSecAttrAccount as String])
        XCTAssertEqual(list[kSecReturnAttributes as String] as? Bool, true)
        XCTAssertNil(list[kSecReturnData as String])
        XCTAssertEqual(list[kSecMatchLimit as String] as? String, kSecMatchLimitAll as String)
    }
}
