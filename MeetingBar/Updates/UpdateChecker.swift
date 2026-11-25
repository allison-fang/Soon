//
//  UpdateChecker.swift
//  MeetingBar
//

import Defaults
import Foundation

/// Owns the release check: at launch, on an hourly tick and on wake, each
/// gated by `UpdateCheckPolicy.isCheckDue`, plus explicit "Check now".
@MainActor
final class UpdateChecker: ObservableObject {
    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case available(AvailableUpdate)
        case failed
    }

    struct Dependencies {
        var currentVersion: String
        /// `false` in Debug builds so SoonDev never checks on its own.
        var automaticChecksAllowed: Bool
        var isEnabled: @MainActor () -> Bool
        var lastCheck: @MainActor () -> Date?
        var setLastCheck: @MainActor (Date) -> Void
        var now: @MainActor () -> Date
        var fetchLatestRelease: @Sendable () async throws -> LatestRelease
        var sleep: @Sendable (TimeInterval) async throws -> Void
    }

    static let tickInterval: TimeInterval = 60 * 60

    @Published private(set) var status: Status = .idle
    @Published private(set) var availableUpdate: AvailableUpdate?

    private let dependencies: Dependencies
    private var checkTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    var currentVersion: String { dependencies.currentVersion }

    func start() {
        guard tickTask == nil else { return }
        if automaticChecksEnabled {
            check()
        }
        tickTask = Task { [weak self, sleep = dependencies.sleep] in
            while !Task.isCancelled {
                do {
                    try await sleep(Self.tickInterval)
                } catch {
                    return
                }
                self?.checkIfDue()
            }
        }
    }

    func handleWake() {
        checkIfDue()
    }

    func checkNow() {
        check()
    }

    func stop() {
        tickTask?.cancel()
        tickTask = nil
        checkTask?.cancel()
        checkTask = nil
    }

    /// Exposed for tests; production calls arrive through the tick and wake.
    func checkIfDue() {
        guard automaticChecksEnabled,
              UpdateCheckPolicy.isCheckDue(lastCheck: dependencies.lastCheck(), now: dependencies.now())
        else { return }
        check()
    }

    /// Exposed for tests to await the in-flight check.
    func waitForCheck() async {
        await checkTask?.value
    }

    private var automaticChecksEnabled: Bool {
        dependencies.automaticChecksAllowed && dependencies.isEnabled()
    }

    private func check() {
        guard checkTask == nil else { return }
        status = .checking
        checkTask = Task { [weak self, fetch = dependencies.fetchLatestRelease] in
            let result: Result<LatestRelease, Error>
            do {
                result = .success(try await fetch())
            } catch {
                result = .failure(error)
            }
            guard let self, !Task.isCancelled else { return }
            checkTask = nil
            apply(result)
        }
    }

    private func apply(_ result: Result<LatestRelease, Error>) {
        switch result {
        case .success(let release):
            dependencies.setLastCheck(dependencies.now())
            let update = UpdateCheckPolicy.availableUpdate(
                currentVersion: dependencies.currentVersion,
                release: release
            )
            availableUpdate = update
            status = update.map(Status.available) ?? .upToDate
        case .failure:
            // Leave lastCheck untouched so the next tick or wake retries.
            status = .failed
        }
    }
}

// MARK: - Live wiring

extension UpdateChecker {
    static let latestReleaseURL = URL(string: "https://api.github.com/repos/allison-fang/Soon/releases/latest")!
    static let installCommand =
        "curl -fsSL https://raw.githubusercontent.com/allison-fang/Soon/master/Scripts/install.sh | bash"

    static func live() -> UpdateChecker {
        let bundleVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        var currentVersion = bundleVersion
        var automaticChecksAllowed = true
        #if DEBUG
            // `open SoonDev.app --args -debugFakeAppVersion 1.0.0` to preview the notice.
            if let fake = UserDefaults.standard.string(forKey: "debugFakeAppVersion") {
                currentVersion = fake
            } else {
                automaticChecksAllowed = false
            }
        #endif
        let userAgent = "Soon/\(bundleVersion)"
        return UpdateChecker(dependencies: Dependencies(
            currentVersion: currentVersion,
            automaticChecksAllowed: automaticChecksAllowed,
            isEnabled: { Defaults[.checkForUpdates] },
            lastCheck: { Defaults[.lastUpdateCheck] },
            setLastCheck: { Defaults[.lastUpdateCheck] = $0 },
            now: { Date() },
            fetchLatestRelease: { try await fetchLatestRelease(userAgent: userAgent) },
            sleep: { try await Task.sleep(nanoseconds: UInt64($0 * Double(NSEC_PER_SEC))) }
        ))
    }

    private static func fetchLatestRelease(userAgent: String) async throws -> LatestRelease {
        var request = URLRequest(url: latestReleaseURL, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try LatestRelease.decode(data)
    }
}
