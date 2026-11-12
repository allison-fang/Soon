//
//  TimelinePaletteTests.swift
//  MeetingBar
//

import XCTest

@testable import MeetingBarLogic

final class TimelinePaletteTests: XCTestCase {
    private let responses: [TimelineEventResponse] = [.accepted, .pending, .tentative, .declined]
    private let schemes: [TimelineColorScheme] = [.light, .dark]

    /// Light, dark and mid-tone calendars, including a pale yellow and black.
    private let calendars: [TimelineRGB] = [
        TimelineRGB(red: 0.84, green: 0.00, blue: 0.00),
        TimelineRGB(red: 0.96, green: 0.75, blue: 0.15),
        TimelineRGB(red: 0.20, green: 0.71, blue: 0.47),
        TimelineRGB(red: 0.04, green: 0.50, blue: 0.26),
        TimelineRGB(red: 0.01, green: 0.61, blue: 0.90),
        TimelineRGB(red: 0.25, green: 0.32, blue: 0.71),
        TimelineRGB(red: 0.56, green: 0.14, blue: 0.67),
        TimelineRGB(red: 0.38, green: 0.38, blue: 0.38),
        .black,
        .white
    ]

    private func forEachColorSet(_ body: (TimelineCardColors, TimelineEventResponse, Bool) -> Void) {
        for calendar in calendars {
            for scheme in schemes {
                let palette = TimelinePalette(calendar: calendar, scheme: scheme)
                for response in responses {
                    for isDimmed in [false, true] {
                        body(palette.colors(for: response, isDimmed: isDimmed), response, isDimmed)
                    }
                }
            }
        }
    }

    func testContrastRatioMatchesTheWcagExtremes() {
        XCTAssertEqual(TimelineRGB.black.contrastRatio(with: .white), 21, accuracy: 0.01)
        XCTAssertEqual(TimelineRGB.white.contrastRatio(with: .white), 1, accuracy: 0.01)
    }

    func testAnsweredStatesKeepReadableTitlesOnEveryCalendar() {
        forEachColorSet { colors, response, isDimmed in
            guard !isDimmed, response == .pending || response == .tentative else { return }
            let backdrop = colors.stripes ?? colors.background
            XCTAssertGreaterThanOrEqual(colors.title.contrastRatio(with: backdrop), 4.5)
        }
    }

    func testQuietStatesStayLegible() {
        forEachColorSet { colors, response, isDimmed in
            guard isDimmed || response == .declined else { return }
            let backdrop = colors.stripes ?? colors.background
            let minimum = isDimmed ? 2.2 : 3
            XCTAssertGreaterThanOrEqual(colors.title.contrastRatio(with: backdrop), minimum)
        }
    }

    func testPastTextIsQuieterThanLiveTextInEveryState() {
        for calendar in calendars {
            for scheme in schemes {
                let palette = TimelinePalette(calendar: calendar, scheme: scheme)
                for response in responses {
                    let live = palette.colors(for: response, isDimmed: false)
                    let past = palette.colors(for: response, isDimmed: true)
                    XCTAssertLessThan(
                        past.title.contrastRatio(with: past.stripes ?? past.background),
                        live.title.contrastRatio(with: live.stripes ?? live.background)
                    )
                }
            }
        }
    }

    func testSolidCardsPickTheStrongerForeground() {
        let banana = TimelinePalette(
            calendar: TimelineRGB(red: 0.96, green: 0.75, blue: 0.15),
            scheme: .light
        )
        let peacock = TimelinePalette(
            calendar: TimelineRGB(red: 0.01, green: 0.61, blue: 0.90),
            scheme: .light
        )

        XCTAssertNotEqual(banana.onSolid, .white)
        XCTAssertEqual(peacock.onSolid, .white)
    }

    func testOnlyAcceptedCardsAreFilledWithTheCalendarColor() {
        let calendar = TimelineRGB(red: 0.01, green: 0.61, blue: 0.90)
        let palette = TimelinePalette(calendar: calendar, scheme: .light)

        XCTAssertEqual(palette.colors(for: .accepted, isDimmed: false).background, calendar)
        for response in [TimelineEventResponse.pending, .tentative, .declined] {
            XCTAssertNotEqual(palette.colors(for: response, isDimmed: false).background, calendar)
        }
    }

    func testUnansweredCardsCarryTheCalendarColorInTheirBorderAndBackground() {
        let calendar = TimelineRGB(red: 0.01, green: 0.61, blue: 0.90)
        let palette = TimelinePalette(calendar: calendar, scheme: .light)

        let pending = palette.colors(for: .pending, isDimmed: false)

        XCTAssertEqual(pending.border, calendar)
        XCTAssertNotEqual(pending.background, palette.surface)
    }

    func testOnlyTentativeCardsAreStriped() {
        let palette = TimelinePalette(calendar: .black, scheme: .light)

        for response in responses {
            for isDimmed in [false, true] {
                let colors = palette.colors(for: response, isDimmed: isDimmed)
                XCTAssertEqual(colors.stripes != nil, response == .tentative)
            }
        }
    }

    func testPastFillIsLighterThanTheLiveFill() {
        let calendar = TimelineRGB(red: 0.01, green: 0.61, blue: 0.90)
        let palette = TimelinePalette(calendar: calendar, scheme: .light)

        let live = palette.colors(for: .accepted, isDimmed: false)
        let past = palette.colors(for: .accepted, isDimmed: true)

        XCTAssertLessThan(
            past.background.contrastRatio(with: palette.surface),
            live.background.contrastRatio(with: palette.surface)
        )
    }
}
