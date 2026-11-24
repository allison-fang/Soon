//
//  GCEventStore.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 21.11.2021.
//  Copyright © 2021 Andrii Leitsius. All rights reserved.
//

import AppAuthCore
import AppKit
import Defaults
import Foundation

let googleClientNumber = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_CLIENT_NUMBER") as! String
let googleClientSecret = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_CLIENT_SECRET") as! String
let googleAuthKeychainName = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_AUTH_KEYCHAIN_NAME") as! String

extension OIDServiceConfiguration: @unchecked @retroactive Sendable {}

extension OIDAuthState {
    /// token is considered fresh if it expires later than 300 seconds from now
    var isTokenFresh: Bool {
        guard let exp = lastTokenResponse?.accessTokenExpirationDate else { return false }
        return exp > Date().addingTimeInterval(300)
    }

    /// convenience email extraction from ID token
    var userEmail: String? {
        lastTokenResponse?.idToken.flatMap(GoogleIDToken.email(from:))
    }
}

/// Owns one interactive AppAuth attempt and guarantees its awaiting caller is
/// released when a newer attempt supersedes it. Keep the session and its
/// completion together so an old callback cannot clear the new session.
@MainActor
final class GoogleAuthorizationFlowSlot {
    private(set) var generation = 0
    private(set) var session: OIDExternalUserAgentSession?
    private var finishWait: ((Result<Void, Error>) -> Void)?

    func begin() -> Int {
        cancel()
        return generation
    }

    func isCurrent(_ attempt: Int) -> Bool { attempt == generation }

    func isPending(_ attempt: Int) -> Bool {
        isCurrent(attempt) && finishWait != nil
    }

    func register(_ attempt: Int, finish: @escaping (Result<Void, Error>) -> Void) {
        guard isCurrent(attempt) else {
            finish(.failure(AuthError.cancelled))
            return
        }
        finishWait = finish
    }

    func setSession(_ session: OIDExternalUserAgentSession?, for attempt: Int) {
        guard isCurrent(attempt) else {
            session?.cancel()
            return
        }
        // AppAuth could invoke the completion synchronously before returning
        // the session. A completed *current* attempt needs no cancellation.
        guard isPending(attempt) else { return }
        self.session = session
    }

    func finish(_ attempt: Int, result: Result<Void, Error>) {
        guard isPending(attempt) else { return }
        let completion = finishWait
        finishWait = nil
        session = nil
        completion?(result)
    }

    func cancel() {
        generation += 1
        let completion = finishWait
        let previousSession = session
        finishWait = nil
        session = nil
        // Settle first; AppAuth may synchronously call back from cancel().
        completion?(.failure(AuthError.cancelled))
        previousSession?.cancel()
    }
}

