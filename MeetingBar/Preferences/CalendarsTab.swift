//
//  CalendarsTab.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 13.01.2021.
//  Copyright © 2021 Andrii Leitsius. All rights reserved.
//

import Defaults
import SwiftUI

struct CalendarsTab: View {
    @EnvironmentObject var appModel: AppModel

    var body: some View {
        let presentation = PreferencesCalendarPresentation.make(from: appModel.state)
        let missingIDs = unavailableSelectedCalendarIDs(
            selectedIDs: appModel.state.selectedCalendarIDs,
            calendars: appModel.state.calendars,
            provider: appModel.state.activeProvider,
            health: appModel.state.providerHealth
        )
        let isEmpty = appModel.state.calendars.isEmpty && accounts.isEmpty
        let notice = isEmpty ? nil : presentation.notice

        PreferencesGroupedForm {
            Section {
                ProviderPicker()
            } header: {
                Text("preferences_calendars_source_title".loco())
            }

            if isGoogle {
                AddGoogleAccountSection(
                    title: "preferences_calendars_show_title".loco(),
                    notice: notice
                )
                CalendarSectionsView(
                    calendars: appModel.state.calendars,
                    accounts: accounts,
                    isStale: appModel.state.providerHealth.isStale
                )
            } else if isEmpty {
                Section {
                    CalendarPreferencesEmptyState(presentation: presentation)
                } header: {
                    CalendarsSectionHeader()
                }
            } else {
                CalendarSectionsView(
                    calendars: appModel.state.calendars,
                    header: CalendarsSectionHeader(notice: notice)
                )
            }

            if !missingIDs.isEmpty {
                Section(header: Text("preferences_calendars_unavailable_title".loco())) {
                    Text("preferences_calendars_unavailable_help".loco())
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    ForEach(missingIDs, id: \.self) { id in
                        HStack {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                            Text(id)
                                .lineLimit(1)
                                .textSelection(.enabled)
                            Spacer()
                            Button("preferences_calendars_remove_missing".loco()) {
                                appModel.toggleCalendarSelection(id: id, selected: false)
                            }
                            .disabled(appModel.state.providerChangeInProgress)
                        }
                    }
                }
            }
        }
    }

    private var isGoogle: Bool { appModel.state.activeProvider == .googleCalendar }

    private var accounts: [ProviderAccountHealth] {
        isGoogle ? appModel.state.providerHealth.accounts : []
    }
}

/// "Your calendars", with Refresh beside it and any problem under it. The
/// Calendar app syncs every source at once, so neither can sit on one source.
struct CalendarsSectionHeader: View {
    @EnvironmentObject var appModel: AppModel
    var notice: CalendarNotice?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("preferences_calendars_show_title".loco())
                Spacer()
                Button("general_refresh".loco()) {
                    appModel.send(.refreshCalendars)
                }
                .controlSize(.small)
                .disabled(appModel.state.providerChangeInProgress)
            }
            if let notice {
                CalendarNoticeBanner(notice: notice) {
                    appModel.send(.reconnectProvider)
                }
                .font(.body.weight(.regular))
            }
        }
    }
}

/// An unavailable saved calendar must remain removable even when a failed
/// refresh has left Preferences with no visible calendar rows.
func unavailableSelectedCalendarIDs(
    selectedIDs: [String],
    calendars: [MBCalendar],
    provider: EventStoreProvider,
    health: ProviderHealth
) -> [String] {
    guard provider == .macOSEventKit,
          health.isStale,
          health.lastErrorDescription?.contains(
              EventKitCalendarSelectionError.selectedCalendarsUnavailable.localizedDescription
          ) == true else { return [] }
    let availableIDs = Set(calendars.map(\.id))
    return selectedIDs.filter { !availableIDs.contains($0) }
}

private struct CalendarPreferencesEmptyState: View {
    @EnvironmentObject var appModel: AppModel
    let presentation: PreferencesCalendarPresentation

