//
//  UpdateCheckPolicyTests.swift
//  MeetingBarLogicTests
//

import XCTest

@testable import MeetingBarLogic

final class UpdateCheckPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let releaseURL = URL(string: "https://github.com/allison-fang/Soon/releases/tag/v1.3.0")!

    private func release(_ tag: String, draft: Bool = false, prerelease: Bool = false) -> LatestRelease {
        LatestRelease(tagName: tag, htmlURL: releaseURL, draft: draft, prerelease: prerelease)
    }

    // MARK: AppVersion

    func testParsesWithAndWithoutPrefix() {
        XCTAssertEqual(AppVersion("1.2.0")?.components, [1, 2, 0])
        XCTAssertEqual(AppVersion("v1.2.0")?.components, [1, 2, 0])
        XCTAssertEqual(AppVersion(" V2 ")?.components, [2])
    }

    func testRejectsMalformedVersions() {
        for text in ["", "v", "1..2", "1.2.", "1.2.0-beta", "latest", "1.-2", "١.٢"] {
            XCTAssertNil(AppVersion(text), text)
        }
    }

    func testComparesNumericallyNotLexically() {
        XCTAssertLessThan(AppVersion("1.9.0")!, AppVersion("1.10.0")!)
        XCTAssertLessThan(AppVersion("1.2.0")!, AppVersion("2.0")!)
    }

    func testMissingComponentsAreZero() {
        XCTAssertEqual(AppVersion("1.2")!, AppVersion("1.2.0")!)
        XCTAssertLessThan(AppVersion("1.2")!, AppVersion("1.2.1")!)
    }

    func testDescriptionDropsPrefix() {
        XCTAssertEqual(AppVersion("v1.3.0")?.description, "1.3.0")
    }

    // MARK: availableUpdate

    func testNewerReleaseIsAvailable() {
        XCTAssertEqual(
            UpdateCheckPolicy.availableUpdate(currentVersion: "1.2.0", release: release("v1.3.0")),
            AvailableUpdate(version: "1.3.0", releaseURL: releaseURL)
        )
    }

    func testSameOrOlderReleaseIsNotAvailable() {
        XCTAssertNil(UpdateCheckPolicy.availableUpdate(currentVersion: "1.2.0", release: release("v1.2.0")))
        XCTAssertNil(UpdateCheckPolicy.availableUpdate(currentVersion: "1.2.0", release: release("v1.1.9")))
    }

    func testDraftsAndPrereleasesAreIgnored() {
        XCTAssertNil(UpdateCheckPolicy.availableUpdate(currentVersion: "1.2.0", release: release("v1.3.0", draft: true)))
        XCTAssertNil(UpdateCheckPolicy.availableUpdate(currentVersion: "1.2.0", release: release("v1.3.0", prerelease: true)))
    }

    func testUnparseableVersionsAreIgnored() {
        XCTAssertNil(UpdateCheckPolicy.availableUpdate(currentVersion: "1.2.0", release: release("nightly")))
        XCTAssertNil(UpdateCheckPolicy.availableUpdate(currentVersion: "", release: release("v1.3.0")))
    }

    // MARK: isCheckDue

    func testFirstCheckIsDue() {
        XCTAssertTrue(UpdateCheckPolicy.isCheckDue(lastCheck: nil, now: now))
    }

    func testCheckIsDueOnlyAfterInterval() {
        let interval = UpdateCheckPolicy.checkInterval
        XCTAssertFalse(UpdateCheckPolicy.isCheckDue(lastCheck: now.addingTimeInterval(-interval + 1), now: now))
        XCTAssertTrue(UpdateCheckPolicy.isCheckDue(lastCheck: now.addingTimeInterval(-interval), now: now))
    }

    func testFutureLastCheckIsDue() {
        XCTAssertTrue(UpdateCheckPolicy.isCheckDue(lastCheck: now.addingTimeInterval(3600), now: now))
    }

    // MARK: Decoding

    func testDecodesGitHubLatestRelease() throws {
        let json = """
        {"tag_name":"v1.3.0","html_url":"https://github.com/allison-fang/Soon/releases/tag/v1.3.0",
         "draft":false,"prerelease":false,"name":"1.3.0","assets":[]}
        """
        XCTAssertEqual(try LatestRelease.decode(Data(json.utf8)), release("v1.3.0"))
    }

    func testDecodingFailsWithoutTag() {
        XCTAssertThrowsError(try LatestRelease.decode(Data(#"{"message":"Not Found"}"#.utf8)))
    }
}
