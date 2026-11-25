//
//  TimelineEventCard.swift
//  MeetingBar
//

import AppKit
import SwiftUI

extension Color {
    init(_ rgb: TimelineRGB) {
        self.init(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: 1)
    }
}

extension TimelineRGB {
    init(_ color: NSColor) {
        let srgb = color.usingColorSpace(.sRGB) ?? .gray
        self.init(
            red: Double(srgb.redComponent),
            green: Double(srgb.greenComponent),
            blue: Double(srgb.blueComponent)
        )
    }
}

/// Past and dismissed events stay in their calendar's color, only quieter.
func timelineCardColors(
    for response: TimelineEventResponse,
    calendarColor: NSColor,
    colorScheme: ColorScheme,
    isDimmed: Bool = false
) -> TimelineCardColors {
    TimelinePalette(
        calendar: TimelineRGB(calendarColor),
        scheme: colorScheme == .dark ? .dark : .light
    )
    .colors(for: response, isDimmed: isDimmed)
}

struct TimelineStripes: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            var path = Path()
            var x = -size.height
            while x < size.width {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += 11
            }
            context.stroke(path, with: .color(color), lineWidth: 5)
        }
    }
}

/// Fill and border of a card in a given state, shared with the details chip.
struct TimelineCardBackground: View {
    let colors: TimelineCardColors
    let cornerRadius: CGFloat

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius)
    }

    var body: some View {
        ZStack {
            Color(colors.background)
            if let stripes = colors.stripes {
                TimelineStripes(color: Color(stripes))
            }
        }
        .clipShape(shape)
        .overlay {
            if let border = colors.border {
                shape.strokeBorder(Color(border), lineWidth: 1)
            }
        }
    }
}

struct TimelineAvatar: View {
    let guest: TimelineGuest
    let fill: Color
    let text: Color
    var size: CGFloat = 16
    var ring: Color?

    var body: some View {
        Text(guest.initial)
            .font(.system(size: size * 0.52, weight: .semibold))
            .foregroundColor(text)
            .lineLimit(1)
            .frame(width: size, height: size)
            .background(Circle().fill(fill))
            .overlay {
                if let ring {
                    Circle().stroke(ring, lineWidth: 1.5)
                }
            }
    }
}

struct TimelineAvatarStack: View {
    private static let maxVisible = 3

    let guests: [TimelineGuest]
    let colors: TimelineCardColors
    let size: CGFloat

    private var overflow: Int { max(guests.count - Self.maxVisible, 0) }

    var body: some View {
        HStack(spacing: -4) {
            ForEach(guests.prefix(Self.maxVisible)) { guest in
                TimelineAvatar(
                    guest: guest,
                    fill: Color(colors.avatarFill),
                    text: Color(colors.avatarText),
                    size: size,
                    ring: Color(colors.background)
                )
            }
            if overflow > 0 {
                Text("+\(overflow)")
                    .font(.system(size: size * 0.6, weight: .semibold))
                    .foregroundColor(Color(colors.detail))
                    .padding(.leading, 7)
            }
        }
        .accessibilityHidden(true)
    }
}

/// The icon alone on cards, so every card looks the same whatever its size;
/// spelled out in the details panel.
struct TimelineJoinButton: View {
    enum Size {
        case card
        case details
    }

    let isPrimary: Bool
    var size: Size = .card
    let colors: TimelineCardColors
    let metrics: TimelineMetrics
    let action: () -> Void

    private var title: String { "notifications_meetingbar_join_event_action".loco() }

    private var fill: TimelineRGB {
        isPrimary ? colors.primaryActionFill : colors.quietActionFill
    }

    private var text: TimelineRGB {
        isPrimary ? colors.primaryActionText : colors.quietActionText
    }

    private var height: CGFloat { size == .card ? metrics.joinHeight : 24 }
    private var iconSize: CGFloat { size == .card ? 9 : 10 }
    private var horizontalPadding: CGFloat { size == .card ? 5 : 12 }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "video.fill")
                    .font(.system(size: iconSize, weight: .semibold))
                if size == .details {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, horizontalPadding)
            .foregroundColor(Color(text))
            .frame(height: height)
            .background(Capsule().fill(Color(fill)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help(title)
        .accessibilityLabel(title)
    }
}

/// Draws one event at a size derived from its duration, showing as much as
/// that height can carry.
struct TimelineEventCard: View {
    let event: TimelineEventPresentation
    let size: CGSize
    let metrics: TimelineMetrics
    let isHighlighted: Bool
    let onJoin: () -> Void
    let onClick: () -> Void
    let onHover: (Bool) -> Void
    let registerAnchor: (TimelineAnchorView) -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var isDimmed: Bool { event.phase == .past || event.isDismissed }

    private var colors: TimelineCardColors {
        timelineCardColors(
            for: event.response,
            calendarColor: event.event.calendar.color,
            colorScheme: colorScheme,
            isDimmed: isDimmed
        )
    }

    private var isPrimaryJoin: Bool {
        (event.isNext || event.phase == .current) && !isDimmed && event.response != .declined
    }

    private var otherGuests: [TimelineGuest] { event.guests.filter { !$0.isCurrentUser } }

    private var fit: TimelineCardContent {
        TimelineCardContent(
            width: size.width,
            height: size.height,
            twoRowHeight: metrics.twoRowCardHeight,
            hasCountdown: event.countdown != nil,
            hasGuests: !otherGuests.isEmpty
        )
    }

