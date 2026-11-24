//
//  EventStore.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 28.03.2022.
//  Copyright © 2022 Andrii Leitsius. All rights reserved.
//

import AppKit
import Defaults

public enum EventStoreProvider: String, Defaults.Serializable, Codable, Sendable {
    case macOSEventKit = "MacOS Calendar App"
    case googleCalendar = "Google Calendar API"
}

/// Base contract for a calendar provider. Not main-actor isolated so providers
/// can run fetch and enumeration work off the main thread.
public protocol EventStore: AnyObject, Sendable {
    func refreshSources() async
    func fetchAllCalendars() async throws -> [MBCalendar]
    func fetchEventsForDateRange(for calendars: [MBCalendar], from: Date, to: Date) async throws
        -> [MBEvent]
    @MainActor func cancelPendingOperations()
}

public extension EventStore {
    @MainActor
    func cancelPendingOperations() {}
}

/// Extended contract for providers that require explicit sign-in/sign-out flows
/// (e.g. OAuth-based providers such as Google Calendar).
public protocol AuthenticatedEventStore: EventStore {
    func signIn(forcePrompt: Bool) async throws
    func signOut() async
}

/// What removing one account changes in the calendar list.
public struct CalendarAccountRemoval: Sendable {
    /// Calendars the account supplied in the latest calendar list.
    public let calendarIDs: Set<String>
    /// Of those, the ones no remaining account can supply.
    public let orphanedCalendarIDs: Set<String>
    /// Tells the provider the account is disconnected. The account is already
    /// gone locally before this runs, so a slow network cannot delay that.
    public let revokeAccess: @Sendable () async -> Void
}

/// Providers that hold several signed-in accounts at once (Google Calendar).
public protocol MultiAccountEventStore: AuthenticatedEventStore {
    @MainActor var accounts: [ProviderAccountHealth] { get }
    @MainActor func addAccount() async throws
    @MainActor func reconnectAccount(_ id: String) async throws
    @MainActor func removeAccount(_ id: String) -> CalendarAccountRemoval
}