// MARK: - GCEventStore
/// Google Calendar as one provider over every connected Google account.
@MainActor
final class GCEventStore: NSObject,
                           MultiAccountEventStore,
                           @preconcurrency OIDExternalUserAgent {

    // MARK: Static constants
    private static let kIssuer       = "https://accounts.google.com"
    private static let kClientID     = "\(googleClientNumber).apps.googleusercontent.com"
    // iOS-type OAuth clients are public and have no secret; Validate xcconfig rejects blanks, so NONE means none
    private static let kClientSecret: String? = ["", "NONE"].contains(googleClientSecret) ? nil : googleClientSecret
    private static let kRedirectURI  = "com.googleusercontent.apps.\(googleClientNumber):/oauthredirect"
    #if DEBUG
        // The Debug build must never read, move or delete the installed
        // release app's saved Google logins.
        private static let kKeychainName = googleAuthKeychainName + ".debug"
    #else
        private static let kKeychainName = googleAuthKeychainName
    #endif

    // MARK: Stored properties
    @MainActor var currentAuthorizationFlow: OIDExternalUserAgentSession? {
        authorizationFlow.session
    }
    private let authorizationFlow = GoogleAuthorizationFlowSlot()
    private let credentials: GoogleCredentialStore
    private let accountsReader = GoogleCalendarAccountsReader()
    /// One per connected account, ordered by email.
    private var sessions: [GoogleAccountSession] = []

    // Shared URLSession to leverage connection reuse
    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.httpMaximumConnectionsPerHost = 6
        // Every request must fail within a bounded time so the next refresh
        // cycle can retry. `waitsForConnectivity` suppresses
        // `timeoutIntervalForRequest` entirely and lets a request issued while
        // offline (wake from sleep before Wi-Fi/VPN is up) park for
        // `timeoutIntervalForResource` — seven days by default. That is not a
        // slow refresh, it is a refresh that never reports back, which leaves
        // the menu bar showing yesterday's events indefinitely.
        cfg.waitsForConnectivity          = false
        cfg.timeoutIntervalForRequest     = 30
        cfg.timeoutIntervalForResource    = 90
        return URLSession(configuration: cfg)
    }()

    // Singleton
    static let shared = GCEventStore()
    private override init() {
        credentials = GoogleKeychainCredentialStore(legacyService: Self.kKeychainName)
        super.init()
        GoogleLegacyCredentialMigration.migrate(store: credentials) { data in
            guard let state = Self.unarchive(data) else { return nil }
            return state.userEmail.map(GoogleAccountKey.make(email:)) ?? GoogleAccountKey.placeholder()
        }
        sessions = credentials.accountKeys().map { key in
            // An unreadable login stays listed as needing reconnect, so the
            // user can still see and remove it.
            makeSession(key: key, state: credentials.load(account: key).flatMap(Self.unarchive))
        }
        sortSessions()
        accountsReader.onEmailDiscovered = { [weak self] key, email in
            self?.adoptEmail(email, forAccount: key)
        }
    }

    // MARK: Public API

    var isAuthorized: Bool { sessions.contains { $0.isAuthorized } }

    var accounts: [ProviderAccountHealth] {
        sessions.map { session in
            let status: ProviderAccountHealth.Status = session.hasReusableSession
                ? accountsReader.statuses[session.key] ?? .connected
                : .authRequired
            return ProviderAccountHealth(id: session.key, email: session.email, status: status)
        }
    }

    /// Selecting Google as the source: connects a first account, or keeps the
    /// existing ones when any of them can still refresh on its own.
    func signIn(forcePrompt: Bool = false) async throws {
        if sessions.contains(where: { Self.shouldSkipSignIn(forcePrompt: forcePrompt, state: $0.authState) }) {
            return
        }
        try await authorize(prompt: forcePrompt ? "consent" : "select_account", loginHint: nil, replacing: nil)
    }

    func addAccount() async throws {
        // Google's account chooser, so a second account can be picked even
        // while the browser is signed in to the first one.
        try await authorize(prompt: "select_account", loginHint: nil, replacing: nil)
    }

    func reconnectAccount(_ id: String) async throws {
        let email = sessions.first { $0.key == id }?.email
        try await authorize(prompt: email == nil ? "select_account" : nil, loginHint: email, replacing: id)
    }

    func removeAccount(_ id: String) -> CalendarAccountRemoval {
        guard let session = sessions.first(where: { $0.key == id }) else {
            return CalendarAccountRemoval(calendarIDs: [], orphanedCalendarIDs: [], revokeAccess: {})
        }
        let tokens = session.tokens
        // Clear the local login before any network suspension. Revocation can
        // take arbitrarily long; a newer sign-in to the same account may finish
        // meanwhile, and a late removal must never clear it.
        session.retire()
        sessions.removeAll { $0 === session }
        credentials.delete(account: id)
        let forgotten = accountsReader.forget(id)
        return CalendarAccountRemoval(
            calendarIDs: forgotten.calendarIDs,
            orphanedCalendarIDs: forgotten.orphanedCalendarIDs,
            revokeAccess: {
                await Self.revokeTokensAfterClearingSession(
                    accessToken: tokens.access,
                    refreshToken: tokens.refresh,
                    clearSession: {},
                    revoke: { token in try? await Self.revoke(token: token) }
                )
            }
        )
    }

    /// Disconnects every account.
    func signOut() async {
        cancelPendingOperations()
        let removals = sessions.map { removeAccount($0.key) }
        for removal in removals {
            await removal.revokeAccess()
        }
    }

    private func authorize(prompt: String?, loginHint: String?, replacing replacedKey: String?) async throws {
        var state = try await performAuthorization(prompt: prompt, loginHint: loginHint)

        // Google only issues a refresh token when the user actually walks
        // through the consent screen. An account that still holds a grant from
        // a previous install authorizes silently and returns none, which leaves
        // `hasReusableSession` false forever: no unattended refresh can run.
        // Re-run the flow once demanding consent so the refresh token comes back.
        if state.refreshToken == nil {
            MeetingBarLogger.calendar.warning(
                "Google authorization returned no refresh token; retrying with forced consent"
            )
            state = try await performAuthorization(prompt: "consent", loginHint: state.userEmail ?? loginHint)
        }
        install(state, replacing: replacedKey)
    }

    private func performAuthorization(prompt: String?, loginHint: String?) async throws -> OIDAuthState {
        // Placeholder GOOGLE_CLIENT_NUMBER (local builds) yields an invalid redirect URL
        guard let redirectURL = URL(string: Self.kRedirectURI) else {
            MeetingBarLogger.calendar.error("Google OAuth client is not configured in this build")
            throw NSError(domain: "GoogleSignIn", code: -2, userInfo: [
                NSLocalizedDescriptionKey: "Google sign-in is not configured in this build (GOOGLE_CLIENT_NUMBER)."
            ])
        }

        // This also completes the previous sign-in awaiter if it was still
        // waiting for a browser callback.
        let generation = authorizationFlow.begin()

        // discover configuration for Google issuer
        let config = try await withCheckedThrowingContinuation { cont in
            OIDAuthorizationService.discoverConfiguration(forIssuer: URL(string: Self.kIssuer)!) { cfg, err in
                if let cfg { cont.resume(returning: cfg) } else { cont.resume(throwing: err ?? NSError(domain: "GoogleSignIn", code: -1)) }
            }
        }

        // Discovery is asynchronous. A newer provider selection may have
        // cancelled this attempt before AppAuth even presents its browser.
        guard authorizationFlow.isCurrent(generation), !Task.isCancelled else {
            throw AuthError.cancelled
        }

        // request scopes we need
        let scopes = [
            "email",
            "https://www.googleapis.com/auth/calendar.calendarlist.readonly",
            "https://www.googleapis.com/auth/calendar.events.readonly"
        ]

        // additional parameters to be sure we get refresh_token
        var extra = [
            "access_type": "offline"
        ]
        extra["prompt"] = prompt
        extra["login_hint"] = loginHint

        let request = OIDAuthorizationRequest(
            configuration: config,
            clientId: Self.kClientID,
            clientSecret: Self.kClientSecret,
            scopes: scopes,
            redirectURL: redirectURL,
            responseType: OIDResponseTypeCode,
            additionalParameters: extra
        )

        var authorized: OIDAuthState?
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            authorizationFlow.register(generation) { result in
                cont.resume(with: result)
            }
            let session = OIDAuthState.authState(
                byPresenting: request, externalUserAgent: self
            ) { [weak self] state, error in
                guard let self, self.authorizationFlow.isPending(generation) else { return }
                do {
                    try Self.acceptAuthorizationResult(
                        issuedGeneration: generation,
                        currentGeneration: self.authorizationFlow.generation,
                        state: state,
                        error: error
                    ) { accepted in
                        authorized = accepted
                    }
                    self.authorizationFlow.finish(generation, result: .success(()))
                } catch {
                    self.authorizationFlow.finish(generation, result: .failure(error))
                }
            }
            authorizationFlow.setSession(session, for: generation)
        }
        guard let authorized else { throw AuthError.cancelled }
        return authorized
    }

    /// The AppAuth callback must not install a session belonging to a
    /// cancelled/superseded sign-in, even if its browser response arrives late.
    /// This accepts generic state data so the callback ordering is testable
    /// without an actual Google account, browser, or Keychain.
    static func acceptAuthorizationResult<State>(
        issuedGeneration: Int,
        currentGeneration: Int,
        state: State?,
        error: Error?,
        install: (State) -> Void
    ) throws {
        guard issuedGeneration == currentGeneration else {
            throw AuthError.cancelled
        }
        guard let state else { throw authorizationError(error) }
        install(state)
    }

    private static func authorizationError(_ error: Error?) -> Error {
        guard let error else {
            return NSError(domain: "GoogleSignIn", code: 1)
        }

        let nsError = error as NSError
        let cancellationCodes = [-3, -4]
        if nsError.domain == OIDGeneralErrorDomain,
           cancellationCodes.contains(nsError.code) {
            return AuthError.cancelled
        }
        return error
    }

    /// Clear the *old* local session before any network suspension. Revocation
    /// can take arbitrarily long; a newer provider selection may sign in while
    /// the old token request is still pending. A late sign-out must never clear
    /// that newer session (or its persisted state).
    static func revokeTokensAfterClearingSession(
        accessToken: String?,
        refreshToken: String?,
        clearSession: () -> Void,
        revoke: @escaping @Sendable (String) async -> Void
    ) async {
        clearSession()
        await withTaskGroup(of: Void.self) { group in
            if let accessToken { group.addTask { await revoke(accessToken) } }
            if let refreshToken { group.addTask { await revoke(refreshToken) } }
        }
    }

    func cancelPendingOperations() {
        authorizationFlow.cancel()
        sessions.forEach { $0.cancelPendingRefresh() }
    }

    func refreshSources() async {}

    func fetchAllCalendars() async throws -> [MBCalendar] {
        try requireAccount()
        return try await accountsReader.fetchCalendars(from: readerAccounts())
    }

    static func eventsURL(calendarID: String, timeMin: String, timeMax: String) throws -> URL {
        // Calendar IDs can contain `#`, `@`, `+`, and group-address punctuation.
        // Path interpolation without escaping breaks for those calendars
        // (Google returns 404). Build the path via `URLComponents.path` so
        // encoding happens once, correctly.
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = "www.googleapis.com"
        comps.path = "/calendar/v3/calendars/\(calendarID)/events"
        comps.queryItems = [
            .init(name: "singleEvents", value: "true"),
            .init(name: "orderBy", value: "startTime"),
            .init(name: "eventTypes", value: "default"),
            .init(name: "timeMax", value: timeMax),
            .init(name: "timeMin", value: timeMin)
        ]
        guard let url = comps.url else {
            throw URLError(.badURL)
        }

        return url
    }

    func fetchEventsForDateRange(
        for calendars: [MBCalendar],
        from: Date,
        to: Date
    ) async throws -> [MBEvent] {
        try requireAccount()
        return try await accountsReader.fetchEvents(from: readerAccounts(), for: calendars, from: from, to: to)
    }

    // MARK: - Private helpers

    /// Fetches always originate from an unattended refresh cycle (timer, wake,
    /// day change) rather than from a user gesture, so this deliberately never
    /// starts an interactive sign-in. Doing so from a background refresh opened
    /// a browser tab nobody was watching and then awaited its callback forever.
    /// Interactive authorization belongs to the explicit sign-in, add and
    /// reconnect entry points; here we surface "reconnect required".
    private func requireAccount() throws {
        guard !sessions.isEmpty else { throw AuthError.notSignedIn }
    }

    private func readerAccounts() -> [GoogleCalendarAccountsReader.Account] {
        sessions.map { session in
            GoogleCalendarAccountsReader.Account(
                key: session.key,
                email: session.email,
                isUsable: session.hasReusableSession,
                reader: GoogleCalendarDataReader(userEmail: session.email) { [weak session] url, calendarID in
                    guard let session else { throw AuthError.notSignedIn }
                    return try await Self.fetchJSON(url, calendarID: calendarID, session: session)
                },
                isCurrent: { [weak self, weak session] in
                    guard let self, let session else { return false }
                    return self.sessions.contains { $0 === session }
                }
            )
        }
    }

    nonisolated static func hasReusableSession(_ state: OIDAuthState?) -> Bool {
        state?.isAuthorized == true && state?.refreshToken != nil
    }

    nonisolated static func shouldSkipSignIn(
        forcePrompt: Bool,
        state: OIDAuthState?
    ) -> Bool {
        !forcePrompt && hasReusableSession(state)
    }

    /// Resolves the AppAuth refresh callback without letting a stale token mask an error.
    /// AppAuth can return the previous access token alongside a transient refresh error,
    /// so the error must always win.
    nonisolated static func resolveTokenRefresh(
        accessToken: String?,
        error: Error?
    ) throws -> String {
        if let error {
            let nsError = error as NSError
            if nsError.domain == OIDOAuthTokenErrorDomain {
                throw AuthError.notSignedIn
            }
            throw AuthError.temporarilyUnavailable(underlying: error)
        }

        guard let accessToken else {
            throw AuthError.refreshFailed
        }
        return accessToken
    }

    // MARK: Accounts and saved logins

    private func makeSession(key: String, state: OIDAuthState?) -> GoogleAccountSession {
        GoogleAccountSession(
            key: key,
            state: state,
            persist: { [weak self] session in self?.save(session) },
            restore: { [weak self] key in
                self?.credentials.load(account: key).flatMap(Self.unarchive)
            }
        )
    }

    private func install(_ state: OIDAuthState, replacing replacedKey: String?) {
        let email = state.userEmail
        let key = email.map(GoogleAccountKey.make(email:)) ?? replacedKey ?? GoogleAccountKey.placeholder()
        // A login saved before its email was known is most likely the account
        // being reconnected now, so it is replaced rather than kept twice.
        let replacedPlaceholder = replacedKey.flatMap { GoogleAccountKey.isPlaceholder($0) ? $0 : nil }
        // Signing in to an already connected account replaces its login. The
        // old tokens are not revoked: Google can hand back the identical
        // refresh token, and revoking it would end the new login too.
        for old in sessions where old.key == key || old.key == replacedPlaceholder {
            old.retire()
            if old.key != key {
                credentials.delete(account: old.key)
                _ = accountsReader.forget(old.key)
            }
        }
        sessions.removeAll { $0.key == key || $0.key == replacedPlaceholder }

        let session = makeSession(key: key, state: state)
        save(session)
        sessions.append(session)
        sortSessions()
        accountsReader.resetStatus(key)
        AppMessageCenter.shared.post(.googleAccountConnected(email: email ?? ""))
    }

    /// The login moved over from an earlier version may not say which account
    /// it is. Its primary calendar does, so the login is re-saved under it.
    private func adoptEmail(_ email: String, forAccount key: String) -> String? {
        guard let session = sessions.first(where: { $0.key == key }) else { return nil }
        let newKey = GoogleAccountKey.make(email: email)
        if sessions.contains(where: { $0.key == newKey && $0 !== session }) {
            // The same account is connected twice. Keep the login that knows
            // its email; never revoke, since both share one Google grant.
            session.retire()
            sessions.removeAll { $0 === session }
            credentials.delete(account: key)
            return nil
        }
        guard let data = Self.archive(session.authState),
              credentials.save(data, account: newKey) else { return key }
        session.adoptEmail(email)
        credentials.delete(account: key)
        sortSessions()
        return newKey
    }

    private func sortSessions() {
        sessions.sort { lhs, rhs in
            (lhs.email ?? lhs.key).localizedStandardCompare(rhs.email ?? rhs.key) == .orderedAscending
        }
    }

    private func save(_ session: GoogleAccountSession) {
        guard let data = Self.archive(session.authState) else { return }
        credentials.save(data, account: session.key)
    }

    private static func archive(_ state: OIDAuthState?) -> Data? {
        guard let state else { return nil }
        do {
            return try NSKeyedArchiver.archivedData(withRootObject: state, requiringSecureCoding: true)
        } catch {
            let errorDescription = String(describing: error)
            MeetingBarLogger.calendar.error(
                "Could not archive Google auth state: \(errorDescription, privacy: .private)"
            )
            return nil
        }
    }

    private static func unarchive(_ data: Data) -> OIDAuthState? {
        do {
            return try NSKeyedUnarchiver.unarchivedObject(ofClass: OIDAuthState.self, from: data)
        } catch {
            let errorDescription = String(describing: error)
            MeetingBarLogger.calendar.error(
                "Could not restore Google auth state: \(errorDescription, privacy: .private)"
            )
            return nil
        }
    }

    // MARK: Networking helper
    private static func fetchJSON(
        _ url: URL,
        calendarID: String?,
        session account: GoogleAccountSession
    ) async throws -> [[String: Any]] {
        let session = Self.session
        let client = GoogleCalendarHTTPClient(
            transport: { request in try await session.data(for: request) },
            accessToken: { forceRefresh in
                try await account.validAccessToken(forceRefresh: forceRefresh)
            }
        )
        return try await client.fetchJSON(url, calendarID: calendarID)
    }

    private static func revoke(token: String) async throws {
        var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/revoke")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data("token=\(token)".utf8)

        let (_, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw NSError(domain: "GoogleRevoke", code: (resp as? HTTPURLResponse)?.statusCode ?? -1)
        }
    }

    // MARK: - OIDExternalUserAgent
    func present(_ request: OIDExternalUserAgentRequest, session _: OIDExternalUserAgentSession) -> Bool {
        if let url = request.externalUserAgentRequestURL(), NSWorkspace.shared.open(url) {
            return true
        }
        return false
    }

    func dismiss(animated _: Bool, completion: @escaping () -> Void) { completion() }

    // MARK: - Google JSON ➜ MBEvent converter
    enum GCParser {
        // swiftlint:disable:next cyclomatic_complexity
        static func event(from item: [String: Any],
                          calendar: MBCalendar) -> MBEvent? {
            guard let eventID = item["id"] as? String else {
                MeetingBarLogger.calendar.warning(
                    "Skipping Google Calendar event without a string id"
                )
                return nil
            }

            let formatter = ISO8601DateFormatter()
            let lastModifiedDate = formatter.date(from: item["updated"] as? String ?? "")
            let title = item["summary"] as? String
            var status: MBEventStatus
            switch item["status"] as? String {
            case "confirmed":
                status = .confirmed
            case "tentative":
                status = .tentative
            case "cancelled":
                status = .canceled
            default:
                status = .none
            }

            let notes = item["description"] as? String
            let location = item["location"] as? String

            // Google Calendar exposes the meeting URL through structured
            // conferenceData. Surface it as `conferenceURL` so the link
            // detector can score it ahead of any URL accidentally pasted
            // into notes (#847). The plain `url` field remains nil for
            // Google events — Google Calendar has no per-event "user URL"
            // equivalent of EKEvent.url.
            var conferenceURL: URL?
            if let conferenceData = item["conferenceData"] as? [String: Any],
               let entryPoints = conferenceData["entryPoints"] as? [[String: Any]],
               let videoEntryPoint = entryPoints.first(where: { $0["entryPointType"] as? String == "video" }) {
                conferenceURL = (videoEntryPoint["uri"] as? String).flatMap(URL.init(string:))
            }

            let organizerRaw = item["organizer"] as? [String: Any]
            let organizer = MBEventOrganizer(email: organizerRaw?["email"] as? String, name: organizerRaw?["name"] as? String)

            var attendees: [MBEventAttendee] = []
            let rawAttendees = item["attendees"] as? [[String: Any]] ?? []
            for jsonAttendee in rawAttendees {
                let email = jsonAttendee["email"] as? String
                let name = jsonAttendee["displayName"] as? String
                let optional = jsonAttendee["optional"] as? Bool ?? false
                let isCurrentUser = jsonAttendee["self"] as? Bool ?? false

                var attendeeStatus: MBEventAttendeeStatus
                switch jsonAttendee["responseStatus"] as? String {
                case "accepted":
                    attendeeStatus = .accepted
                case "declined":
                    attendeeStatus = .declined
                case "tentative":
                    attendeeStatus = .tentative
                case "needsAction":
                    attendeeStatus = .pending
                default:
                    attendeeStatus = .unknown
                }
                let attendee = MBEventAttendee(email: email, name: name, status: attendeeStatus, optional: optional, isCurrentUser: isCurrentUser)
                attendees.append(attendee)
            }

            var startDate: Date
            var endDate: Date
            var isAllDay: Bool

            guard let itemStart = item["start"] as? [String: String],
                  let itemEnd = item["end"] as? [String: String] else {
                MeetingBarLogger.calendar.warning(
                    "Skipping Google event \(eventID, privacy: .private) without valid start/end dictionaries"
                )
                return nil
            }

            if let startDateTime = itemStart["dateTime"], let endDateTime = itemEnd["dateTime"] {
                let formatter = ISO8601DateFormatter()
                guard let parsedStartDate = formatter.date(from: startDateTime),
                      let parsedEndDate = formatter.date(from: endDateTime) else {
                    MeetingBarLogger.calendar.warning(
                        "Skipping Google event \(eventID, privacy: .private) with invalid dateTime values"
                    )
                    return nil
                }
                startDate = parsedStartDate
                endDate = parsedEndDate
                isAllDay = false
            } else {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                guard let startDateString = itemStart["date"],
                      let endDateString = itemEnd["date"],
                      let parsedStartDate = formatter.date(from: startDateString),
                      let parsedEndDate = formatter.date(from: endDateString) else {
                    MeetingBarLogger.calendar.warning(
                        "Skipping Google event \(eventID, privacy: .private) with invalid all-day date values"
                    )
                    return nil
                }
                startDate = parsedStartDate
                endDate = parsedEndDate
                isAllDay = true
            }

            let recurrent = (item["recurringEventId"] != nil) ? true : false

            // Web link to the event in Google Calendar; used for "Open in
            // Calendar" since `ical://ekevent/<google-id>` is not valid.
            let calendarOpenURL = (item["htmlLink"] as? String).flatMap(URL.init(string:))

            return MBEvent(
                id: eventID,
                lastModifiedDate: lastModifiedDate,
                title: title,
                status: status,
                notes: notes,
                location: location,
                url: nil,
                conferenceURL: conferenceURL,
                calendarOpenURL: calendarOpenURL,
                organizer: organizer,
                attendees: attendees,
                startDate: startDate,
                endDate: endDate,
                isAllDay: isAllDay,
                recurrent: recurrent,
                calendar: calendar,
                customRegexes: Defaults[.customRegexes]
            )
        }
    }
}

/// Saved Google logins in the Keychain: one item per account, labeled by the
/// account's email, beside the single item earlier versions used.
@MainActor
struct GoogleKeychainCredentialStore: GoogleCredentialStore {
    let legacyService: String
    private var accountsService: String { legacyService + ".accounts" }

    func accountKeys() -> [String] { Keychain.accounts(for: accountsService) }
    func load(account: String) -> Data? { Keychain.load(for: accountsService, account: account) }
    @discardableResult
    func save(_ data: Data, account: String) -> Bool {
        Keychain.save(data: data, for: accountsService, account: account)
    }
    func delete(account: String) { Keychain.delete(for: accountsService, account: account) }
    func loadLegacy() -> Data? { Keychain.load(for: legacyService) }
    func deleteLegacy() { Keychain.delete(for: legacyService) }
}
