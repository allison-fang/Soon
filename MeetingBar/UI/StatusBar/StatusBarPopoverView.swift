//
//  StatusBarPopoverView.swift
//  MeetingBar
//

import AppKit
import SwiftUI

struct StatusBarPopoverActions {
    var join: @MainActor (MBEvent) -> Void = { _ in }
    var joinCandidate: @MainActor (MeetingLinkCandidate) -> Void = { _ in }
    var copyLink: @MainActor (MBEvent) -> Void = { _ in }
    var dismiss: @MainActor (MBEvent) -> Void = { _ in }
    var undismiss: @MainActor (MBEvent) -> Void = { _ in }
    var openInCalendar: @MainActor (URL) -> Void = { _ in }
    var openInFantastical: @MainActor (MBEvent) -> Void = { _ in }
    var openCalendarApp: @MainActor (TimelineCalendarApp) -> Void = { _ in }
    var performNotice: @MainActor (StatusBarNoticeAction) -> Void = { _ in }
    var refresh: @MainActor () -> Void = {}
    var openPreferences: @MainActor () -> Void = {}
    var openUpdateSettings: @MainActor () -> Void = {}
    var quit: @MainActor () -> Void = {}
}

@MainActor
final class StatusBarPopoverModel: ObservableObject {
    @Published var presentation = StatusBarPopoverPresentation()
    @Published var highlightedEventID: String?

    var maxTimelineHeight: CGFloat = 520
    #if DEBUG
        /// Offscreen rendering can't blur, so screenshots get solid chrome and no debug frame.
        var rendersForScreenshot = false
    #endif
    var actions = StatusBarPopoverActions()
    var onEventHover: @MainActor (String, Bool) -> Void = { _, _ in }
    var onEventClick: @MainActor (String) -> Void = { _ in }
    var onZoom: @MainActor (TimelineZoom) -> Void = { _ in }

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

    func scroll(toOffset offset: CGFloat) {
        anchors.objectEnumerator()?.allObjects
            .lazy.compactMap { ($0 as? NSView)?.enclosingScrollView }.first?
            .scrollDocument(toVisibleTop: offset)
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
    static let scrollSpace = "timeline.scroll"
}

struct TimelineMetrics {
    let width: CGFloat = 372
    let trailingInset: CGFloat = 10
    let edgeInset: CGFloat = 12
    let cardGap: CGFloat = 1
    let cardCornerRadius: CGFloat = 5
    let cardHorizontalPadding: CGFloat = 6
    let cardVerticalPadding: CGFloat = 3
    let cardRowHeight: CGFloat = 16
    let cardRowSpacing: CGFloat = 1
    let cardTitleSize: CGFloat = 12
    let cardDetailSize: CGFloat = 10.5
    let avatarSize: CGFloat = 16
    let joinHeight: CGFloat = 16
    let allDayRowHeight: CGFloat = 22
    let allDayRowSpacing: CGFloat = 2
    let dayTitleHeight: CGFloat = 18
    let dayHeaderSpacing: CGFloat = 6
    let dayHeaderVerticalPadding: CGFloat = 8
    let dayHeaderFadeHeight: CGFloat = 16
    let emptyDayHeight: CGFloat = 64
    let maxTimelineHeight: CGFloat = 540
    let footerHeight: CGFloat = 34
    let topBarTopPadding: CGFloat = 8
    /// Small, so the pinned day header below reads as part of the top bar.
    let topBarBottomPadding: CGFloat = 2
    let detailsWidth: CGFloat = 320
    let detailsPadding: CGFloat = 14
    let detailsSpacing: CGFloat = 12
    let detailsRowSpacing: CGFloat = 6
    let detailsAvatarSize: CGFloat = 22
    let hourLabelHeight: CGFloat = 12

    /// Hour labels are centered on their line, so the first and last stick
    /// out by half a label; this leaves the day header's padding beyond that.
    var gridVerticalInset: CGFloat {
        dayHeaderVerticalPadding + hourLabelHeight / 2
    }

    var bottomChromeHeight: CGFloat { footerHeight + 4 + 1 }

    var twoRowCardHeight: CGFloat {
        cardRowHeight * 2 + cardRowSpacing + cardVerticalPadding * 2
    }

