//
//  GoogleAccountPolicyTests.swift
//  MeetingBarLogicTests
//

import XCTest

@testable import MeetingBarLogic

@MainActor
private final class InMemoryCredentialStore: GoogleCredentialStore {
    var items: [String: Data] = [:]
    var legacy: Data?
    var failSaves = false
    var failLegacyDelete = false

    func accountKeys() -> [String] { Array(items.keys) }
    func load(account: String) -> Data? { items[account] }
    func save(_ data: Data, account: String) -> Bool {
        guard !failSaves else { return false }
        items[account] = data
        return true
    }
    func delete(account: String) { items[account] = nil }
    func loadLegacy() -> Data? { legacy }
    func deleteLegacy() {
        guard !failLegacyDelete else { return }
        legacy = nil
    }
}

@MainActor
final class GoogleLegacyCredentialMigrationTests: XCTestCase {
    private let login = Data("work-login".utf8)

    func testExistingLoginMovesToItsAccountAndOldItemIsRemoved() {
        let store = InMemoryCredentialStore()
        store.legacy = login

        let key = GoogleLegacyCredentialMigration.migrate(store: store) { _ in "work@example.com" }

        XCTAssertEqual(key, "work@example.com")
        XCTAssertEqual(store.items, ["work@example.com": login])
        XCTAssertNil(store.legacy)
    }

    func testUnreadableLoginIsLeftUntouched() {
        let store = InMemoryCredentialStore()
        store.legacy = login

        let key = GoogleLegacyCredentialMigration.migrate(store: store) { _ in nil }

        XCTAssertNil(key)
        XCTAssertEqual(store.legacy, login)
        XCTAssertTrue(store.items.isEmpty)
    }

    func testFailedCopyKeepsTheOldLoginSoTheUserStaysSignedIn() {
        let store = InMemoryCredentialStore()
        store.legacy = login
        store.failSaves = true

        let key = GoogleLegacyCredentialMigration.migrate(store: store) { _ in "work@example.com" }

        XCTAssertNil(key)
        XCTAssertEqual(store.legacy, login)
    }

    func testNewerLoginForTheSameAccountIsNotOverwritten() {
        let store = InMemoryCredentialStore()
        let newer = Data("newer-login".utf8)
        store.items["work@example.com"] = newer
        store.legacy = login

        GoogleLegacyCredentialMigration.migrate(store: store) { _ in "work@example.com" }

        XCTAssertEqual(store.items["work@example.com"], newer)
        XCTAssertNil(store.legacy)
    }

    func testCopyThatCouldNotBeCleanedUpIsNotImportedTwice() {
        let store = InMemoryCredentialStore()
        store.legacy = login
        store.failLegacyDelete = true
        GoogleLegacyCredentialMigration.migrate(store: store) { _ in GoogleAccountKey.placeholder() }
        store.failLegacyDelete = false

        let key = GoogleLegacyCredentialMigration.migrate(store: store) { _ in GoogleAccountKey.placeholder() }

        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(key, store.items.keys.first)
        XCTAssertNil(store.legacy)
    }

    func testNothingToMoveForNewUsers() {
        let store = InMemoryCredentialStore()

        XCTAssertNil(GoogleLegacyCredentialMigration.migrate(store: store) { _ in "a@example.com" })
        XCTAssertTrue(store.items.isEmpty)
    }
}

final class GoogleAccountKeyTests: XCTestCase {
    func testKeyIgnoresCaseAndSurroundingSpace() {
        XCTAssertEqual(GoogleAccountKey.make(email: " Work@Example.com "), "work@example.com")
    }

    func testPlaceholdersAreUniqueAndHaveNoEmail() {
        let first = GoogleAccountKey.placeholder()
        let second = GoogleAccountKey.placeholder()

        XCTAssertNotEqual(first, second)
        XCTAssertTrue(GoogleAccountKey.isPlaceholder(first))
        XCTAssertNil(GoogleAccountKey.email(for: first))
        XCTAssertEqual(GoogleAccountKey.email(for: "work@example.com"), "work@example.com")
    }

    func testPrimaryCalendarIDGivesTheAccountEmail() {
        XCTAssertEqual(
            GoogleAccountKey.email(fromPrimaryCalendarID: "work@example.com"),
            "work@example.com"
        )
        XCTAssertNil(GoogleAccountKey.email(fromPrimaryCalendarID: "primary"))
        XCTAssertNil(GoogleAccountKey.email(fromPrimaryCalendarID: "@"))
    }
}

