//
//  TimelinePalette.swift
//  MeetingBar
//

import Foundation

/// The response cues Google Calendar draws on an event.
enum TimelineEventResponse: Equatable {
    case accepted
    case pending
    case tentative
    case declined
}

enum TimelineColorScheme {
    case light
    case dark
}

struct TimelineRGB: Equatable {
    static let white = TimelineRGB(red: 1, green: 1, blue: 1)
    static let black = TimelineRGB(red: 0, green: 0, blue: 0)

    let red: Double
    let green: Double
    let blue: Double

    var relativeLuminance: Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    func contrastRatio(with other: TimelineRGB) -> Double {
        let lighter = max(relativeLuminance, other.relativeLuminance)
        let darker = min(relativeLuminance, other.relativeLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    func mixed(with other: TimelineRGB, amount: Double) -> TimelineRGB {
        TimelineRGB(
            red: red + (other.red - red) * amount,
            green: green + (other.green - green) * amount,
            blue: blue + (other.blue - blue) * amount
        )
    }
}

struct TimelineCardColors: Equatable {
    let background: TimelineRGB
    let stripes: TimelineRGB?
    let border: TimelineRGB?
    let title: TimelineRGB
    let detail: TimelineRGB
    let avatarFill: TimelineRGB
    let avatarText: TimelineRGB
    let primaryActionFill: TimelineRGB
    let primaryActionText: TimelineRGB
    let quietActionFill: TimelineRGB
    let quietActionText: TimelineRGB
}

/// Every state is drawn from the calendar's own hue, so color always answers
/// "which calendar" and fill, stripes and strikethrough answer "which state".
/// Colors are opaque so that hour lines never show through a card.
struct TimelinePalette: Equatable {
    private static let readableContrast = 4.5
    private static let softContrast = 3.2
    private static let faintContrast = 2.6
    private static let detailContrastRatio = 0.85
    private static let pastContrast = 2.3
    private static let pastDetailContrast = 1.9
    /// Google keeps white text on mid-tone calendars such as Sage, which sit
    /// well below 3:1, and only flips to dark text on light ones like Banana.
    private static let whiteOnFillContrast = 2.4

    let calendar: TimelineRGB
    let scheme: TimelineColorScheme

    var surface: TimelineRGB {
        scheme == .light ? .white : TimelineRGB(red: 0.14, green: 0.14, blue: 0.15)
    }

    var solid: TimelineRGB {
        scheme == .light ? calendar : calendar.mixed(with: surface, amount: 0.12)
    }

    var onSolid: TimelineRGB {
        solid.contrastRatio(with: .white) >= Self.whiteOnFillContrast
            ? .white
            : TimelineRGB(red: 0.1, green: 0.1, blue: 0.12)
    }

    func tint(_ amount: Double) -> TimelineRGB {
        surface.mixed(with: calendar, amount: scheme == .light ? amount : amount * 1.4)
    }

    /// The calendar's hue, darkened or lightened only as far as `contrast` needs.
    func readable(on background: TimelineRGB, contrast: Double) -> TimelineRGB {
        let target: TimelineRGB = scheme == .light ? .black : .white
        for step in 0 ... 25 {
            let candidate = calendar.mixed(with: target, amount: Double(step) * 0.04)
            if candidate.contrastRatio(with: background) >= contrast {
                return candidate
            }
        }
        // A near-white calendar in dark mode tints its card too light for light text.
        return background.contrastRatio(with: .black) > background.contrastRatio(with: .white)
            ? .black
            : .white
    }

    func colors(for response: TimelineEventResponse, isDimmed: Bool) -> TimelineCardColors {
        if isDimmed {
            return pastColors(for: response)
        }
        switch response {
        case .accepted:
            return acceptedColors
        case .pending:
            return hollowColors(
                background: tint(0.12),
                stripes: nil,
                border: solid,
                contrast: Self.readableContrast
            )
        case .tentative:
            return hollowColors(
                background: tint(0.1),
                stripes: tint(0.26),
                border: tint(0.6),
                contrast: Self.readableContrast
            )
        case .declined:
            return hollowColors(
                background: tint(0.04),
                stripes: nil,
                border: tint(0.38),
                contrast: Self.softContrast
            )
        }
    }

    private var acceptedColors: TimelineCardColors {
        TimelineCardColors(
            background: solid,
            stripes: nil,
            border: nil,
            title: onSolid,
            detail: onSolid.mixed(with: solid, amount: 0.14),
            avatarFill: solid.mixed(with: onSolid, amount: 0.26),
            avatarText: onSolid,
            primaryActionFill: onSolid,
            primaryActionText: readable(on: onSolid, contrast: Self.readableContrast),
            quietActionFill: solid.mixed(with: onSolid, amount: 0.22),
            quietActionText: onSolid
        )
    }

    /// Past events keep their state's shape but read as grayed out: a faint
    /// tint, and text pulled toward gray as well as toward the background.
    private func pastColors(for response: TimelineEventResponse) -> TimelineCardColors {
        let background: TimelineRGB
        let stripes: TimelineRGB?
        let border: TimelineRGB?
        switch response {
        case .accepted:
            background = tint(0.14)
            stripes = nil
            border = nil
        case .pending:
            background = tint(0.03)
            stripes = nil
            border = tint(0.3)
        case .tentative:
            background = tint(0.03)
            stripes = tint(0.09)
            border = tint(0.22)
        case .declined:
            background = tint(0.02)
            stripes = nil
            border = tint(0.16)
        }
        let backdrop = stripes ?? background
        let avatarFill = tint(0.12)
        return TimelineCardColors(
            background: background,
            stripes: stripes,
            border: border,
            title: faded(on: backdrop, contrast: Self.pastContrast),
            detail: faded(on: backdrop, contrast: Self.pastDetailContrast),
            avatarFill: avatarFill,
            avatarText: faded(on: avatarFill, contrast: Self.pastDetailContrast),
            primaryActionFill: solid,
            primaryActionText: onSolid,
            quietActionFill: tint(0.2),
            quietActionText: faded(on: tint(0.2), contrast: Self.pastContrast)
        )
    }

    /// The calendar's hue, mostly washed to gray, just dark (or light) enough to read.
    private func faded(on background: TimelineRGB, contrast: Double) -> TimelineRGB {
        let gray = TimelineRGB(red: 0.5, green: 0.5, blue: 0.5)
        let base = calendar.mixed(with: gray, amount: 0.55)
        let target: TimelineRGB = scheme == .light ? .black : .white
        let start = base.mixed(with: background, amount: 0.5)
        for step in 0 ... 25 {
            let candidate = start.mixed(with: target, amount: Double(step) * 0.04)
            if candidate.contrastRatio(with: background) >= contrast {
                return candidate
            }
        }
        return target
    }

    private func hollowColors(
        background: TimelineRGB,
        stripes: TimelineRGB?,
        border: TimelineRGB,
        contrast: Double
    ) -> TimelineCardColors {
        let backdrop = stripes ?? background
        let avatarFill = tint(contrast < Self.readableContrast ? 0.18 : 0.3)
        return TimelineCardColors(
            background: background,
            stripes: stripes,
            border: border,
            title: readable(on: backdrop, contrast: contrast),
            detail: readable(on: backdrop, contrast: contrast * Self.detailContrastRatio),
            avatarFill: avatarFill,
            avatarText: readable(on: avatarFill, contrast: contrast),
            primaryActionFill: solid,
            primaryActionText: onSolid,
            quietActionFill: tint(0.26),
            quietActionText: readable(on: tint(0.26), contrast: Self.readableContrast)
        )
    }
}
