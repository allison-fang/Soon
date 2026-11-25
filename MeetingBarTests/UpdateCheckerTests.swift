//
//  UpdateCheckerTests.swift
//  MeetingBarTests
//

import XCTest

@testable import MeetingBar

@MainActor
final class UpdateCheckerTests: BaseTestCase {
    private final class Recorder: @unchecked Sendable {
        var fetchCount = 0
        var result: Result<LatestRelease, Error> = .success(UpdateCheckerTests.release("v1.3.0"))
    }

    nonisolated private static func release(_ tag: String) -> LatestRelease {
        LatestRelease(
            tagName: tag,
            htmlURL: URL(string: "https://github.com/allison-fang/Soon/releases/tag/\(tag)")!,
            draft: false,
            prerelease: false
        )
    }

    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private var lastCheck: Date?
    private var enabled = true
    private let recorder = Recorder()

    private func makeChecker(
        currentVersion: String = "1.2.0",
        automaticChecksAllowed: Bool = true
    ) -> UpdateChecker {
        let recorder = recorder
        return UpdateChecker(dependencies: .init(
            currentVersion: currentVersion,
            automaticChecksAllowed: automaticChecksAllowed,
            isEnabled: { [unowned self] in enabled },
            lastCheck: { [unowned self] in lastCheck },
            setLastCheck: { [unowned self] in lastCheck = $0 },
            now: { [unowned self] in now },
            fetchLatestRelease: {
                recorder.fetchCount += 1
                return try recorder.result.get()
            },
            sleep: { _ in try await Task.sleep(nanoseconds: .max) }
        ))
    }

    func testLaunchChecksEvenWhenCheckedRecently() async {
        lastCheck = now.addingTimeInterval(-60)
        let checker = makeChecker()
        checker.start()
        await checker.waitForCheck()
        checker.stop()

        XCTAssertEqual(recorder.fetchCount, 1)
        let expected = AvailableUpdate(version: "1.3.0", releaseURL: Self.release("v1.3.0").htmlURL)
        XCTAssertEqual(checker.availableUpdate, expected)
        XCTAssertEqual(checker.status, .available(expected))
        XCTAssertEqual(lastCheck, now)
    }

    func testWakeChecksOnlyAfterADay() async {
        let checker = makeChecker()
        lastCheck = now.addingTimeInterval(-UpdateCheckPolicy.checkInterval + 60)
        checker.handleWake()
        await checker.waitForCheck()
        XCTAssertEqual(recorder.fetchCount, 0)

        lastCheck = now.addingTimeInterval(-UpdateCheckPolicy.checkInterval)
        checker.handleWake()
        await checker.waitForCheck()
        XCTAssertEqual(recorder.fetchCount, 1)
    }

    func testDisabledSkipsAutomaticChecksButCheckNowStillWorks() async {
        enabled = false
        let checker = makeChecker()
        checker.start()
        checker.handleWake()
        await checker.waitForCheck()
        XCTAssertEqual(recorder.fetchCount, 0)

        checker.checkNow()
        await checker.waitForCheck()
        checker.stop()
        XCTAssertEqual(recorder.fetchCount, 1)
    }

    func testDebugBuildsNeverCheckAutomatically() async {
        let checker = makeChecker(automaticChecksAllowed: false)
        checker.start()
        checker.checkIfDue()
        await checker.waitForCheck()
        checker.stop()
        XCTAssertEqual(recorder.fetchCount, 0)
        XCTAssertEqual(checker.status, .idle)
    }

    func testUpToDateClearsAnEarlierUpdate() async {
        let checker = makeChecker()
        checker.checkNow()
        await checker.waitForCheck()
        XCTAssertNotNil(checker.availableUpdate)

        recorder.result = .success(Self.release("v1.2.0"))
        checker.checkNow()
        await checker.waitForCheck()
        XCTAssertNil(checker.availableUpdate)
        XCTAssertEqual(checker.status, .upToDate)
    }

    func testFailureKeepsLastCheckSoTheNextTriggerRetries() async {
        recorder.result = .failure(URLError(.notConnectedToInternet))
        let checker = makeChecker()
        checker.checkNow()
        await checker.waitForCheck()

        XCTAssertEqual(checker.status, .failed)
        XCTAssertNil(lastCheck)
        XCTAssertNil(checker.availableUpdate)
    }

    func testConcurrentTriggersShareOneRequest() async {
        let checker = makeChecker()
        checker.checkNow()
        checker.checkNow()
        checker.handleWake()
        await checker.waitForCheck()
        XCTAssertEqual(recorder.fetchCount, 1)
    }
}