    /// Sticky, so scrolling to a card has to clear it.
    func dayHeaderHeight(_ day: TimelineDayPresentation) -> CGFloat {
        let rows = min(day.allDayEvents.count, TimelineGrid.maxAllDayRows)
        let allDay = rows == 0 ? 0 : dayHeaderSpacing + CGFloat(rows) * allDayRowHeight - allDayRowSpacing
        return dayHeaderVerticalPadding * 2 + dayTitleHeight + allDay + 1
    }

    func dayBodyHeight(_ day: TimelineDayPresentation) -> CGFloat {
        if day.emptyMessage != nil { return emptyDayHeight }
        return day.gridHeight > 0 ? CGFloat(day.gridHeight) + gridVerticalInset * 2 : 0
    }

    /// Includes the divider after each day but the last.
    func timelineHeight(_ days: [TimelineDayPresentation]) -> CGFloat {
        days.reduce(CGFloat(0)) { $0 + dayHeaderHeight($1) + dayBodyHeight($1) + 1 } - (days.isEmpty ? 0 : 1)
    }

    /// Where to scroll so an event shows just below its pinned day header.
    /// The timeline is lazy, so later days have no views to ask until then.
    func scrollOffset(toShow eventID: String, in days: [TimelineDayPresentation]) -> CGFloat? {
        var dayTop: CGFloat = 0
        for day in days {
            if day.allDayEvents.contains(where: { $0.id == eventID }) {
                return dayTop
            }
            if let placed = day.timedEvents.first(where: { $0.id == eventID }) {
                return dayTop + gridVerticalInset + CGFloat(placed.placement.top)
            }
            dayTop += dayHeaderHeight(day) + dayBodyHeight(day) + 1
        }
        return nil
    }
}

struct StatusBarPopoverView: View {
    @ObservedObject var model: StatusBarPopoverModel

    private var presentation: StatusBarPopoverPresentation { model.presentation }
    private let metrics = TimelineMetrics()
    @State private var topChromeHeight: CGFloat = 0

    private var chromeMaterial: AnyShapeStyle {
        #if DEBUG
            if model.rendersForScreenshot {
                return AnyShapeStyle(Color(nsColor: .windowBackgroundColor))
            }
        #endif
        return AnyShapeStyle(.regularMaterial)
    }

    var body: some View {
        Group {
            if presentation.days.isEmpty {
                VStack(spacing: 0) {
                    topBar
                        .background(chromeMaterial)
                    if let notice = presentation.notice {
                        Divider()
                        TimelineUnavailableState(notice: notice) {
                            model.actions.performNotice(notice.action)
                        }
                    }
                    bottomChrome
                }
            } else {
                timeline
            }
        }
        .frame(width: metrics.width)
        #if DEBUG
            .overlay(
                RoundedRectangle(cornerRadius: StatusBarPopoverController.cornerRadius)
                    .strokeBorder(Color.orange, lineWidth: model.rendersForScreenshot ? 0 : 2)
                    .allowsHitTesting(false)
            )
        #endif
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            if presentation.timelineHeight > 0 {
                SegmentedButtons(segments: [
                    zoomSegment(
                        to: presentation.zoom.zoomedOut,
                        systemImage: "minus.magnifyingglass",
                        title: "status_bar_popover_zoom_out".loco()
                    ),
                    zoomSegment(
                        to: presentation.zoom.zoomedIn,
                        systemImage: "plus.magnifyingglass",
                        title: "status_bar_popover_zoom_in".loco()
                    )
                ])
                .fixedSize()
            }
            Spacer(minLength: 0)
            settingsButton
        }
        .controlSize(.small)
        .padding(.horizontal, metrics.edgeInset)
        .padding(.top, metrics.topBarTopPadding)
        .padding(.bottom, metrics.topBarBottomPadding)
    }

    private func zoomSegment(to zoom: TimelineZoom?, systemImage: String, title: String) -> SegmentedButtons.Segment {
        SegmentedButtons.Segment(title: title, systemImage: systemImage, isEnabled: zoom != nil) {
            if let zoom { model.onZoom(zoom) }
        }
    }

