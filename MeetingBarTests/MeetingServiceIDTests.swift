//
//  MeetingServiceIDTests.swift
//  MeetingBarTests
//

import XCTest

@testable import MeetingBar

final class MeetingServiceIDTests: XCTestCase {
    /// Stored per-provider browser preferences are keyed by these strings.
    func testMeetingServicesRawValuesAreUsedAsServiceIDs() {
        XCTAssertEqual(MeetingServices.meet.rawValue, "Google Meet")
        XCTAssertEqual(MeetingServices.zoom.rawValue, "Zoom")
        XCTAssertEqual(MeetingServices.teams.rawValue, "Microsoft Teams")
        XCTAssertEqual(MeetingServices.jitsi.rawValue, "Jitsi")
        XCTAssertEqual(MeetingServices.slack.rawValue, "Slack")
        XCTAssertEqual(MeetingServices.riverside.rawValue, "Riverside")
    }
}
