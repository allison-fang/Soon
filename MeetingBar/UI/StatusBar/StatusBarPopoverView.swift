//
//  StatusBarPopoverView.swift
//  MeetingBar
//

import AppKit
import SwiftUI

struct StatusBarPopoverActions {
    var join: @MainActor (MBEvent) -> Void = { _ in }
    var joinCandidate: @MainActor (MeetingLinkCandidate) -> Void = { _ in }
    var joinBookmark: @MainActor (Bookmark) -> Void = { _ in }
    var copyLink: @MainActor (MBEvent) -> Void = { _ in }
    var dismiss: @MainActor (MBEvent) -> Void = { _ in }
    var undismiss: @MainActor (MBEvent) -> Void = { _ in }
    var openInCalendar: @MainActor (URL) -> Void = { _ in }
    var openInFantastical: @MainActor (MBEvent) -> Void = { _ in }
    var performNotice: @MainActor (StatusBarNoticeAction) -> Void = { _ in }
    var refresh: @MainActor () -> Void = {}
    var openPreferences: @MainActor () -> Void = {}
    var quit: @MainActor () -> Void = {}
}

@MainActor
final class StatusBarPopoverModel: ObservableObject {
    @Published var presentation = StatusBarPopoverPresentation()
    @Published var highlightedEventID: String?

    var maxTimelineHeight: CGFloat = 520
    var actions = StatusBarPopoverActions()
    var onEventHover: @MainActor (String, Bool) -> Void = { _, _ in }

    private let anchors = NSMapTable<NSString, TimelineAnchorView>.strongToWeakObjects()

    func registerAnchor(_ view: TimelineAnchorView, id: String) {
        anchors.setObject(view, forKey: id as NSString)
    }

    func anchor(id: String) -> TimelineAnchorView? {
        anchors.object(forKey: id as NSString)
    }

    func removeAllAnchors() {
        anchors.removeAllObjects()
    }

    func scrollToNow() {
        anchor(id: TimelineGrid.nowAnchorID)?.scrollToViewportPosition(TimelineGrid.nowViewportPosition)
    }
}

enum TimelineGrid {
    static let gutter: CGFloat = 52
    static let maxAllDayRows = 3
    static let nowViewportPosition: CGFloat = 0.25
    static let nowAnchorID = "timeline.now"
}

/// Everything Compact and Comfortable disagree on.
struct TimelineMetrics {
    let width: CGFloat
    let trailingInset: CGFloat
    let edgeInset: CGFloat
    let gridVerticalInset: CGFloat
    let cardGap: CGFloat
    let cardCornerRadius: CGFloat
    let cardHorizontalPadding: CGFloat
    let cardVerticalPadding: CGFloat
    let cardRowHeight: CGFloat
    let cardRowSpacing: CGFloat
    let cardTitleSize: CGFloat
    let cardDetailSize: CGFloat
    let avatarSize: CGFloat
    let joinHeight: CGFloat
    let allDayRowHeight: CGFloat
    let allDayRowSpacing: CGFloat
    let maxTimelineHeight: CGFloat
    let footerHeight: CGFloat
    let detailsWidth: CGFloat
    let detailsPadding: CGFloat
    let detailsSpacing: CGFloat
    let detailsRowSpacing: CGFloat
    let detailsAvatarSize: CGFloat

    var twoRowCardHeight: CGFloat {
        cardRowHeight * 2 + cardRowSpacing + cardVerticalPadding * 2
    }

    var threeRowCardHeight: CGFloat {
        cardRowHeight * 3 + cardRowSpacing * 2 + cardVerticalPadding * 2
    }

    init(density: TimelineDensity) {
        let isCompact = density == .compact
        width = isCompact ? 372 : 396
        trailingInset = isCompact ? 10 : 14
        edgeInset = isCompact ? 12 : 14
        gridVerticalInset = isCompact ? 10 : 14
        cardGap = isCompact ? 1 : 2
        cardCornerRadius = isCompact ? 5 : 7
        cardHorizontalPadding = isCompact ? 6 : 10
        cardVerticalPadding = isCompact ? 3 : 6
        cardRowHeight = isCompact ? 16 : 18
        cardRowSpacing = isCompact ? 1 : 3
        cardTitleSize = isCompact ? 12 : 12.5
        cardDetailSize = isCompact ? 10.5 : 11
        avatarSize = isCompact ? 16 : 18
        joinHeight = isCompact ? 16 : 18
        allDayRowHeight = isCompact ? 22 : 28
        allDayRowSpacing = isCompact ? 2 : 4
        maxTimelineHeight = isCompact ? 540 : 600
        footerHeight = isCompact ? 34 : 38
        detailsWidth = isCompact ? 320 : 340
        detailsPadding = isCompact ? 14 : 18
        detailsSpacing = isCompact ? 12 : 16
        detailsRowSpacing = isCompact ? 6 : 9
        detailsAvatarSize = isCompact ? 22 : 24
    }
}