    /// An available update has no room of its own, so Settings carries it.
    private var settingsButton: some View {
        let update = presentation.updateAvailableText
        return Button {
            if update == nil {
                model.actions.openPreferences()
            } else {
                model.actions.openUpdateSettings()
            }
        } label: {
            Label("status_bar_preferences".loco(), systemImage: "gearshape")
        }
        .buttonStyle(.bordered)
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(Color.accentColor)
                .frame(width: 7, height: 7)
                .offset(x: 2, y: -2)
                .opacity(update == nil ? 0 : 1)
                .accessibilityHidden(true)
        }
        .fixedSize()
        .help(update ?? "status_bar_preferences".loco())
        .accessibilityValue(update ?? "")
    }

    private func dayHeader(_ day: TimelineDayPresentation) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: metrics.dayHeaderSpacing) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(day.title)
                        .font(.system(size: 13, weight: .semibold))
                    Text(day.dateText)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .frame(height: metrics.dayTitleHeight)
                allDayEvents(day)
            }
            .padding(.horizontal, metrics.edgeInset)
            .padding(.vertical, metrics.dayHeaderVerticalPadding)
            Divider()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .mask(dayHeaderMask)
        .background(dayHeaderBackground)
        .accessibilityElement(children: .contain)
    }

    /// The top bar has no blur of its own, so a header being pushed off has
    /// to disappear under it rather than show through. The scroll space
    /// starts below the top bar: 0 is pinned, below 0 is being pushed off.
    private var dayHeaderMask: some View {
        GeometryReader { proxy in
            let hidden = min(max(-proxy.frame(in: .named(TimelineGrid.scrollSpace)).minY, 0), proxy.size.height)
            VStack(spacing: 0) {
                Color.clear.frame(height: hidden)
                // Grows in as the header leaves, so a pinned header has no fade.
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: min(hidden, metrics.dayHeaderFadeHeight))
                Rectangle()
            }
        }
    }

    /// The pinned header's blur also fills the top bar, so the two share one
    /// blur. A header being pushed off keeps that top-bar blur but loses its
    /// own above the top bar's edge, so the bar never blurs the leaving header.
    private var dayHeaderBackground: some View {
        GeometryReader { proxy in
            let top = proxy.frame(in: .named(TimelineGrid.scrollSpace)).minY
            let height = proxy.size.height
            let isPinned = top <= 0.5 && top > -height
            let start = isPinned ? -top - topChromeHeight : max(-top, 0)
            Rectangle()
                .fill(chromeMaterial)
                .frame(height: max(height - start, 0))
                .offset(y: start)
        }
        .allowsHitTesting(false)
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

    /// Each day's header stays pinned while that day scrolls by, until the
    /// next day's header pushes it off. The bars float over the timeline so it
    /// blurs under them; the top bar takes its blur from the pinned header.
    private var timeline: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(presentation.days) { day in
                    Section(header: dayHeader(day)) {
                        dayBody(day)
                        if day.id != presentation.days.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
        .coordinateSpace(name: TimelineGrid.scrollSpace)
        .safeAreaInset(edge: .top, spacing: 0) { topChrome }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomChrome }
        .frame(
            height: min(metrics.timelineHeight(presentation.days), model.maxTimelineHeight)
                + topChromeHeight + metrics.bottomChromeHeight
        )
    }

    private var topChrome: some View {
        VStack(spacing: 0) {
            topBar
            if let notice = presentation.notice {
                TimelineNoticeBanner(notice: notice, metrics: metrics) {
                    model.actions.performNotice(notice.action)
                }
                Divider()
            }
        }
        .background(GeometryReader { proxy in
            Color.clear.preference(key: TopChromeHeightKey.self, value: proxy.size.height)
        })
        .onPreferenceChange(TopChromeHeightKey.self) { topChromeHeight = $0 }
    }

    private var bottomChrome: some View {
        VStack(spacing: 0) {
            Divider()
            footer
        }
        .background(chromeMaterial)
    }

    @ViewBuilder
    private func dayBody(_ day: TimelineDayPresentation) -> some View {
        if let message = day.emptyMessage {
            Text(message)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: metrics.emptyDayHeight)
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
        .frame(height: metrics.hourLabelHeight)
        .padding(.top, CGFloat(label.offset) - metrics.hourLabelHeight / 2)
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
            onClick: { model.onEventClick(event.id) },
            onHover: { model.onEventHover(event.id, $0) },
            registerAnchor: { model.registerAnchor($0, id: event.id) }
        )
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button(action: model.actions.refresh) {
                Label("general_refresh".loco(), systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .fixedSize()
            if let updated = presentation.lastUpdatedText {
                Text(updated)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Menu {
                Button {
                    model.actions.openCalendarApp(presentation.calendarApp)
                } label: {
                    Label(openCalendarAppTitle, systemImage: "arrow.up.right.square")
                }
                Divider()
                Button(action: model.actions.quit) {
                    Label("status_bar_quit".loco(), systemImage: "power")
                }
            } label: {
                // A menu button sets its icon right against the title, unlike other buttons.
                Label {
                    Text("status_bar_popover_more".loco())
                } icon: {
                    Image(nsImage: .paddedSymbol("ellipsis.circle", trailing: 6))
                }
            }
            .menuStyle(.borderedButton)
            .fixedSize()
        }
        .controlSize(.small)
        .padding(.horizontal, metrics.edgeInset)
        .frame(height: metrics.footerHeight + 4)
    }

    private var openCalendarAppTitle: String {
        switch presentation.calendarApp {
        case .googleCalendar: "status_bar_popover_open_google_calendar".loco()
        case .fantastical: "status_bar_popover_open_fantastical".loco()
        case .calendar: "status_bar_popover_open_calendar".loco()
        }
    }
}

/// Quiet secondary actions: clearly buttons, never louder than Join.
struct TimelineButtonStyle: ButtonStyle {
    var isIconOnly = false
    var tint: Color?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(TimelineButtonLook(isPressed: configuration.isPressed, isIconOnly: isIconOnly, tint: tint))
    }
}