    var body: some View {
        let fit = fit
        return content(fit)
            .padding(.horizontal, metrics.cardHorizontalPadding)
            .padding(.vertical, fit.rows == 1 ? 0 : metrics.cardVerticalPadding)
            .frame(
                width: size.width,
                height: size.height,
                alignment: fit.rows == 1 ? .leading : .topLeading
            )
            .background(TimelineCardBackground(colors: colors, cornerRadius: metrics.cardCornerRadius))
            .overlay(highlight)
            .contentShape(RoundedRectangle(cornerRadius: metrics.cardCornerRadius))
            .onTapGesture(perform: onClick)
            .background(TimelineAnchor(onHover: onHover, register: registerAnchor))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(TimelineEventAccessibility.label(for: event))
            .accessibilityAddTraits(event.canJoin ? .isButton : [])
            .accessibilityAction {
                if event.canJoin { onJoin() }
            }
    }

    @ViewBuilder
    private func content(_ fit: TimelineCardContent) -> some View {
        if fit.rows == 1 {
            titleRow(fit)
        } else {
            VStack(alignment: .leading, spacing: metrics.cardRowSpacing) {
                titleRow(fit)
                detailRow(showsAvatars: fit.showsAvatars)
            }
        }
    }

    private func titleRow(_ fit: TimelineCardContent) -> some View {
        HStack(spacing: 6) {
            titleText
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let countdown = event.countdown, fit.showsCountdown {
                Text(countdown)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color(colors.detail))
                    .lineLimit(1)
                    .fixedSize()
            }
            if event.canJoin {
                TimelineJoinButton(
                    isPrimary: isPrimaryJoin,
                    colors: colors,
                    metrics: metrics,
                    action: onJoin
                )
            }
        }
        .frame(height: metrics.cardRowHeight)
    }

    private var titleText: Text {
        let text = Text(event.title)
            .font(.system(size: metrics.cardTitleSize, weight: .semibold))
            .foregroundColor(Color(colors.title))
        return event.response == .declined ? text.strikethrough() : text
    }

    private func detailRow(showsAvatars: Bool) -> some View {
        HStack(spacing: 6) {
            if let description = event.descriptionPreview {
                detailText(description)
            }
            Spacer(minLength: 0)
            if showsAvatars {
                TimelineAvatarStack(guests: otherGuests, colors: colors, size: metrics.avatarSize)
            }
        }
        .frame(height: metrics.cardRowHeight)
    }

    private func detailText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: metrics.cardDetailSize))
            .foregroundColor(Color(colors.detail))
            .lineLimit(1)
            .truncationMode(.tail)
    }

    @ViewBuilder
    private var highlight: some View {
        if isHighlighted {
            RoundedRectangle(cornerRadius: metrics.cardCornerRadius)
                .strokeBorder(Color(colors.title).opacity(0.7), lineWidth: 1.5)
        }
    }
}

/// The grid conveys time and response visually, so spoken labels state them.
@MainActor
enum TimelineEventAccessibility {
    static func label(for event: TimelineEventPresentation) -> String {
        [event.title, timeText(for: event.event), responseText(for: event)]
            .joined(separator: ", ")
    }

    static func responseText(for event: TimelineEventPresentation) -> String {
        if event.isCanceled {
            return "status_bar_details_status_canceled".loco()
        }
        switch event.response {
        case .accepted: return "status_bar_details_status_accepted".loco()
        case .pending: return "status_bar_details_status_pending".loco()
        case .tentative: return "status_bar_details_status_tentative".loco()
        case .declined: return "status_bar_details_status_declined".loco()
        }
    }

    private static func timeText(for event: MBEvent) -> String {
        guard !event.isAllDay else { return "status_bar_event_start_time_all_day".loco() }
        let formatter = DateIntervalFormatter()
        formatter.locale = I18N.instance.locale
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: event.startDate, to: event.endDate)
    }
}

/// Bridges a piece of the timeline to AppKit. SwiftUI's `onHover` follows the
/// active app, but this panel never activates it, so hover needs a tracking
/// area that is always live. Scrolling goes through the same view because
/// `ScrollViewProxy` misplaces offset content on macOS.
struct TimelineAnchor: NSViewRepresentable {
    var onHover: ((Bool) -> Void)?
    var register: (TimelineAnchorView) -> Void = { _ in }

    func makeNSView(context _: Context) -> TimelineAnchorView {
        TimelineAnchorView()
    }

    func updateNSView(_ view: TimelineAnchorView, context _: Context) {
        view.onHover = onHover
        register(view)
    }
}

final class TimelineAnchorView: NSView {
    var onHover: ((Bool) -> Void)?
    private var trackingArea: NSTrackingArea?

    var screenFrame: NSRect? {
        window?.convertToScreen(convert(bounds, to: nil))
    }

    func scrollIntoView() {
        scrollToVisible(bounds)
    }

    /// Scrolls so this view sits `ratio` of the way down the visible area.
    func scrollToViewportPosition(_ ratio: CGFloat) {
        guard let scrollView = enclosingScrollView,
              let document = scrollView.documentView
        else { return }

        let clip = scrollView.contentView
        let frame = convert(bounds, to: document)
        let top = document.isFlipped ? frame.minY : document.bounds.maxY - frame.maxY
        let maxOffset = max(document.bounds.height - clip.bounds.height, 0)
        let offset = min(max(top - clip.bounds.height * ratio, 0), maxOffset)
        let y = document.isFlipped ? offset : maxOffset - offset
        clip.scroll(to: NSPoint(x: clip.bounds.minX, y: y))
        scrollView.reflectScrolledClipView(clip)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func hitTest(_: NSPoint) -> NSView? { nil }

    override func mouseEntered(with _: NSEvent) {
        onHover?(true)
    }

    override func mouseExited(with _: NSEvent) {
        onHover?(false)
    }
}
