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

    func testWindowCoversTheWholeDay() {
        let window = TimelineWindow(day: day, scale: .standard)

        XCTAssertEqual(window.start, at(0))
        XCTAssertEqual(window.end, at(24))
        XCTAssertEqual(window.height, 24 * TimelineScale.standard.hourHeight)
    }

    func testEventsCrossingMidnightAreClippedToTheDay() {
        let window = TimelineWindow(day: day, scale: .standard)

        let placements = TimelineLayout.placements(
            for: [event("late", at(23), at(25)), event("early", at(-1), at(1))],
            in: window
        )

        XCTAssertEqual(placements.first { $0.id == "early" }?.top, 0)
        XCTAssertEqual(
            placements.first { $0.id == "late" }.map { $0.top + $0.height },
            window.height
        )
    }

    func testShortDayFromDaylightSavingKeepsItsRealLength() throws {
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let noon = try XCTUnwrap(newYork.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 12)))
        let springForward = try XCTUnwrap(newYork.dateInterval(of: .day, for: noon))

        let window = TimelineWindow(day: springForward, scale: .standard)

        XCTAssertEqual(window.height, 23 * TimelineScale.standard.hourHeight)
        XCTAssertEqual(TimelineLayout.hourTicks(in: window, calendar: newYork).count, 24)
    }

    // MARK: Zoom

    func testZoomLevelsShowFewerHoursAsTheyGoIn() {
        let heights = TimelineZoom.allCases.map(\.hourHeight)

        XCTAssertEqual(heights, heights.sorted())
        XCTAssertEqual(Set(heights).count, heights.count)
    }

    func testFullDayZoomFitsTheShortestPopoverTimeline() {
        // The popover's timeline is at most 540 pt, with 10 pt insets.
        XCTAssertLessThanOrEqual(TimelineZoom.fullDay.hourHeight * 24, 540 - 20)
    }

    func testZoomStepsStopAtEitherEnd() {
        XCTAssertNil(TimelineZoom.fullDay.zoomedOut)
        XCTAssertNil(TimelineZoom.closest.zoomedIn)
        XCTAssertEqual(TimelineZoom.fullDay.zoomedIn, .wide)
        XCTAssertEqual(TimelineZoom.medium.zoomedOut, .wide)
    }

    func testEveryLevelIsReachableByStepping() {
        var level: TimelineZoom? = .fullDay
        var visited: [TimelineZoom] = []
        while let current = level {
            visited.append(current)
            level = current.zoomedIn
        }

        XCTAssertEqual(visited, TimelineZoom.allCases)
    }

    func testZoomKeepsTheOneLineMinimum() {
        for zoom in TimelineZoom.allCases {
            XCTAssertEqual(TimelineScale.standard.zoomed(to: zoom).hourHeight, zoom.hourHeight)
            XCTAssertEqual(
                TimelineScale.standard.zoomed(to: zoom).minimumEventHeight,
                TimelineScale.standard.minimumEventHeight
            )
        }
    }

    func testStandardScaleMatchesTheDefaultZoom() {
        XCTAssertEqual(TimelineScale.standard.hourHeight, TimelineZoom.close.hourHeight)
    }

    func testShortEventStaysOneLineTallAtFullDayZoom() {
        let window = TimelineWindow(day: day, scale: TimelineScale.standard.zoomed(to: .fullDay))

        let placements = TimelineLayout.placements(for: [event("a", at(9), at(9, 30))], in: window)

        XCTAssertEqual(placements[0].height, TimelineScale.standard.minimumEventHeight)
    }

    // MARK: Card content

    private func card(
        width: Double = 300,
        height: Double = 100,
        hasCountdown: Bool = true,
        hasGuests: Bool = true
    ) -> TimelineCardContent {
        TimelineCardContent(
            width: width,
            height: height,
            twoRowHeight: 51,
            hasCountdown: hasCountdown,
            hasGuests: hasGuests
        )
    }

    func testRoomyCardShowsEverything() {
        let content = card()

        XCTAssertEqual(content.rows, 2)
        XCTAssertTrue(content.showsCountdown)
        XCTAssertTrue(content.showsAvatars)
    }

    func testShorterCardsDropRowsBelowTheTitle() {
        XCTAssertEqual(card(height: 60).rows, 2)
        XCTAssertEqual(card(height: 22).rows, 1)
        XCTAssertEqual(card(height: 1).rows, 1)
    }

    func testOneLineCardHasNoRoomForAvatars() {
        XCTAssertFalse(card(height: 22).showsAvatars)
    }

    func testNarrowCardsDropCountdownAndAvatars() {
        let narrow = card(width: 140)

        XCTAssertFalse(narrow.showsCountdown)
        XCTAssertFalse(narrow.showsAvatars)
    }

    func testCardsWithoutCountdownOrGuestsShowNeither() {
        XCTAssertFalse(card(hasCountdown: false).showsCountdown)
        XCTAssertFalse(card(hasGuests: false).showsAvatars)
    }

    func testOffsetScalesWithHourHeight() {
        let window = TimelineWindow(start: at(9), end: at(11))

        XCTAssertEqual(window.offset(of: at(9, 30)), TimelineScale.standard.hourHeight / 2)
        XCTAssertEqual(window.height, TimelineScale.standard.hourHeight * 2)
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

        XCTAssertEqual(placements[0].height, TimelineScale.standard.minimumEventHeight)
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
