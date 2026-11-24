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
    @Default(.timeFormat) var timeFormat

    var body: some View {
        PreferencesGroupedForm {
            Section {
                AboutSection()
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
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Soon")
                        .font(.title2).bold()
                    Text("preferences_general_version".loco(
                        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
                    ))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
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
