//
//  GoogleCalendarAccountsReader.swift
//  MeetingBar
//

import Foundation

/// Calendars and events across every connected Google account.
///
/// Merges calendars that several accounts can see, sends each calendar's
/// event request through the account that listed it, and keeps each account's
/// last good data so one failing account does not blank the others.
/// `GCEventStore` owns one instance and supplies the accounts on each call.
@MainActor
final class GoogleCalendarAccountsReader {
    struct Account {
        let key: String
        let email: String?
        /// False for a login without a refresh token: it cannot refresh
        /// unattended, so it is reported as needing reconnect without a request.
        let isUsable: Bool
        let reader: GoogleCalendarDataReader
        /// False once this login was removed or replaced by a reconnect.
        let isCurrent: @MainActor () -> Bool
    }

    /// Called when an account whose email was unknown turns out to have one.
    /// Returns the account's new key, or `nil` if the account is a duplicate
    /// of one already connected and was dropped.
    var onEmailDiscovered: (@MainActor (_ key: String, _ email: String) -> String?)?

    private(set) var statuses: [String: ProviderAccountHealth.Status] = [:]
    private var calendarCache: [String: [GoogleCalendarListEntry]] = [:]
    private var eventCache: [String: [MBEvent]] = [:]
    /// Calendar ID -> the account whose copy won the merge.
    private var routes: [String: String] = [:]

    func fetchCalendars(from accounts: [Account]) async throws -> [MBCalendar] {
        let results = await concurrently(accounts) { account in
            guard account.isUsable else { throw AuthError.notSignedIn }
            return try await account.reader.fetchCalendarEntries()
        }

        var perAccount: [GoogleAccountResult<GoogleCalendarListEntry>] = []
        for (account, result) in zip(accounts, results) where account.isCurrent() {
            var key = account.key
            switch result {
            case .success(var entries):
                if account.email == nil,
                   let primary = entries.first(where: \.isPrimary),
                   let email = GoogleAccountKey.email(fromPrimaryCalendarID: primary.calendar.id) {
                    guard let newKey = onEmailDiscovered?(key, email) else { continue }
                    rename(key, to: newKey)
                    key = newKey
                    entries = entries.map { $0.withAccountEmail(email) }
                }
                calendarCache[key] = entries
                statuses[key] = .connected
                perAccount.append(.init(account: key, result: .success(entries), fallback: []))
            case .failure(let error):
                statuses[key] = Self.status(for: error)
                perAccount.append(.init(
                    account: key,
                    result: .failure(error),
                    fallback: calendarCache[key] ?? []
                ))
            }
        }

        let combined = try GoogleAccountResults.combine(perAccount)
        let keyed = combined.valuesByAccount.map { group in
            group.values.map { (account: group.account, entry: $0) }
        }
        let merged = GoogleCalendarMergePolicy.merge(
            keyed,
            id: \.entry.calendar.id,
            accessRole: \.entry.accessRole
        )
        routes = Dictionary(merged.map { ($0.entry.calendar.id, $0.account) }) { first, _ in first }
        return merged.map(\.entry.calendar)
    }

    func fetchEvents(
        from accounts: [Account],
        for calendars: [MBCalendar],
        from start: Date,
        to end: Date
    ) async throws -> [MBEvent] {
        let requestedIDs = Set(calendars.map(\.id))
        let work: [(account: Account, calendars: [MBCalendar])] = accounts.compactMap { account in
            let owned = calendars.filter { owner(of: $0) == account.key }
            return owned.isEmpty ? nil : (account, owned)
        }

        let results = await concurrently(work) { item in
            guard item.account.isUsable else { throw AuthError.notSignedIn }
            return try await item.account.reader.fetchEvents(for: item.calendars, from: start, to: end)
        }

        var perAccount: [GoogleAccountResult<MBEvent>] = []
        for (item, result) in zip(work, results) where item.account.isCurrent() {
            let key = item.account.key
            switch result {
            case .success(let events):
                eventCache[key] = events
                statuses[key] = .connected
                perAccount.append(.init(account: key, result: .success(events), fallback: []))
            case .failure(let error):
                statuses[key] = Self.status(for: error)
                let lastKnown = (eventCache[key] ?? []).filter {
                    requestedIDs.contains($0.calendar.id) && $0.endDate > start && $0.startDate < end
                }
                perAccount.append(.init(account: key, result: .failure(error), fallback: lastKnown))
            }
        }

        return try GoogleAccountResults.combine(perAccount).values
            .deduplicatedPreferringResolvedAttendee()
    }

    /// Drops everything kept for a removed account.
    func forget(_ key: String) -> (calendarIDs: Set<String>, orphanedCalendarIDs: Set<String>) {
        let owned = Set(routes.filter { $0.value == key }.keys)
        let stillAvailable = Set(
            calendarCache.filter { $0.key != key }.values.flatMap { $0.map(\.calendar.id) }
        )
        let listed = Set((calendarCache[key] ?? []).map(\.calendar.id))
        calendarCache[key] = nil
        eventCache[key] = nil
        statuses[key] = nil
        routes = routes.filter { $0.value != key }
        return (owned, owned.union(listed).subtracting(stillAvailable))
    }

    /// A reconnect starts the account's status afresh; its last good data stays
    /// until the next refresh replaces it.
    func resetStatus(_ key: String) {
        statuses[key] = nil
    }

    private func rename(_ oldKey: String, to newKey: String) {
        guard oldKey != newKey else { return }
        calendarCache[newKey] = calendarCache.removeValue(forKey: oldKey)
        eventCache[newKey] = eventCache.removeValue(forKey: oldKey)
        statuses[newKey] = statuses.removeValue(forKey: oldKey)
        routes = routes.mapValues { $0 == oldKey ? newKey : $0 }
    }

    private func owner(of calendar: MBCalendar) -> String? {
        if let routed = routes[calendar.id] { return routed }
        return calendar.email.map(GoogleAccountKey.make(email:))
    }

    static func status(for error: Error) -> ProviderAccountHealth.Status {
        if GoogleAccountErrorPolicy.requiresReauthorization(error) { return .authRequired }
        return .failed(error.localizedDescription)
    }

    /// Runs one operation per item at the same time, so a slow account cannot
    /// hold up the others, and returns the results in item order.
    private func concurrently<Item, Value: Sendable>(
        _ items: [Item],
        _ operation: @escaping @MainActor (Item) async throws -> Value
    ) async -> [Result<Value, Error>] {
        let work = ConcurrentWork(items: items, operation: operation)
        return await withTaskGroup(of: (Int, Result<Value, Error>).self) { group in
            for index in items.indices {
                group.addTask { (index, await work.result(at: index)) }
            }
            var results = [Result<Value, Error>?](repeating: nil, count: items.count)
            for await (index, result) in group {
                results[index] = result
            }
            return results.map { $0 ?? .failure(CancellationError()) }
        }
    }
}

/// Main-actor storage that lets task-group children reach non-Sendable
/// readers without copying them across isolation.
@MainActor
private final class ConcurrentWork<Item, Value: Sendable> {
    let items: [Item]
    let operation: @MainActor (Item) async throws -> Value

    init(items: [Item], operation: @escaping @MainActor (Item) async throws -> Value) {
        self.items = items
        self.operation = operation
    }

    func result(at index: Int) async -> Result<Value, Error> {
        do {
            return .success(try await operation(items[index]))
        } catch {
            return .failure(error)
        }
    }
}
