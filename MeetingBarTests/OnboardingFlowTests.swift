//
//  OnboardingFlowTests.swift
//  MeetingBarTests
//

import XCTest

@testable import MeetingBar

@MainActor
final class OnboardingFlowTests: XCTestCase {
    func testCalendarSelectionRequiresAtLeastOneCalendar() {
        XCTAssertFalse(
            OnboardingFlowPolicy.canContinueCalendarSelection(
                selectedCalendarIDs: [],
                availableCalendarIDs: ["calendar"]
            )
        )
        XCTAssertTrue(
            OnboardingFlowPolicy.canContinueCalendarSelection(
                selectedCalendarIDs: ["calendar"],
                availableCalendarIDs: ["calendar"]
            )
        )
    }

    func testCalendarSelectionRejectsStaleSelectionFromAnotherProvider() {
        XCTAssertFalse(
            OnboardingFlowPolicy.canContinueCalendarSelection(
                selectedCalendarIDs: ["previous-provider-calendar"],
                availableCalendarIDs: ["active-provider-calendar"]
            )
        )
    }
}
