//
//  TimelineLayoutTests.swift
//  MeetingBar
//

import XCTest

@testable import MeetingBarLogic

final class TimelineLayoutTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private var day: DateInterval {
        let start = calendar.date(from: DateComponents(year: 2026, month: 11, day: 6))!
        return DateInterval(start: start, duration: 86_400)
    }

    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        day.start.addingTimeInterval(Double(hour) * 3600 + Double(minute) * 60)
    }

    private func event(_ id: String, _ start: Date, _ end: Date) -> TimelineLayoutEvent {
        TimelineLayoutEvent(id: id, start: start, end: end)
    }

    // MARK: Window

    func testWindowCoversEventsAndNowInWholeHours() {
        let window = TimelineLayout.window(
            for: [event("a", at(9, 30), at(10)), event("b", at(14), at(14, 20))],
            now: at(8, 10),
            day: day,
            calendar: calendar
        )

        XCTAssertEqual(window?.start, at(8))
        XCTAssertEqual(window?.end, at(15))
    }

    func testWindowIgnoresNowOutsideTheDay() {
        let window = TimelineLayout.window(
            for: [event("a", at(9), at(10))],
            now: day.end.addingTimeInterval(7200),
            day: day,
            calendar: calendar
        )

        XCTAssertEqual(window?.start, at(9))
        XCTAssertEqual(window?.end, at(10))
    }

    func testWindowClampsEventsCrossingMidnightToTheDay() {
        let window = TimelineLayout.window(
            for: [event("late", at(23), at(25))],
            now: at(22, 30),
            day: day,
            calendar: calendar
        )

        XCTAssertEqual(window?.start, at(22))
        XCTAssertEqual(window?.end, day.end)
    }

    func testOffsetScalesWithHourHeight() {
        let window = TimelineWindow(start: at(9), end: at(11))

        XCTAssertEqual(window.offset(of: at(9, 30)), TimelineScale.compact.hourHeight / 2)
        XCTAssertEqual(window.height, TimelineScale.compact.hourHeight * 2)
    }

    func testComfortableScaleGivesEveryHourMoreRoom() {
        let compact = TimelineWindow(start: at(9), end: at(10), scale: .compact)
        let comfortable = TimelineWindow(start: at(9), end: at(10), scale: .comfortable)

        XCTAssertGreaterThan(comfortable.height, compact.height)
    }

    func testWindowKeepsTheRequestedScale() {
        let window = TimelineLayout.window(
            for: [event("a", at(9), at(10))],
            now: at(9),
            day: day,
            calendar: calendar,
            scale: .comfortable
        )

        XCTAssertEqual(window?.scale, .comfortable)
    }

    func testMinimumHeightFollowsTheScale() {
        let window = TimelineWindow(start: at(9), end: at(10), scale: .comfortable)

        let placements = TimelineLayout.placements(
            for: [event("short", at(9), at(9, 5))],
            in: window
        )

        XCTAssertEqual(placements[0].height, TimelineScale.comfortable.minimumEventHeight)
    }

    func testHourTicksIncludeBothEnds() {
        let ticks = TimelineLayout.hourTicks(
            in: TimelineWindow(start: at(9), end: at(11)),
            calendar: calendar
        )

        XCTAssertEqual(ticks, [at(9), at(10), at(11)])
    }

    func testHourTicksSkipTheSpringForwardGap() throws {
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let start = try XCTUnwrap(
            newYork.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 1))
        )

        let ticks = TimelineLayout.hourTicks(
            in: TimelineWindow(start: start, end: start.addingTimeInterval(2 * 3600)),
            calendar: newYork
        )

        XCTAssertEqual(ticks.map { newYork.component(.hour, from: $0) }, [1, 3, 4])
    }

    // MARK: Placement

    func testSeparateEventsTakeTheFullWidth() {
        let window = TimelineWindow(start: at(9), end: at(12))

        let placements = TimelineLayout.placements(
            for: [event("a", at(9), at(10)), event("b", at(10), at(11))],
            in: window
        )

        XCTAssertEqual(placements.map(\.columnCount), [1, 1])
        XCTAssertEqual(placements.map(\.column), [0, 0])
    }

    func testOverlappingEventsSitSideBySide() {
        let window = TimelineWindow(start: at(9), end: at(12))

        let placements = TimelineLayout.placements(
            for: [event("a", at(9), at(10)), event("b", at(9, 30), at(10, 30))],
            in: window
        )

        XCTAssertEqual(placements.map(\.id), ["a", "b"])
        XCTAssertEqual(placements.map(\.column), [0, 1])
        XCTAssertEqual(placements.map(\.columnCount), [2, 2])
    }

    func testChainedOverlapsShareOneColumnCount() {
        let window = TimelineWindow(start: at(9), end: at(13))

        let placements = TimelineLayout.placements(
            for: [
                event("a", at(9), at(10)),
                event("b", at(9, 30), at(10, 30)),
                event("c", at(10, 15), at(11))
            ],
            in: window
        )

        XCTAssertEqual(placements.map(\.columnCount), [2, 2, 2])
        XCTAssertEqual(placements.map(\.column), [0, 1, 0])
    }

    func testOverlapEndsTheClusterAtItsLastEvent() {
        let window = TimelineWindow(start: at(9), end: at(13))

        let placements = TimelineLayout.placements(
            for: [
                event("a", at(9), at(10)),
                event("b", at(9), at(10)),
                event("later", at(11), at(12))
            ],
            in: window
        )

        XCTAssertEqual(placements.last?.columnCount, 1)
    }

    func testShortEventGetsMinimumHeightAndAvoidsTheNextEvent() {
        let window = TimelineWindow(start: at(9), end: at(11))

        let placements = TimelineLayout.placements(
            for: [event("short", at(9), at(9, 5)), event("next", at(9, 10), at(10))],
            in: window
        )

        XCTAssertEqual(placements[0].height, TimelineScale.compact.minimumEventHeight)
        XCTAssertEqual(placements.map(\.columnCount), [2, 2])
    }

    func testEventsOutsideTheWindowAreDropped() {
        let window = TimelineWindow(start: at(9), end: at(10))

        let placements = TimelineLayout.placements(
            for: [event("before", at(7), at(8)), event("after", at(11), at(12))],
            in: window
        )

        XCTAssertTrue(placements.isEmpty)
    }

    // MARK: Panel placement

    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)

    func testPopoverCentersUnderItsButton() {
        let frame = StatusBarPopoverPlacement.popoverFrame(
            size: CGSize(width: 372, height: 600),
            button: CGRect(x: 700, y: 875, width: 40, height: 25),
            visible: screen
        )

        XCTAssertEqual(frame.midX, 720)
        XCTAssertEqual(frame.maxY, 875 - StatusBarPopoverPlacement.buttonGap)
    }

    func testPopoverStaysOnScreenNearTheRightEdge() {
        let frame = StatusBarPopoverPlacement.popoverFrame(
            size: CGSize(width: 372, height: 600),
            button: CGRect(x: 1400, y: 875, width: 40, height: 25),
            visible: screen
        )

        XCTAssertEqual(frame.maxX, screen.maxX - StatusBarPopoverPlacement.screenMargin)
    }

    func testDetailsOpenLeftOfThePopover() {
        let popover = CGRect(x: 900, y: 200, width: 372, height: 600)

        let frame = StatusBarPopoverPlacement.detailsFrame(
            size: CGSize(width: 320, height: 300),
            anchor: CGRect(x: 950, y: 500, width: 300, height: 40),
            popover: popover,
            visible: screen
        )

        XCTAssertEqual(frame.maxX, popover.minX - StatusBarPopoverPlacement.detailsGap)
        XCTAssertEqual(frame.maxY, 540)
    }

    func testDetailsFlipRightWhenThereIsNoRoomOnTheLeft() {
        let popover = CGRect(x: 100, y: 200, width: 372, height: 600)

        let frame = StatusBarPopoverPlacement.detailsFrame(
            size: CGSize(width: 320, height: 300),
            anchor: CGRect(x: 150, y: 500, width: 300, height: 40),
            popover: popover,
            visible: screen
        )

        XCTAssertEqual(frame.minX, popover.maxX + StatusBarPopoverPlacement.detailsGap)
    }

    func testDetailsStayAboveTheBottomOfTheScreen() {
        let frame = StatusBarPopoverPlacement.detailsFrame(
            size: CGSize(width: 320, height: 500),
            anchor: CGRect(x: 950, y: 60, width: 300, height: 40),
            popover: CGRect(x: 900, y: 8, width: 372, height: 600),
            visible: screen
        )

        XCTAssertEqual(frame.minY, screen.minY + StatusBarPopoverPlacement.screenMargin)
    }
}
