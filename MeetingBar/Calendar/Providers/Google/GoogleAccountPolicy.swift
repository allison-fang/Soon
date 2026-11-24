//
//  GoogleAccountPolicy.swift
//  MeetingBar
//

import Foundation

/// The label each connected Google account's login is saved under.
enum GoogleAccountKey {
    private static let placeholderPrefix = "unknown-account:"

    static func make(email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// For a login whose email is not known yet. Unique, so two such logins
    /// can never overwrite each other.
    static func placeholder() -> String {
        placeholderPrefix + UUID().uuidString
    }

    static func isPlaceholder(_ key: String) -> Bool {
        key.hasPrefix(placeholderPrefix)
    }

    static func email(for key: String) -> String? {
        isPlaceholder(key) ? nil : key
    }

    /// A Google account's primary calendar ID is the account's email.
    static func email(fromPrimaryCalendarID calendarID: String) -> String? {
        let trimmed = calendarID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("@"), !trimmed.hasPrefix("@"), !trimmed.hasSuffix("@") else {
            return nil
        }
        return trimmed
    }
}

/// Saved Google logins, one per account.
@MainActor
protocol GoogleCredentialStore {
    func accountKeys() -> [String]
    func load(account: String) -> Data?
    @discardableResult func save(_ data: Data, account: String) -> Bool
    func delete(account: String)
    /// The single login saved by versions before multiple accounts.
    func loadLegacy() -> Data?
    func deleteLegacy()
}

enum GoogleLegacyCredentialMigration {
    /// Moves the pre-multi-account login into the per-account store.
    ///
    /// `accountKey` returns `nil` when the saved data cannot be read. That
    /// login is left exactly where it is: deleting something we failed to
    /// understand would sign the user out for good.
    ///
    /// The old item is deleted only once the copy reads back identically, so
    /// a failed write keeps the user signed in under the old item.
    @MainActor
    @discardableResult
    static func migrate(
        store: GoogleCredentialStore,
        accountKey: (Data) -> String?
    ) -> String? {
        guard let legacy = store.loadLegacy() else { return nil }

        // A previous launch copied it but could not delete the original.
        if let existing = store.accountKeys().first(where: { store.load(account: $0) == legacy }) {
            store.deleteLegacy()
            return existing
        }

        guard let key = accountKey(legacy) else { return nil }
        if store.load(account: key) == nil {
            guard store.save(legacy, account: key), store.load(account: key) == legacy else {
                return nil
            }
        }
        store.deleteLegacy()
        return key
    }
}

enum GoogleCalendarMergePolicy {
    /// How much of a calendar an account can see. A free/busy copy has no
    /// titles or meeting links, so any fuller copy must win over it.
    static func rank(accessRole: String?) -> Int {
        switch accessRole {
        case "owner": 3
        case "writer": 2
        case "reader": 1
        default: 0
        }
    }

    /// One entry per calendar ID across accounts. When several accounts list
    /// the same calendar, the copy with the most access wins; on a tie, the
    /// earlier account does. The winner keeps the position of the first copy.
    static func merge<Entry>(
        _ accounts: [[Entry]],
        id: (Entry) -> String,
        accessRole: (Entry) -> String?
    ) -> [Entry] {
        var merged: [Entry] = []
        var positions: [String: (index: Int, rank: Int)] = [:]
        for entries in accounts {
            for entry in entries {
                let calendarID = id(entry)
                let rank = rank(accessRole: accessRole(entry))
                if let existing = positions[calendarID] {
                    if rank > existing.rank {
                        merged[existing.index] = entry
                        positions[calendarID] = (existing.index, rank)
                    }
                } else {
                    positions[calendarID] = (merged.count, rank)
                    merged.append(entry)
                }
            }
        }
        return merged
    }
}

enum GoogleAccountErrorPolicy {
    /// Only these mean the account itself must be signed in again.
    static func requiresReauthorization(_ error: Error) -> Bool {
        if let authError = error as? AuthError, case .notSignedIn = authError { return true }
        if let googleError = error as? GoogleCalendarError, case .unauthorized = googleError {
            return true
        }
        return false
    }
}

/// One account's part of a refresh.
struct GoogleAccountResult<Value> {
    let account: String
    let result: Result<[Value], Error>
    /// What to show for this account when its fetch fails: its last good data.
    let fallback: [Value]
}

enum GoogleAccountResults {
    struct Combined<Value> {
        /// What to show for each account, in the order the results came in.
        let valuesByAccount: [(account: String, values: [Value])]
        let failures: [(account: String, error: Error)]

        var values: [Value] { valuesByAccount.flatMap(\.values) }
    }

    /// Joins per-account results so one failing account cannot blank the
    /// others. Only when every account fails is the refresh a failure, which
    /// keeps the whole-provider stale and reconnect states working as before.
    static func combine<Value>(_ results: [GoogleAccountResult<Value>]) throws -> Combined<Value> {
        var valuesByAccount: [(account: String, values: [Value])] = []
        var failures: [(account: String, error: Error)] = []
        for item in results {
            switch item.result {
            case .success(let fetched):
                valuesByAccount.append((item.account, fetched))
            case .failure(let error):
                failures.append((item.account, error))
                valuesByAccount.append((item.account, item.fallback))
            }
        }

        if !results.isEmpty, failures.count == results.count {
            // A reachable-but-failing account is the more useful report: an
            // auth error here would push every account into "reconnect".
            let reported = failures.first { !GoogleAccountErrorPolicy.requiresReauthorization($0.error) }
                ?? failures[0]
            throw reported.error
        }
        return Combined(valuesByAccount: valuesByAccount, failures: failures)
    }
}