    var body: some View {
        VStack(spacing: 10) {
            Text(presentation.emptyStateTextKey.loco())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let action = presentation.notice?.action {
                CalendarNoticeActionButton(action: action) {
                    appModel.send(.reconnectProvider)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 160)
    }
}

/// A source's or account's problem, with its fix on the right, tinted so it
/// doesn't read as one more setting.
private struct CalendarNoticeBanner: View {
    let notice: CalendarNotice
    let reconnect: () -> Void

    var body: some View {
        HStack {
            PreferencesStatusLabel(text: notice.textKey.loco(), tone: notice.tone)
            Spacer()
            if let action = notice.action {
                CalendarNoticeActionButton(action: action, reconnect: reconnect)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(statusColor(notice.tone).opacity(0.12))
        )
    }
}

private struct CalendarNoticeActionButton: View {
    @EnvironmentObject var appModel: AppModel
    let action: CalendarNotice.Action
    let reconnect: () -> Void

    var body: some View {
        switch action {
        case .reconnect:
            Button("preferences_status_reconnect".loco(), action: reconnect)
                .disabled(appModel.state.providerChangeInProgress)
        case .openCalendarSettings:
            Button("preferences_status_open_calendar_settings".loco()) {
                NSWorkspace.shared.open(Links.calendarPreferences)
            }
        }
    }
}

private func statusSystemImage(_ tone: PreferencesStatusTone) -> String? {
    switch tone {
    case .warning: "exclamationmark.triangle.fill"
    case .error: "xmark.circle.fill"
    case .busy: nil
    }
}

private func statusColor(_ tone: PreferencesStatusTone) -> Color {
    switch tone {
    case .busy: .secondary
    case .warning: .orange
    case .error: .red
    }
}

/// An icon and short status text, tinted by how things stand.
struct PreferencesStatusLabel: View {
    private static let capHeight = NSFont.preferredFont(forTextStyle: .callout).capHeight

    let text: String
    let tone: PreferencesStatusTone

    var body: some View {
        // Baseline alignment keeps the icon on the first line when the text wraps.
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if let name = statusSystemImage(tone) {
                Image(systemName: name)
            } else {
                ProgressView()
                    .controlSize(.mini)
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + Self.capHeight / 2 }
            }
            Text(text)
        }
        .foregroundStyle(statusColor(tone))
        .font(.callout)
    }
}

/// Calendars grouped by source. For Google, each connected account's section
/// starts with its actions and any problem it has.
struct CalendarSectionsView: View {
    @EnvironmentObject var appModel: AppModel
    let calendars: [MBCalendar]
    var accounts: [ProviderAccountHealth] = []
    var isStale = false
    /// Over the first card, when nothing above already names the list.
    var header: CalendarsSectionHeader?
    @State private var accountPendingRemoval: CalendarAccountRowPresentation?

    var body: some View {
        Group {
            // One card per account (or Calendar app source), headed by the
            // account with a switch for all its calendars, like an account's
            // services in System Settings › Internet Accounts.
            let sections = CalendarListPresentation.sections(
                for: calendars,
                accounts: accounts,
                isStale: isStale
            )
            ForEach(sections) { section in
                Section {
                    parentRow(section)
                    ForEach(section.calendars, id: \.id) { cal in
                        CalendarRow(calendar: cal)
                            .padding(.leading, Self.childIndent)
                    }
                } header: {
                    if section.id == sections.first?.id {
                        header
                    }
                }
            }
        }
        .alert(item: $accountPendingRemoval) { row in
            Alert(
                title: Text("preferences_calendars_google_account_remove_title".loco(accountName(row))),
                message: Text("preferences_calendars_google_account_remove_message".loco()),
                primaryButton: .destructive(Text("preferences_calendars_google_account_remove".loco())) {
                    appModel.send(.removeCalendarAccount(row.id))
                },
                secondaryButton: .cancel()
            )
        }
    }

    private static let iconSize: CGFloat = 20
    private static let childIndent: CGFloat = iconSize + 8

    /// An account's problem sits under its name in the same row, so it reads
    /// as the account's rather than as another calendar.
    private func parentRow(_ section: CalendarListSection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            parentRowControls(section)
            if let account = section.account, let notice = account.notice {
                CalendarNoticeBanner(notice: notice) {
                    appModel.send(.reconnectCalendarAccount(account.id))
                }
            }
        }
        .disabled(appModel.state.providerChangeInProgress)
    }

    private func parentRowControls(_ section: CalendarListSection) -> some View {
        HStack(spacing: 8) {
            Image(systemName: section.account == nil ? "calendar" : "person.crop.circle.fill")
                .font(.system(size: Self.iconSize))
                .foregroundStyle(.secondary)
                .frame(width: Self.iconSize)
            Text(title(of: section))
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            if let account = section.account {
                accountActions(account)
            }
            if !section.calendars.isEmpty {
                allCalendarsToggle(section)
            }
        }
    }

    @ViewBuilder
    private func accountActions(_ row: CalendarAccountRowPresentation) -> some View {
        // Every refresh checks all accounts side by side, so any account's
        // Refresh retries them all.
        if row.canRefresh {
            Button("general_refresh".loco()) {
                appModel.send(.refreshCalendars)
            }
        }
        Button("preferences_calendars_google_account_remove".loco()) {
            accountPendingRemoval = row
        }
    }

