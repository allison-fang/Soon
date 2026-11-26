//
//  GeneralTab.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 13.01.2021.
//  Copyright © 2021 Andrii Leitsius. All rights reserved.
//

import SwiftUI

import Defaults
import KeyboardShortcuts

struct GeneralTab: View {
    @EnvironmentObject var updateChecker: UpdateChecker
    @Default(.timeFormat) var timeFormat

    var body: some View {
        PreferencesGroupedForm {
            Section {
                AboutSection()
            }

            Section(header: Text("preferences_section_updates_title".loco())) {
                VersionSection()
            }

            if let update = updateChecker.availableUpdate {
                Section {
                    AvailableUpdateRow(update: update)
                        // Grouped forms ignore listRowBackground, so the card is drawn behind the row at the section's inset and corner radius.
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.accentColor.opacity(0.14))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(Color.accentColor, lineWidth: 1)
                                )
                                .padding(.horizontal, -10)
                                .padding(.vertical, -9.5)
                        )
                }
            }

            Section(header: Text("preferences_section_general_settings_title".loco())) {
                LaunchAtLoginANDPreferredLanguagePicker()

                // 12/24-hour format affects every surface that renders clock
                // times (dropdown rows, timeline, event details, fullscreen
                // notification), so it lives with the app-wide options rather
                // than under Menu.
                Picker(
                    preferenceLabel("preferences_appearance_menu_time_format_title"),
                    selection: $timeFormat
                ) {
                    Text("preferences_appearance_menu_time_format_12_hour_value".loco())
                        .tag(TimeFormat.am_pm)
                    Text("preferences_appearance_menu_time_format_24_hour_value".loco())
                        .tag(TimeFormat.military)
                }
            }

            Section(header: Text("preferences_section_shortcuts_title".loco())) {
                ShortcutsSection()
            }
        }
    }
}

struct PreferencesWindowOpenedAtKey: EnvironmentKey {
    static let defaultValue = Date.distantFuture
}

extension EnvironmentValues {
    var preferencesWindowOpenedAt: Date {
        get { self[PreferencesWindowOpenedAtKey.self] }
        set { self[PreferencesWindowOpenedAtKey.self] = newValue }
    }
}

struct VersionSection: View {
    @EnvironmentObject var updateChecker: UpdateChecker
    @Environment(\.preferencesWindowOpenedAt) var windowOpenedAt
    @Default(.checkForUpdates) var checkForUpdates

    var body: some View {
        HStack(spacing: 8) {
            Text("preferences_general_version".loco(updateChecker.currentVersion))
            if let badge {
                UpdateStatusBadgeView(badge: badge)
            }
            Spacer()
            Button("preferences_general_check_for_updates_button".loco()) {
                updateChecker.checkNow()
            }
            .disabled(updateChecker.status == .checking)
        }
        Toggle("preferences_general_check_for_updates".loco(), isOn: $checkForUpdates)
    }

    private var badge: UpdateStatusBadge? {
        UpdateCheckPolicy.statusBadge(
            isChecking: updateChecker.status == .checking,
            lastResult: updateChecker.lastResult,
            shownSince: windowOpenedAt
        )
    }
}

private struct UpdateStatusBadgeView: View {
    let badge: UpdateStatusBadge

    var body: some View {
        switch badge {
        case .checking:
            StatusBadge(title: "preferences_general_update_checking".loco(), tint: .secondary, icon: .spinner)
        case .upToDate:
            StatusBadge(title: "preferences_general_update_up_to_date".loco(), tint: .green, icon: .symbol("checkmark"))
        case .available:
            StatusBadge(title: "preferences_general_update_badge_available".loco(), tint: .accentColor, icon: .dot)
        case .failed:
            StatusBadge(
                title: "preferences_general_update_badge_failed".loco(),
                tint: .orange,
                icon: .symbol("exclamationmark.triangle.fill")
            )
            .help("preferences_general_update_failed".loco())
        }
    }
}

struct AvailableUpdateRow: View {
    let update: AvailableUpdate

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("preferences_general_update_available".loco(update.version))
                    .font(.body.weight(.medium))
                Text("preferences_general_update_instructions".loco())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            // Same equal-width stack as the About card's buttons.
            VStack(spacing: 6) {
                Button {
                    NSWorkspace.shared.open(update.releaseURL)
                } label: {
                    Text("preferences_general_update_whats_new".loco()).frame(maxWidth: .infinity)
                }
                Button {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(UpdateChecker.installCommand, forType: .string)
                } label: {
                    Text("preferences_general_update_copy_command".loco()).frame(maxWidth: .infinity)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.vertical, 4)
    }
}

struct ShortcutsSection: View {
    var body: some View {
        ShortcutRow(
            title: "preferences_general_shortcut_open_menu".loco(),
            recorder: KeyboardShortcuts.Recorder(for: .openMenuShortcut)
        )
        ShortcutRow(
            title: "preferences_general_shortcut_join_next".loco(),
            recorder: KeyboardShortcuts.Recorder(for: .joinEventShortcut)
        )
        ShortcutRow(
            title: "preferences_general_shortcut_create_meeting".loco(),
            recorder: KeyboardShortcuts.Recorder(for: .createMeetingShortcut)
        )
        ShortcutRow(
            title: "preferences_general_shortcut_join_from_clipboard".loco(),
            recorder: KeyboardShortcuts.Recorder(for: .openClipboardShortcut)
        )
        ShortcutRow(
            title: "preferences_general_shortcut_toggle_meeting_name_visibility".loco(),
            recorder: KeyboardShortcuts.Recorder(for: .toggleMeetingTitleVisibilityShortcut)
        )
    }
}

private struct ShortcutRow<Recorder: View>: View {
    let title: String
    let recorder: Recorder

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            recorder
        }
    }
}

struct AboutSection: View {
    @EnvironmentObject var appModel: AppModel

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Image("appLogo")
                .resizable()
                .frame(width: 72, height: 72)
            VStack(alignment: .leading, spacing: 4) {
                Text("Soon")
                    .font(.title2).bold()
                Text("preferences_general_meeting_bar_description".loco())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 16)
            // Fixed width so both buttons stretch to the wider one.
            VStack(spacing: 6) {
                Button {
                    Links.github.openInDefaultBrowser()
                } label: {
                    Text("GitHub").frame(maxWidth: .infinity)
                }
                Button {
                    DiagnosticsClipboard.copy(
                        snapshot: DiagnosticsSnapshot(appState: appModel.state)
                    )
                } label: {
                    Text("preferences_status_copy_diagnostics".loco()).frame(maxWidth: .infinity)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .controlSize(.small)
        }
        .padding(.vertical, 4)
    }
}

#Preview() {
    GeneralTab()
        .padding()
        .frame(width: 700, height: 620)
}
