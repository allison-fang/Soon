//
//  EventDetailsView.swift
//  MeetingBar
//

import AppKit
import SwiftUI

/// Details that are useful only sometimes, shown beside the timeline on hover.
/// The title and the actions stay put; only guests and notes scroll, so a long
/// attendee list can never push Join or the actions out of reach.
struct EventDetailsView: View {
    private static let gutter: CGFloat = 16
    private static let gutterSpacing: CGFloat = 10
    private static let minimumSectionsHeight: CGFloat = 120

    let event: TimelineEventPresentation
    let metrics: TimelineMetrics
    let timeFormat: TimeFormat
    let isFantasticalInstalled: Bool
    let actions: StatusBarPopoverActions
    /// `nil` lays the sections out at their natural height.
    var sectionsHeight: CGFloat?

    @Environment(\.colorScheme) private var colorScheme

    private var mbEvent: MBEvent { event.event }
    private var notes: String? {
        mbEvent.notes.map(cleanUpNotes).flatMap { $0.isEmpty ? nil : $0 }
    }

    private var stateColors: TimelineCardColors {
        timelineCardColors(
            for: event.response,
            calendarColor: mbEvent.calendar.color,
            colorScheme: colorScheme
        )
    }

    /// Guests take the hollow palette: they are not the event's state.
    private var neutralColors: TimelineCardColors {
        timelineCardColors(
            for: .pending,
            calendarColor: mbEvent.calendar.color,
            colorScheme: colorScheme
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: metrics.detailsSpacing) {
                header
                if mbEvent.meetingLink != nil {
                    joinSection
                }
            }
            .padding(metrics.detailsPadding)

            if hasSections {
                Divider()
                if let sectionsHeight {
                    ScrollView { sections }
                        .frame(height: sectionsHeight)
                } else {
                    sections
                }
            }

            Divider()
            eventActions
                .padding(.horizontal, metrics.detailsPadding)
                .padding(.vertical, metrics.detailsPadding - 4)
        }
        .font(.system(size: 12))
        .frame(width: metrics.detailsWidth, alignment: .leading)
    }

    /// Returns this view fitted to `maxHeight`, with its height.
    func fitted(maxHeight: CGFloat) -> (view: EventDetailsView, height: CGFloat) {
        let natural = NSHostingView(rootView: self).fittingSize.height
        guard natural > maxHeight else { return (self, natural) }

        let sectionsNatural = NSHostingView(rootView: measuredSections).fittingSize.height
        var fitted = self
        fitted.sectionsHeight = max(
            sectionsNatural - (natural - maxHeight),
            Self.minimumSectionsHeight
        )
        return (fitted, NSHostingView(rootView: fitted).fittingSize.height)
    }

    private var measuredSections: some View {
        sections
            .font(.system(size: 12))
            .frame(width: metrics.detailsWidth)
    }

    private var hasSections: Bool {
        visibleLocation != nil || !event.guests.isEmpty || unlistedOrganizer != nil || notes != nil
    }

    private var sections: some View {
        VStack(alignment: .leading, spacing: metrics.detailsSpacing) {
            if let location = visibleLocation {
                row(systemImage: "mappin.and.ellipse") {
                    linkedText(location)
                }
            }
            if !event.guests.isEmpty {
                guests
            }
            if let organizer = unlistedOrganizer {
                row(systemImage: "person.crop.circle") {
                    Text("status_bar_submenu_organizer_title".loco(organizer.name))
                }
            }
            if let notes {
                row(systemImage: "text.alignleft") {
                    linkedText(notes)
                }
            }
        }
        .padding(metrics.detailsPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Status sits with the title: it's primary, and the title is where a
    /// decline already shows as strikethrough.
    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 7) {
                titleText
                    .fixedSize(horizontal: false, vertical: true)
                stateChip
            }
            VStack(alignment: .leading, spacing: 6) {
                row(systemImage: "clock") {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(dateText)
                        if !mbEvent.isAllDay {
                            Text(timeText).foregroundColor(.secondary)
                        }
                    }
                }
                HStack(spacing: Self.gutterSpacing) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(neutralColors.primaryActionFill))
                        .frame(width: 11, height: 11)
                        .frame(width: Self.gutter)
                    Text(mbEvent.calendar.title)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if let url = mbEvent.calendarOpenURL {
                        Button {
                            actions.openInCalendar(url)
                        } label: {
                            Label(openInCalendarTitle(url), systemImage: "arrow.up.right.square")
                        }
                        .buttonStyle(TimelineButtonStyle())
                    }
                }
            }
        }
    }

    private var titleText: Text {
        let title = Text(event.title).font(.system(size: 15, weight: .semibold))
        return event.response == .declined ? title.strikethrough() : title
    }

    /// Repeats the card's look, so the panel confirms what the timeline showed.
    private var stateChip: some View {
        Text(TimelineEventAccessibility.responseText(for: event))
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundColor(Color(stateColors.title))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 7)
            .frame(height: 19)
            .background(TimelineCardBackground(colors: stateColors, cornerRadius: 4))
    }

    private var joinSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Image(nsImage: getIconForMeetingService(mbEvent.meetingLink?.service))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 14, height: 14)
                    .frame(width: Self.gutter)
                Text(event.linkPreview ?? "")
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                Button {
                    actions.copyLink(mbEvent)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(TimelineButtonStyle(isIconOnly: true))
                .help("status_bar_submenu_copy_meeting_link".loco())
                .accessibilityLabel("status_bar_submenu_copy_meeting_link".loco())
                if event.canJoin {
                    Button {
                        actions.join(mbEvent)
                    } label: {
                        Text("notifications_meetingbar_join_event_action".loco())
                            .fontWeight(.semibold)
                            .foregroundColor(Color(neutralColors.primaryActionText))
                            .padding(.horizontal, 12)
                            .frame(height: 24)
                            .background(Capsule().fill(Color(neutralColors.primaryActionFill)))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.leading, 8)
            .padding(.trailing, 4)
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(neutralColors.background)))

            if event.canJoin {
                ForEach(mbEvent.alternateMeetingLinkCandidates, id: \.self) { candidate in
                    Button(alternateLinkTitle(candidate)) {
                        actions.joinCandidate(candidate)
                    }
                    .buttonStyle(.link)
                    .padding(.leading, Self.gutter + Self.gutterSpacing)
                }
            }
        }
    }

    private var guests: some View {
        row(systemImage: "person.2") {
            VStack(alignment: .leading, spacing: metrics.detailsRowSpacing) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("status_bar_submenu_attendees_title".loco(event.guests.count))
                        .fontWeight(.medium)
                    Text(guestSummary)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                ForEach(event.guests) { guest in
                    guestRow(guest)
                }
            }
        }
    }

    private var guestSummary: String {
        let accepted = event.guests.filter { $0.status == .accepted }.count
        let declined = event.guests.filter { $0.status == .declined }.count
        return "status_bar_details_guests_summary".loco(
            accepted,
            declined,
            event.guests.count - accepted - declined
        )
    }

    private func guestRow(_ guest: TimelineGuest) -> some View {
        HStack(spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                TimelineAvatar(
                    guest: guest,
                    fill: Color(neutralColors.avatarFill),
                    text: Color(neutralColors.avatarText),
                    size: metrics.detailsAvatarSize
                )
                guestBadge(guest.status)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(guestName(guest))
                    .foregroundColor(guest.status == .declined ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if isOrganizer(guest) {
                    Text("status_bar_details_organizer".loco())
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private func isOrganizer(_ guest: TimelineGuest) -> Bool {
        guard let email = mbEvent.organizer?.email, let guestEmail = guest.email else { return false }
        return email.caseInsensitiveCompare(guestEmail) == .orderedSame
    }

    /// Only shown when the organizer isn't already labeled in the guest list.
    private var unlistedOrganizer: MBEventOrganizer? {
        guard let organizer = mbEvent.organizer,
              !event.guests.contains(where: isOrganizer)
        else { return nil }
        return organizer
    }

    private func guestName(_ guest: TimelineGuest) -> String {
        guest.isCurrentUser ? "status_bar_submenu_attendees_you".loco(guest.name) : guest.name
    }

    @ViewBuilder
    private func guestBadge(_ status: MBEventAttendeeStatus) -> some View {
        switch status {
        case .accepted:
            badge("checkmark", color: .green)
        case .declined:
            badge("xmark", color: .red)
        case .tentative:
            badge("questionmark", color: .gray)
        default:
            EmptyView()
        }
    }

    private func badge(_ systemImage: String, color: Color) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 6, weight: .heavy))
            .foregroundColor(.white)
            .frame(width: 10, height: 10)
            .background(Circle().fill(color))
            .offset(x: 2, y: 2)
    }

    private var eventActions: some View {
        HStack(spacing: 8) {
            if event.isDismissed {
                Button {
                    actions.undismiss(mbEvent)
                } label: {
                    Label("status_bar_submenu_undismiss_meeting".loco(), systemImage: "bell")
                }
            } else {
                Button {
                    actions.dismiss(mbEvent)
                } label: {
                    Label("status_bar_submenu_dismiss_meeting".loco(), systemImage: "bell.slash")
                }
            }
            if isFantasticalInstalled {
                Button {
                    actions.openInFantastical(mbEvent)
                } label: {
                    Label("status_bar_submenu_open_in_fantastical".loco(), systemImage: "calendar")
                }
            }
            Spacer(minLength: 0)
        }
        .buttonStyle(TimelineButtonStyle())
    }

    /// Google events carry their web link, which opens in the default browser.
    private func openInCalendarTitle(_ url: URL) -> String {
        url.host?.contains("google.com") == true
            ? "status_bar_submenu_open_in_google_calendar".loco()
            : "status_bar_submenu_open_in_calendar".loco()
    }

    private func row<Content: View>(
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: Self.gutterSpacing) {
            Image(systemName: systemImage)
                .foregroundColor(.secondary)
                .frame(width: Self.gutter)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Notes and locations often contain the meeting URL; keep it clickable.
    private func linkedText(_ text: String) -> Text {
        var attributed = AttributedString(text)
        let range = NSRange(text.startIndex..., in: text)
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        detector?.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let match,
                  let url = match.url,
                  let stringRange = Range(match.range, in: text),
                  let lower = AttributedString.Index(stringRange.lowerBound, within: attributed),
                  let upper = AttributedString.Index(stringRange.upperBound, within: attributed)
            else { return }
            attributed[lower ..< upper].link = url
        }
        return Text(attributed)
    }

    private var visibleLocation: String? {
        guard let location = mbEvent.location?.trimmingCharacters(in: .whitespacesAndNewlines),
              !location.isEmpty
        else { return nil }
        let isBareLink = location.contains("://") && !location.contains(" ")
        return isBareLink ? nil : location
    }

    private var dateText: String {
        let formatter = DateFormatter()
        formatter.locale = I18N.instance.locale
        formatter.setLocalizedDateFormatFromTemplate("EEEEMMMMd")
        let date = formatter.string(from: mbEvent.startDate)
        return mbEvent.isAllDay
            ? "\(date) · \("status_bar_event_start_time_all_day".loco())"
            : date
    }

    private var timeText: String {
        let formatter = DateFormatter()
        formatter.locale = I18N.instance.locale
        formatter.dateFormat = timeFormat == .am_pm ? "h:mm a" : "HH:mm"
        let minutes = Int(mbEvent.endDate.timeIntervalSince(mbEvent.startDate) / 60)
        return "status_bar_submenu_duration_all_day".loco(
            formatter.string(from: mbEvent.startDate),
            formatter.string(from: mbEvent.endDate),
            String(minutes)
        )
    }

    private func alternateLinkTitle(_ candidate: MeetingLinkCandidate) -> String {
        let service = candidate.service?.localizedValue ?? "constants_meeting_service_other".loco()
        guard let host = candidate.url.host else { return service }
        return "\(service) - \(host)"
    }
}
