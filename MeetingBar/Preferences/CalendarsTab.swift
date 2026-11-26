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

        PreferencesGroupedForm {
            Section(header: Text("preferences_calendar_configuration_title".loco())) {
                ProviderPicker()

                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            PreferencesStatusLabel(text: statusText(presentation), tone: presentation.statusTone)
                            if let lastSuccess = appModel.state.providerHealth.lastSuccessfulRefresh {
                                Text("·")
                                    .foregroundStyle(.tertiary)
                                    .font(.callout)
                                Text("status_bar_popover_updated".loco(
                                    lastSuccess.formatted(date: .omitted, time: .shortened)
                                ))
                                .foregroundStyle(.secondary)
                                .font(.callout)
                            }
                        }
                        if presentation.showsErrorDetail,
                           let error = appModel.state.providerHealth.lastErrorDescription {
                            Text(error)
                                .foregroundStyle(.secondary)
                                .font(.caption)
                                .textSelection(.enabled)
                                .lineLimit(3)
                        }
                    }
                    Spacer()
                    if presentation.canReconnect {
                        Button("preferences_status_reconnect".loco()) {
                            appModel.send(.reconnectProvider)
                        }
                        .disabled(appModel.state.providerChangeInProgress)
                    }
                    if presentation.canOpenCalendarSettings {
                        Button("preferences_status_open_calendar_settings".loco()) {
                            NSWorkspace.shared.open(Links.calendarPreferences)
                        }
                    }
                    // Google accounts each have their own Refresh.
                    if appModel.state.activeProvider != .googleCalendar {
                        Button("general_refresh".loco()) {
                            appModel.send(.refreshCalendars)
                        }
                        .disabled(appModel.state.providerChangeInProgress)
                    }
                }
            }

            if appModel.state.activeProvider == .googleCalendar {
                AddGoogleAccountSection()
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

            if appModel.state.calendars.isEmpty, accounts.isEmpty {
                Section(header: Text("preferences_calendars_select_calendars_title".loco())) {
                    CalendarPreferencesEmptyState(presentation: presentation)
                }
            } else {
                CalendarSectionsView(calendars: appModel.state.calendars, accounts: accounts)
            }
        }
    }

    private var accounts: [ProviderAccountHealth] {
        appModel.state.activeProvider == .googleCalendar ? appModel.state.providerHealth.accounts : []
    }

    private func statusText(_ presentation: PreferencesCalendarPresentation) -> String {
        let arguments = presentation.statusTextArguments
        switch arguments.count {
        case 1:
            return presentation.statusTextKey.loco(arguments[0])
        case 2:
            return presentation.statusTextKey.loco(arguments[0], arguments[1])
        default:
            return presentation.statusTextKey.loco()
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
            Text(emptyStateText)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
    }

    private var emptyStateText: String {
        presentation.emptyStateTextKey.loco()
    }
}

private func statusSystemImage(_ tone: PreferencesStatusTone) -> String {
    switch tone {
    case .neutral: "circle"
    case .info: "person.crop.circle"
    case .success: "checkmark.circle.fill"
    case .warning: "exclamationmark.triangle.fill"
    case .error: "xmark.circle.fill"
    }
}

private func statusColor(_ tone: PreferencesStatusTone) -> Color {
    switch tone {
    case .neutral, .info: .secondary
    case .success: .green
    case .warning: .orange
    case .error: .red
    }
}

/// An icon and short status text, tinted by how things stand.
struct PreferencesStatusLabel: View {
    let text: String
    let tone: PreferencesStatusTone

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: statusSystemImage(tone))
            Text(text)
        }
        .foregroundStyle(statusColor(tone))
        .font(.callout)
    }
}

/// Calendars grouped by source. For Google, each connected account's section
/// starts with its status and actions.
struct CalendarSectionsView: View {
    @EnvironmentObject var appModel: AppModel
    let calendars: [MBCalendar]
    var accounts: [ProviderAccountHealth] = []
    @State private var accountPendingRemoval: CalendarAccountRowPresentation?

    var body: some View {
        Group {
            ForEach(CalendarListPresentation.sections(for: calendars, accounts: accounts)) { section in
                if let account = section.account {
                    // The account's connection gets its own card so its status
                    // does not read as one of the calendar rows below it.
                    Section(header: Text(title(of: section))) {
                        accountRow(account)
                    }
                    if !section.calendars.isEmpty {
                        Section {
                            calendarRows(section)
                        }
                    }
                } else {
                    Section(header: Text(title(of: section))) {
                        calendarRows(section)
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

    private func calendarRows(_ section: CalendarListSection) -> some View {
        ForEach(section.calendars, id: \.id) { cal in
            CalendarRow(calendar: cal)
        }
    }

    private func accountRow(_ row: CalendarAccountRowPresentation) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                PreferencesStatusLabel(text: row.statusTextKey.loco(), tone: row.statusTone)
                if let detail = row.errorDetail {
                    Text(detail)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                        .textSelection(.enabled)
                        .lineLimit(3)
                }
            }
            Spacer()
            // Every refresh checks all accounts side by side, so any account's
            // Refresh retries them all.
            if row.canRefresh {
                Button("general_refresh".loco()) {
                    appModel.send(.refreshCalendars)
                }
            }
            if row.canReconnect {
                Button("preferences_status_reconnect".loco()) {
                    appModel.send(.reconnectCalendarAccount(row.id))
                }
            }
            Button("preferences_calendars_google_account_remove".loco()) {
                accountPendingRemoval = row
            }
        }
        .disabled(appModel.state.providerChangeInProgress)
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
        Picker("access_screen_provider_picker_label".loco(), selection: $picker) {
            ForEach(CalendarSourcePresentation.all) { source in
                Text(source.titleKey.loco()).tag(source.provider)
            }
        }
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
/// Shared by Preferences and setup.
struct AddGoogleAccountSection: View {
    @EnvironmentObject var appModel: AppModel
    /// Off where it follows the titled configuration section as a sub-group.
    var showsTitle = false

    var body: some View {
        Section {
            row
        } header: {
            if showsTitle {
                Text("preferences_calendar_configuration_title".loco())
            }
        }
    }

    private var row: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button("preferences_calendars_google_add_account".loco()) {
                appModel.send(.addCalendarAccount)
            }
            .disabled(appModel.state.providerChangeInProgress)

            if let error = appModel.state.accountActionError {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .textSelection(.enabled)
                    .lineLimit(3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