final class GoogleCalendarMergePolicyTests: XCTestCase {
    private struct Entry: Equatable {
        let account: String
        let id: String
        let role: String?
    }

    private func merge(_ accounts: [[Entry]]) -> [Entry] {
        GoogleCalendarMergePolicy.merge(accounts, id: \.id, accessRole: \.role)
    }

    func testCalendarsFromDifferentAccountsAreAllKept() {
        let work = [Entry(account: "work", id: "work@example.com", role: "owner")]
        let personal = [Entry(account: "personal", id: "me@example.com", role: "owner")]

        XCTAssertEqual(merge([work, personal]), work + personal)
    }

    func testSharedCalendarIsListedOnceUnderTheAccountThatOwnsIt() {
        let work = [Entry(account: "work", id: "family", role: "reader")]
        let personal = [Entry(account: "personal", id: "family", role: "owner")]

        XCTAssertEqual(merge([work, personal]), personal)
    }

    func testFreeBusyCopyNeverBeatsOneWithDetails() {
        let work = [Entry(account: "work", id: "team", role: "freeBusyReader")]
        let personal = [Entry(account: "personal", id: "team", role: "reader")]

        XCTAssertEqual(merge([work, personal]), personal)
    }

    func testEqualAccessKeepsTheFirstAccountsCopyInItsPlace() {
        let work = [
            Entry(account: "work", id: "holidays", role: "reader"),
            Entry(account: "work", id: "work@example.com", role: "owner")
        ]
        let personal = [Entry(account: "personal", id: "holidays", role: "reader")]

        XCTAssertEqual(merge([work, personal]), work)
    }
}

final class GoogleAccountResultsTests: XCTestCase {
    private struct Offline: Error {}

    func testOneFailingAccountKeepsItsLastKnownDataAndTheOthersFresh() throws {
        let combined = try GoogleAccountResults.combine([
            GoogleAccountResult(account: "work", result: .failure(AuthError.notSignedIn), fallback: ["old-work"]),
            GoogleAccountResult(account: "personal", result: .success(["new-personal"]), fallback: [])
        ])

        XCTAssertEqual(combined.values, ["old-work", "new-personal"])
        XCTAssertEqual(combined.failures.map(\.account), ["work"])
        XCTAssertEqual(combined.valuesByAccount.map(\.account), ["work", "personal"])
    }

    func testEveryAccountFailingIsAFailure() {
        XCTAssertThrowsError(try GoogleAccountResults.combine([
            GoogleAccountResult(account: "work", result: .failure(Offline()), fallback: ["old"]),
            GoogleAccountResult<String>(account: "personal", result: .failure(Offline()), fallback: [])
        ])) { error in
            XCTAssertTrue(error is Offline)
        }
    }

    func testWhenAllFailAConnectionProblemIsReportedOverOneAccountsSignIn() {
        XCTAssertThrowsError(try GoogleAccountResults.combine([
            GoogleAccountResult<String>(account: "work", result: .failure(AuthError.notSignedIn), fallback: []),
            GoogleAccountResult<String>(account: "personal", result: .failure(Offline()), fallback: [])
        ])) { error in
            XCTAssertTrue(error is Offline)
        }
    }

    func testEveryAccountNeedingSignInReportsSignIn() {
        XCTAssertThrowsError(try GoogleAccountResults.combine([
            GoogleAccountResult<String>(account: "work", result: .failure(AuthError.notSignedIn), fallback: []),
            GoogleAccountResult<String>(
                account: "personal",
                result: .failure(GoogleCalendarError.unauthorized(URL(string: "https://example.com")!)),
                fallback: []
            )
        ])) { error in
            XCTAssertTrue(GoogleAccountErrorPolicy.requiresReauthorization(error))
        }
    }

    func testNoAccountsIsAnEmptySuccess() throws {
        let combined = try GoogleAccountResults.combine([GoogleAccountResult<String>]())
        XCTAssertTrue(combined.values.isEmpty)
    }

    func testOnlySignInErrorsRequireReauthorization() {
        XCTAssertTrue(GoogleAccountErrorPolicy.requiresReauthorization(AuthError.notSignedIn))
        XCTAssertFalse(GoogleAccountErrorPolicy.requiresReauthorization(
            AuthError.temporarilyUnavailable(underlying: Offline())
        ))
        XCTAssertFalse(GoogleAccountErrorPolicy.requiresReauthorization(
            GoogleCalendarError.httpStatus(500, url: URL(string: "https://example.com")!)
        ))
    }
}