    private func allCalendarsToggle(_ section: CalendarListSection) -> some View {
        Toggle(
            "preferences_calendars_all".loco(),
            isOn: Binding(
                get: { section.allSelected(in: appModel.state.selectedCalendarIDs) },
                set: { selected in
                    let current = Set(appModel.state.selectedCalendarIDs)
                    for cal in section.calendars where current.contains(cal.id) != selected {
                        appModel.toggleCalendarSelection(id: cal.id, selected: selected)
                    }
                }
            )
        )
        .labelsHidden()
        .help("preferences_calendars_all".loco())
    }

    private func title(of section: CalendarListSection) -> String {
        section.account.map(accountName) ?? section.source
    }

    private func accountName(_ row: CalendarAccountRowPresentation) -> String {
        row.email ?? "google_calendar_account_fallback".loco()
    }
}

struct ProviderPicker: View {
    @EnvironmentObject var appModel: AppModel
    @State private var picker = EventStoreProvider.macOSEventKit

    var body: some View {
        Picker("preferences_calendars_source_label".loco(), selection: $picker) {
            ForEach(CalendarSourcePresentation.all) { source in
                Text(source.titleKey.loco()).tag(source.provider)
            }
        }
        .pickerStyle(.radioGroup)
        .onChange(of: picker) { provider in
            guard ProviderPickerSelectionPolicy.shouldRequestChange(
                selectedProvider: provider,
                activeProvider: appModel.state.activeProvider,
                providerChangeInProgress: appModel.state.providerChangeInProgress
            ) else { return }
            appModel.send(.changeProvider(provider, signOut: false))
        }
        .disabled(appModel.state.providerChangeInProgress)
        .onAppear {
            picker = appModel.state.activeProvider
        }
        .onChange(of: appModel.state.activeProvider) { provider in
            picker = provider
        }
        .onChange(of: appModel.state.providerChangeInProgress) { inProgress in
            picker = ProviderPickerSelectionPolicy.synchronizedSelection(
                currentSelection: picker,
                activeProvider: appModel.state.activeProvider,
                providerChangeInProgress: inProgress
            )
        }
    }
}

/// "Add Google account", with the latest add's failure under the button.
/// With no account yet, it is the section's empty state, asking for one.
struct AddGoogleAccountSection: View {
    @EnvironmentObject var appModel: AppModel
    var title: String?
    /// A problem with Google as a whole rather than one account.
    var notice: CalendarNotice?

    var body: some View {
        let hasNoAccount = PreferencesCalendarPresentation.make(from: appModel.state).hasNoGoogleAccount
        Section {
            if hasNoAccount {
                VStack(spacing: 10) {
                    Text("preferences_calendars_google_no_account".loco())
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    addButton.buttonStyle(.borderedProminent)
                    error
                }
                .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    addButton
                    error
                    if let notice {
                        CalendarNoticeBanner(notice: notice) {
                            appModel.send(.reconnectProvider)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } header: {
            if let title {
                Text(title)
            }
        }
    }

    private var addButton: some View {
        Button("preferences_calendars_google_add_account".loco()) {
            appModel.send(.addCalendarAccount)
        }
        .disabled(appModel.state.providerChangeInProgress)
    }

    @ViewBuilder
    private var error: some View {
        if let error = appModel.state.accountActionError {
            Text(error)
                .foregroundStyle(.red)
                .font(.caption)
                .textSelection(.enabled)
                .lineLimit(3)
        }
    }
}

struct AccessDeniedBanner: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("access_screen_access_screen_access_denied_go_to_title".loco())
            Button("access_screen_access_denied_system_preferences_button".loco()) {
                NSWorkspace.shared.open(Links.calendarPreferences)
            }
            Text("access_screen_access_denied_relaunch_title".loco())
        }
        .padding(.top, 8)
    }
}

struct CalendarRow: View {
    let calendar: MBCalendar
    @EnvironmentObject var appModel: AppModel

    var body: some View {
        Toggle(
            isOn: Binding(
                get: { appModel.state.selectedCalendarIDs.contains(calendar.id) },
                set: { appModel.toggleCalendarSelection(id: calendar.id, selected: $0) }
            )
        ) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(calendar.color))
                    .frame(width: 10, height: 10)
                Text(calendar.title)
                    .lineLimit(1)
            }
        }
    }
}

#Preview {
    List {
        CalendarSectionsView(calendars: [
            MBCalendar(
                title: "Calendar #1", id: "1", source: "Source #1", email: nil, color: .brown)
        ])

        CalendarSectionsView(calendars: [
            MBCalendar(title: "Calendar #2", id: "2", source: "Source #2", email: nil, color: .blue)
        ])
    }.listStyle(.sidebar)
        .frame(width: 300, height: 200)
}
