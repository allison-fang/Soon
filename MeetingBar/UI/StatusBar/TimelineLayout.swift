//
//  TimelineLayout.swift
//  MeetingBar
//

import CoreGraphics
import Foundation

struct TimelineLayoutEvent: Equatable {
    let id: String
    let start: Date
    let end: Date
}

struct TimelinePlacement: Equatable {
    let id: String
    let top: Double
    let height: Double
    let column: Int
    let columnCount: Int
}

/// Vertical scale of the grid. Short meetings keep `minimumEventHeight`, tall
/// enough for one line of title, like Google Calendar. Overlap is judged on
/// that visual height, not on real duration.
struct TimelineScale: Equatable {
    static let compact = TimelineScale(hourHeight: 84, minimumEventHeight: 20)
    static let comfortable = TimelineScale(hourHeight: 112, minimumEventHeight: 26)

    let hourHeight: Double
    let minimumEventHeight: Double
}

struct TimelineWindow: Equatable {
    let start: Date
    let end: Date
    var scale: TimelineScale = .compact

    var height: Double { offset(of: end) }

    func offset(of date: Date) -> Double {
        date.timeIntervalSince(start) / 3600 * scale.hourHeight
    }

    func contains(_ date: Date) -> Bool {
        date >= start && date <= end
    }
}

enum TimelineLayout {
    /// Whole hours covering the events, plus now when now is inside `day`.
    static func window(
        for events: [TimelineLayoutEvent],
        now: Date,
        day: DateInterval,
        calendar: Calendar,
        scale: TimelineScale = .compact
    ) -> TimelineWindow? {
        var lower = events.map(\.start).min()
        var upper = events.map(\.end).max()
        if day.contains(now) {
            lower = min(lower ?? now, now)
            upper = max(upper ?? now, now)
        }
        guard let lower, let upper else { return nil }

        let start = max(hourFloor(lower, calendar: calendar), day.start)
        let end = min(hourCeiling(upper, calendar: calendar), day.end)
        guard end > start else { return nil }
        return TimelineWindow(start: start, end: end, scale: scale)
    }

    static func hourTicks(in window: TimelineWindow, calendar: Calendar) -> [Date] {
        var ticks: [Date] = []
        var tick = hourFloor(window.start, calendar: calendar)
        if tick < window.start, let next = calendar.date(byAdding: .hour, value: 1, to: tick) {
            tick = next
        }
        while tick <= window.end {
            ticks.append(tick)
            guard let next = calendar.date(byAdding: .hour, value: 1, to: tick) else { break }
            tick = next
        }
        return ticks
    }

    /// Lays overlapping events side by side, Google Calendar style: every
    /// event in a chain of overlaps shares one column count.
    static func placements(
        for events: [TimelineLayoutEvent],
        in window: TimelineWindow
    ) -> [TimelinePlacement] {
        let visible = events
            .filter { $0.end > window.start && $0.start < window.end }
            .sorted {
                if $0.start != $1.start { return $0.start < $1.start }
                if $0.end != $1.end { return $0.end > $1.end }
                return $0.id < $1.id
            }

        var placements: [TimelinePlacement] = []
        var cluster: [TimelinePlacement] = []
        var columnBottoms: [Double] = []

        func closeCluster() {
            placements += cluster.map {
                TimelinePlacement(
                    id: $0.id,
                    top: $0.top,
                    height: $0.height,
                    column: $0.column,
                    columnCount: columnBottoms.count
                )
            }
            cluster = []
            columnBottoms = []
        }

        for event in visible {
            let top = window.offset(of: max(event.start, window.start))
            let height = max(
                window.offset(of: min(event.end, window.end)) - top,
                window.scale.minimumEventHeight
            )
            if let clusterBottom = columnBottoms.max(), top >= clusterBottom {
                closeCluster()
            }

            let column = columnBottoms.firstIndex { $0 <= top } ?? columnBottoms.count
            if column == columnBottoms.count {
                columnBottoms.append(top + height)
            } else {
                columnBottoms[column] = top + height
            }
            cluster.append(
                TimelinePlacement(id: event.id, top: top, height: height, column: column, columnCount: 0)
            )
        }
        closeCluster()
        return placements
    }

    private static func hourFloor(_ date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .hour, for: date)?.start ?? date
    }

    private static func hourCeiling(_ date: Date, calendar: Calendar) -> Date {
        guard let hour = calendar.dateInterval(of: .hour, for: date) else { return date }
        return hour.start == date ? date : hour.end
    }
}

enum StatusBarPopoverPlacement {
    static let screenMargin: CGFloat = 8
    static let buttonGap: CGFloat = 6
    static let detailsGap: CGFloat = 8

    /// Centers under the status item, kept fully on screen.
    static func popoverFrame(size: CGSize, button: CGRect, visible: CGRect) -> CGRect {
        let maxX = visible.maxX - screenMargin - size.width
        let x = max(visible.minX + screenMargin, min(button.midX - size.width / 2, maxX))
        return CGRect(
            x: x,
            y: max(visible.minY + screenMargin, button.minY - buttonGap - size.height),
            width: size.width,
            height: size.height
        )
    }

    /// Prefers the left of the popover, falling back to the right, then to
    /// whichever edge of the screen is available.
    static func detailsFrame(
        size: CGSize,
        anchor: CGRect,
        popover: CGRect,
        visible: CGRect
    ) -> CGRect {
        let left = popover.minX - detailsGap - size.width
        let right = popover.maxX + detailsGap
        let x: CGFloat
        if left >= visible.minX + screenMargin {
            x = left
        } else if right + size.width <= visible.maxX - screenMargin {
            x = right
        } else {
            x = visible.minX + screenMargin
        }

        let top = min(anchor.maxY, visible.maxY - screenMargin)
        return CGRect(
            x: x,
            y: max(visible.minY + screenMargin, top - size.height),
            width: size.width,
            height: size.height
        )
    }
}
