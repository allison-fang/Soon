//
//  GoogleAccountSession.swift
//  MeetingBar
//

import AppAuthCore
import Foundation

/// One connected Google account: its AppAuth state, token refresh and saved
/// login. `GCEventStore` owns one per account; a reconnect installs a new
/// session rather than mutating this one, so work started for the old login
/// can recognise that it is no longer current.
@MainActor
final class GoogleAccountSession: NSObject,
                                  @preconcurrency OIDAuthStateChangeDelegate,
                                  @preconcurrency OIDAuthStateErrorDelegate {
    typealias Persist = @MainActor (GoogleAccountSession) -> Void
    typealias Restore = @MainActor (_ key: String) -> OIDAuthState?

    private(set) var key: String
    private(set) var email: String?

    private let persist: Persist
    private let restore: Restore

    private(set) var authState: OIDAuthState? {
        didSet {
            authState?.stateChangeDelegate = self
            authState?.errorDelegate       = self
            // Only save here. Dropping the in-memory state never deletes the
            // saved login — `discardStuckAuthState` relies on that.
            if authState != nil { persist(self) }
        }
    }

    /// The refresh currently occupying the slot, and what it is refreshing.
    ///
    /// Two things have to be distinguished, and neither implies the other.
    /// `state` identity says *which login*: a stuck-state replacement installs
    /// a new `OIDAuthState`, and a refresh started for the previous one can
    /// only ever return the previous object's token. `generation` says *which
    /// attempt*: a forced refresh takes the slot from an ordinary refresh of
    /// the same state, and the superseded task must not then clear or discard
    /// on behalf of its replacement.
    private struct PendingRefresh {
        let task: Task<String, Error>
        let state: OIDAuthState
        let generation: Int
    }

    private var pendingRefresh: PendingRefresh?
    private var refreshGeneration = 0
    /// Upper bound on one AppAuth token refresh.
    ///
    /// AppAuth issues token requests on `OIDURLSessionProvider.session`, which
    /// defaults to `URLSession.shared` — *not* GCEventStore's hardened session,
    /// so none of its configuration applies to the refresh path. `URLSession`'s
    /// own 60s default request timeout still bounds that call, so this deadline
    /// sits beyond it and fires only when the callback never arrives at all.
    static let tokenRefreshTimeout: TimeInterval = 90

    init(
        key: String,
        state: OIDAuthState?,
        persist: @escaping Persist,
        restore: @escaping Restore
    ) {
        self.key = key
        self.email = GoogleAccountKey.email(for: key)
        self.persist = persist
        self.restore = restore
        self.authState = state
        super.init()
        state?.stateChangeDelegate = self
        state?.errorDelegate = self
    }

    var isAuthorized: Bool { authState?.isAuthorized == true }

    var hasReusableSession: Bool { GCEventStore.hasReusableSession(authState) }

    var tokens: (access: String?, refresh: String?) {
        (authState?.lastTokenResponse?.accessToken, authState?.refreshToken)
    }

    /// Renames a login saved before its email was known. The caller moves the
    /// saved item; this only updates what the session reports.
    func adoptEmail(_ email: String) {
        key = GoogleAccountKey.make(email: email)
        self.email = email
    }

    func cancelPendingRefresh() {
        pendingRefresh?.task.cancel()
        pendingRefresh = nil
    }

    /// Stops this session from refreshing or saving anything further.
    func retire() {
        cancelPendingRefresh()
        authState?.stateChangeDelegate = nil
        authState?.errorDelegate = nil
        authState = nil
    }

    func validAccessToken(forceRefresh: Bool = false) async throws -> String {
        guard let state = authState else { throw AuthError.notSignedIn }

        if !forceRefresh,
           state.isTokenFresh,
           let token = state.lastTokenResponse?.accessToken {
            return token
        }

        // Join an in-flight refresh only when it is refreshing this very state.
        // A forced refresh never joins: it exists because the token the pending
        // refresh will return was already rejected.
        if !forceRefresh, let pending = pendingRefresh, pending.state === state {
            return try await pending.task.value
        }

        refreshGeneration += 1
        let generation = refreshGeneration
        let task = Task<String, Error> {
            defer { if pendingRefresh?.generation == generation { pendingRefresh = nil } }
            return try await withCheckedThrowingContinuation { cont in
                // `performAction` owns its URLSession task internally and offers
                // no way to cancel it, and this is an unstructured Task, so
                // cancelling whoever awaits it does not reach in here. A
                // continuation that AppAuth never resumes would therefore
                // outlive every timeout the refresh cycle can apply and strand
                // the serialized pipeline. Settle the wait on our own deadline
                // instead and let a late callback find the resume already claimed.
                let resumeGuard = SingleResumeGuard()
                let deadline = Task {
                    try? await Task.sleep(
                        nanoseconds: UInt64(Self.tokenRefreshTimeout * Double(NSEC_PER_SEC))
                    )
                    guard !Task.isCancelled, resumeGuard.claim() else { return }
                    MeetingBarLogger.calendar.error(
                        "Google token refresh did not return within \(Int(Self.tokenRefreshTimeout))s"
                    )
                    // Only the refresh that still owns the slot may do this. A
                    // superseded ordinary refresh timing out after a forced one
                    // took over would otherwise swap in a stale state while the
                    // forced refresh is still driving the old object — and when
                    // that object later succeeds, `didChange` persists whatever
                    // `authState` now holds, so the fresh token is dropped from
                    // memory and the keychain both.
                    if self.pendingRefresh?.generation == generation, state === self.authState {
                        self.discardStuckAuthState()
                    }
                    cont.resume(
                        throwing: AuthError.temporarilyUnavailable(
                            underlying: URLError(.timedOut)
                        )
                    )
                }

                if forceRefresh { state.setNeedsTokenRefresh() }

                state.performAction { accessToken, _, error in
                    guard resumeGuard.claim() else { return }
                    deadline.cancel()
                    // `error` must be inspected before `accessToken`. When the
                    // token endpoint is unreachable, AppAuth reports the failure
                    // as a transient error but still passes back the *previous*,
                    // already-expired access token. Treating that as a success
                    // sends a known-expired token to Google, which answers 401 →
                    // forced refresh → 401 again → "sign the user out", so a few
                    // seconds without network destroyed the stored refresh token.
                    do {
                        let token = try GCEventStore.resolveTokenRefresh(
                            accessToken: accessToken,
                            error: error
                        )
                        cont.resume(returning: token) // stateChangeDelegate persists new tokens
                    } catch {
                        cont.resume(throwing: error)
                    }
                }
            }
        }

        pendingRefresh = PendingRefresh(task: task, state: state, generation: generation)
        return try await task.value
    }

    /// Replaces the `OIDAuthState` whose token request never came back.
    ///
    /// AppAuth serializes refreshes through `_pendingActions`, which only that
    /// request's own callback clears. A request that never completes therefore
    /// parks every later refresh behind it for the lifetime of the state
    /// object. Rebuilding from the saved login leaves the stuck queue behind
    /// while keeping the user signed in.
    private func discardStuckAuthState() {
        // Retiring the stuck object must not depend on the restore succeeding.
        // With no state installed, fetches report "reconnect required" and the
        // next sign-in builds a clean one. The saved login is deliberately left
        // alone: only an explicit removal deletes it.
        let restored = restore(key)
        authState?.stateChangeDelegate = nil
        authState?.errorDelegate = nil
        authState = restored
    }

    // MARK: - OIDAuthState delegates

    func didChange(_ state: OIDAuthState) {
        // An abandoned state can still complete its pending request. Persisting
        // then would write out whatever `authState` currently holds, so only
        // the installed state counts.
        guard state === authState else { return }
        persist(self)
    }

    func authState(_ state: OIDAuthState, didEncounterAuthorizationError error: Error) {
        guard state === authState else { return }
        let nsErr = error as NSError
        if nsErr.domain == OIDOAuthTokenErrorDomain {
            // Google rejected the refresh token. Stop using it, but keep the
            // account listed (and its saved item) so the user sees which
            // account to reconnect instead of watching it disappear.
            cancelPendingRefresh()
            state.stateChangeDelegate = nil
            state.errorDelegate = nil
            authState = nil
        }
    }
}