struct StatusBarPopoverView: View {
    @ObservedObject var model: StatusBarPopoverModel

    private var presentation: StatusBarPopoverPresentation { model.presentation }
    private var metrics: TimelineMetrics { TimelineMetrics(density: presentation.density) }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            if presentation.days.isEmpty, let notice = presentation.notice {
                TimelineUnavailableState(notice: notice) {
                    model.actions.performNotice(notice.action)
                }
            } else {
                if let notice = presentation.notice {
                    TimelineNoticeBanner(notice: notice, metrics: metrics) {
                        model.actions.performNotice(notice.action)
                    }
                    Divider()
                }
                if let today = presentation.days.first {
                    if !today.allDayEvents.isEmpty {
                        allDayEvents(today)
                            .padding(.horizontal, metrics.edgeInset)
                            .padding(.vertical, metrics.gridVerticalInset - 4)
                        Divider()
                    }
                    timeline(today: today)
                }
            }
            Divider()
            footer
        }
        .frame(width: metrics.width)
    }

    /// Freshness and Refresh sit with the date they describe.
    private var topBar: some View {
        HStack(alignment: .center, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(presentation.title)
                    .font(.system(size: 13, weight: .semibold))
                Text(presentation.dateText)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
            if let updated = presentation.lastUpdatedText {
                Text(updated)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Button(action: model.actions.refresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(TimelineButtonStyle(isIconOnly: true))
            .help("general_refresh".loco())
            .accessibilityLabel("general_refresh".loco())
        }
        .padding(.horizontal, metrics.edgeInset)
        .frame(height: metrics.footerHeight + 4)
    }

    private func dayHeader(_ day: TimelineDayPresentation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(day.title)
                    .font(.system(size: 13, weight: .semibold))
                Text(day.dateText)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            allDayEvents(day)
        }
        .padding(.horizontal, metrics.edgeInset)
        .padding(.top, metrics.gridVerticalInset)
        .padding(.bottom, metrics.gridVerticalInset - 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func allDayEvents(_ day: TimelineDayPresentation) -> some View {
        if !day.allDayEvents.isEmpty {
            let rows = VStack(spacing: metrics.allDayRowSpacing) {
                ForEach(day.allDayEvents) { event in
                    card(
                        event,
                        size: CGSize(
                            width: metrics.width - metrics.edgeInset * 2,
                            height: metrics.allDayRowHeight - metrics.allDayRowSpacing
                        )
                    )
                }
            }
            if day.allDayEvents.count > TimelineGrid.maxAllDayRows {
                ScrollView(showsIndicators: false) { rows }
                    .frame(height: metrics.allDayRowHeight * CGFloat(TimelineGrid.maxAllDayRows))
            } else {
                rows
            }
        }
    }

    private var scrollHeight: CGFloat {
        presentation.days.enumerated().reduce(CGFloat(0)) { total, entry in
            total + dayContentHeight(entry.element, isFirst: entry.offset == 0)
        }
    }

    private func dayContentHeight(_ day: TimelineDayPresentation, isFirst: Bool) -> CGFloat {
        let allDayRows = isFirst ? 0 : min(day.allDayEvents.count, TimelineGrid.maxAllDayRows)
        let header = isFirst
            ? 0
            : 40 + metrics.gridVerticalInset + CGFloat(allDayRows) * metrics.allDayRowHeight
        let body: CGFloat
        if day.emptyMessage != nil {
            body = 64
        } else if day.gridHeight > 0 {
            body = CGFloat(day.gridHeight) + metrics.gridVerticalInset * 2
        } else {
            body = 0
        }
        return header + body
    }

    private func timeline(today: TimelineDayPresentation) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                dayBody(today)
                ForEach(presentation.days.dropFirst()) { day in
                    Divider()
                    dayHeader(day)
                    dayBody(day)
                }
            }
        }
        .frame(height: min(scrollHeight, model.maxTimelineHeight))
    }

    @ViewBuilder
    private func dayBody(_ day: TimelineDayPresentation) -> some View {
        if let message = day.emptyMessage {
            Text(message)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 64)
        } else if day.gridHeight > 0 {
            grid(day)
        }
    }

    private func grid(_ day: TimelineDayPresentation) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(day.hourLabels) { label in
                hourLine(label, isNearNow: isNearNow(label, in: day))
            }
            ForEach(day.timedEvents) { placed in
                let frame = cardFrame(placed.placement)
                card(placed.event, size: frame.size)
                    .padding(.leading, frame.minX)
                    .padding(.top, frame.minY)
            }
            if let now = day.now {
                nowIndicator(now)
            }
        }
        .frame(
            width: metrics.width,
            height: CGFloat(day.gridHeight),
            alignment: .topLeading
        )
        .padding(.vertical, metrics.gridVerticalInset)
    }

    private func isNearNow(_ label: TimelineHourLabel, in day: TimelineDayPresentation) -> Bool {
        guard let now = day.now else { return false }
        return abs(label.offset - now.offset) < 13
    }

    private func hourLine(_ label: TimelineHourLabel, isNearNow: Bool) -> some View {
        HStack(spacing: 6) {
            Text(label.text)
                .font(.system(size: 10).monospacedDigit())
                .foregroundColor(.secondary)
                .frame(width: TimelineGrid.gutter - 8, alignment: .trailing)
                .opacity(isNearNow ? 0 : 1)
            Rectangle()
                .fill(Color.primary.opacity(0.07))
                .frame(height: 1)
        }
        .frame(height: 12)
        .padding(.top, CGFloat(label.offset) - 6)
        .padding(.trailing, metrics.trailingInset)
    }

    private func nowIndicator(_ now: TimelineNowIndicator) -> some View {
        HStack(spacing: 2) {
            Text(now.text)
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .foregroundColor(.red)
                .lineLimit(1)
                .frame(width: TimelineGrid.gutter - 8, alignment: .trailing)
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
            Rectangle()
                .fill(Color.red)
                .frame(height: 1.5)
                .padding(.leading, -3)
        }
        .frame(height: 12)
        .background(
            TimelineAnchor(register: { model.registerAnchor($0, id: TimelineGrid.nowAnchorID) })
        )
        .padding(.top, CGFloat(now.offset) - 6)
        .padding(.trailing, metrics.trailingInset)
        .allowsHitTesting(false)
    }

    private func cardFrame(_ placement: TimelinePlacement) -> CGRect {
        let available = metrics.width - TimelineGrid.gutter - metrics.trailingInset
        let columnWidth = available / CGFloat(max(placement.columnCount, 1))
        return CGRect(
            x: TimelineGrid.gutter + columnWidth * CGFloat(placement.column),
            y: CGFloat(placement.top) + metrics.cardGap,
            width: columnWidth - metrics.cardGap * 2,
            height: CGFloat(placement.height) - metrics.cardGap * 2
        )
    }

    private func card(_ event: TimelineEventPresentation, size: CGSize) -> some View {
        TimelineEventCard(
            event: event,
            size: size,
            metrics: metrics,
            isHighlighted: model.highlightedEventID == event.id,
            onJoin: { model.actions.join(event.event) },
            onHover: { model.onEventHover(event.id, $0) },
            registerAnchor: { model.registerAnchor($0, id: event.id) }
        )
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button(action: model.actions.openPreferences) {
                Label("status_bar_preferences".loco(), systemImage: "gearshape")
            }
            if !presentation.bookmarks.isEmpty {
                bookmarksMenu
            }
            Spacer(minLength: 0)
            Button(action: model.actions.quit) {
                Label("status_bar_popover_quit".loco(), systemImage: "power")
            }
        }
        .buttonStyle(TimelineButtonStyle())
        .padding(.horizontal, metrics.edgeInset)
        .frame(height: metrics.footerHeight + 4)
    }

    private var bookmarksMenu: some View {
        Menu("status_bar_section_bookmarks_title".loco()) {
            ForEach(presentation.bookmarks, id: \.self) { bookmark in
                Button(bookmark.name) { model.actions.joinBookmark(bookmark) }
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

/// Quiet secondary actions: clearly buttons, never louder than Join.
struct TimelineButtonStyle: ButtonStyle {
    var isIconOnly = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(TimelineButtonLook(isPressed: configuration.isPressed, isIconOnly: isIconOnly))
    }
}

struct TimelineButtonLook: ViewModifier {
    let isPressed: Bool
    var isIconOnly = false

    func body(content: Content) -> some View {
        content
            .font(.system(size: 11.5, weight: .medium))
            .foregroundColor(.primary)
            .lineLimit(1)
            .padding(.horizontal, isIconOnly ? 0 : 9)
            .frame(width: isIconOnly ? 24 : nil, height: 24)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(isPressed ? 0.14 : 0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6))
    }
}

/// Shown instead of the timeline when the calendar can't be read: an empty
/// grid there would look like a free day.
private struct TimelineUnavailableState: View {
    let notice: StatusBarNotice
    let action: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28))
                .foregroundColor(.orange)
            Text(notice.title)
                .font(.system(size: 13, weight: .semibold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button(notice.actionTitle, action: action)
                .buttonStyle(TimelineButtonStyle())
                .padding(.top, 2)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 36)
        .frame(maxWidth: .infinity)
    }
}

private struct TimelineNoticeBanner: View {
    let notice: StatusBarNotice
    let metrics: TimelineMetrics
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(notice.title, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
            Button(notice.actionTitle, action: action)
                .buttonStyle(.link)
                .font(.system(size: 12))
                .padding(.leading, 22)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, metrics.edgeInset)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.14))
    }
}