struct TimelineButtonLook: ViewModifier {
    let isPressed: Bool
    var isIconOnly = false
    var tint: Color?

    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content
            .font(.system(size: 11.5, weight: .medium))
            .foregroundColor(Color.primary.opacity(isEnabled ? 1 : 0.3))
            .lineLimit(1)
            .padding(.horizontal, isIconOnly ? 0 : 9)
            .frame(width: isIconOnly ? 24 : nil, height: 24)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(tint.map { $0.opacity(isPressed ? 0.32 : 0.2) } ?? Color.primary.opacity(isPressed ? 0.14 : 0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(tint.map { $0.opacity(0.4) } ?? Color.primary.opacity(0.1), lineWidth: 0.5)
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

/// Joined buttons, each with an icon and a title. AppKit sets a segment's icon
/// about 4pt from its edge but leaves about 10pt after the title, so each icon
/// carries the difference.
struct SegmentedButtons: NSViewRepresentable {
    struct Segment {
        let title: String
        let systemImage: String
        let isEnabled: Bool
        let action: () -> Void
    }

    let segments: [Segment]

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl()
        control.trackingMode = .momentary
        control.controlSize = .small
        control.font = .systemFont(ofSize: NSFont.systemFontSize(for: .small))
        control.target = context.coordinator
        control.action = #selector(Coordinator.select(_:))
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.segments = segments
        control.segmentCount = segments.count
        for (index, segment) in segments.enumerated() {
            control.setLabel(segment.title, forSegment: index)
            control.setImage(.paddedSymbol(segment.systemImage, leading: 6.5), forSegment: index)
            control.setEnabled(segment.isEnabled, forSegment: index)
            control.setToolTip(segment.title, forSegment: index)
        }
    }

    final class Coordinator: NSObject {
        var segments: [Segment] = []

        @objc func select(_ control: NSSegmentedControl) {
            guard segments.indices.contains(control.selectedSegment) else { return }
            segments[control.selectedSegment].action()
        }
    }
}

extension NSImage {
    /// A template SF Symbol at small-control size with transparent room on either side.
    static func paddedSymbol(_ name: String, leading: CGFloat = 0, trailing: CGFloat = 0) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: NSFont.systemFontSize(for: .small), weight: .regular)
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        else { return NSImage() }
        let size = NSSize(width: symbol.size.width + leading + trailing, height: symbol.size.height)
        let image = NSImage(size: size, flipped: false) { _ in
            symbol.draw(in: NSRect(origin: NSPoint(x: leading, y: 0), size: symbol.size))
            return true
        }
        image.isTemplate = true
        return image
    }
}

private struct TopChromeHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
