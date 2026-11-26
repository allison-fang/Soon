//
//  Shared.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 13.01.2021.
//  Copyright © 2021 Andrii Leitsius. All rights reserved.
//

import Defaults
import Foundation
import LaunchAtLogin
import SwiftUI
import UserNotifications

/// An indented "Timing" picker that belongs to the toggle row above it.
private struct TimeBeforeEventPickerRow: View {
    @Binding var selection: TimeBeforeEvent

    var body: some View {
        Picker(preferenceLabel("notifications_timing_title"), selection: $selection) {
            Text("general_when_event_starts".loco()).tag(TimeBeforeEvent.atStart)
            Text("general_one_minute_before".loco()).tag(TimeBeforeEvent.minuteBefore)
            Text("general_three_minute_before".loco()).tag(TimeBeforeEvent.threeMinuteBefore)
            Text("general_five_minute_before".loco()).tag(TimeBeforeEvent.fiveMinuteBefore)
        }
        .padding(.leading, 16)
    }
}

/**
 * users can decide to automatically open events in the configured application
 */
struct AutomaticEventJoinPicker: View {
    @Default(.automaticEventJoin) var automaticEventJoin
    @Default(.automaticEventJoinTime) var automaticEventJoinTime

    var body: some View {
        Toggle("shared_automatic_event_join_toggle".loco(), isOn: $automaticEventJoin)

        TimeBeforeEventPickerRow(selection: $automaticEventJoinTime)
            .disabled(!automaticEventJoin)

        if automaticEventJoin {
            Text("shared_automatic_event_join_tip".loco())
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 16)
        }
    }
}

struct EventStartAlertPicker: View {
    @Default(.joinEventNotification) var systemNotification
    @Default(.fullscreenNotification) var fullscreenNotification
    @Default(.joinEventNotificationTime) var time
    @Default(.eventStartAlertStyle) var storedStyle
    @Default(.fullscreenNotificationsForEventsWithoutMeetingLink)
    var fullscreenNotificationsForEventsWithoutMeetingLink

    private var style: EventStartAlertStyle { storedStyle ?? .system }
    private var isEnabled: Bool { systemNotification || fullscreenNotification }

    var notificationSettings: (noAlertStyle: Bool, disabled: Bool) {
        checkNotificationSettings()
    }

    var body: some View {
        Toggle(
            "notifications_event_start_toggle".loco(),
            isOn: Binding(
                get: { isEnabled },
                set: { EventStartAlertPreferences.apply(enabled: $0, style: style, time: time) }
            )
        )

        Picker(
            preferenceLabel("notifications_alert_style_title"),
            selection: Binding(
                get: { style },
                set: { EventStartAlertPreferences.apply(enabled: isEnabled, style: $0, time: time) }
            )
        ) {
            Text("notifications_alert_style_system".loco()).tag(EventStartAlertStyle.system)
            Text("notifications_alert_style_fullscreen".loco()).tag(EventStartAlertStyle.fullscreen)
            Text("notifications_alert_style_both".loco()).tag(EventStartAlertStyle.both)
        }
        .padding(.leading, 16)
        .disabled(!isEnabled)

        TimeBeforeEventPickerRow(
            selection: Binding(
                get: { time },
                set: { EventStartAlertPreferences.apply(enabled: isEnabled, style: style, time: $0) }
            )
        )
        .disabled(!isEnabled)

        if style != .system {
            Toggle(
                "shared_fullscreen_notification_without_link_toggle".loco(),
                isOn: $fullscreenNotificationsForEventsWithoutMeetingLink
            )
            .disabled(!isEnabled)
            .padding(.leading, 16)

            Text("shared_fullscreen_notification_without_link_help".loco())
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 16)
        }

        if systemNotification {
            if notificationSettings.noAlertStyle, !notificationSettings.disabled {
                Text("shared_send_notification_no_alert_style_tip".loco())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 16)
            }

            if notificationSettings.disabled {
                Text("shared_send_notification_disabled_tip".loco())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 16)
            }
        }
    }
}

struct EndEventNotificationPicker: View {
    @Default(.endOfEventNotification) var endOfEventNotification
    @Default(.endOfEventNotificationTime) var endOfEventNotificationTime

    var body: some View {
        Toggle("general_end_of_event_notification_toggle".loco(), isOn: $endOfEventNotification)

        Picker(preferenceLabel("notifications_timing_title"), selection: $endOfEventNotificationTime) {
            Text("general_when_event_ends".loco()).tag(TimeBeforeEventEnd.atEnd)
            Text("general_one_minute_before".loco()).tag(TimeBeforeEventEnd.minuteBefore)
            Text("general_three_minute_before".loco()).tag(TimeBeforeEventEnd.threeMinuteBefore)
            Text("general_five_minute_before".loco()).tag(TimeBeforeEventEnd.fiveMinuteBefore)
        }
        .padding(.leading, 16)
        .disabled(!endOfEventNotification)
    }
}

func checkNotificationSettings() -> (Bool, Bool) {
    let center = UNUserNotificationCenter.current()
    let group = DispatchGroup()
    let result = NotificationSettingsResult()
    group.enter()

    center.getNotificationSettings { notificationSettings in
        result.update(
            noAlertStyle: notificationSettings.alertStyle != .alert,
            notificationsDisabled: notificationSettings.authorizationStatus == .denied
        )
        group.leave()
    }

    group.wait()
    return result.value
}

/// `UNUserNotificationCenter.getNotificationSettings` invokes a Sendable
/// callback. This tiny holder keeps the synchronous Preferences helper
/// warning-free while the callback writes its result.
private final class NotificationSettingsResult: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue = (noAlertStyle: false, notificationsDisabled: false)

    var value: (Bool, Bool) {
        lock.withLock { storedValue }
    }

    func update(noAlertStyle: Bool, notificationsDisabled: Bool) {
        lock.withLock {
            storedValue = (noAlertStyle, notificationsDisabled)
        }
    }
}

struct LaunchAtLoginANDPreferredLanguagePicker: View {
    @Default(.preferredLanguage) var preferredLanguage

    var body: some View {
        LaunchAtLogin.Toggle {
            Text("preferences_general_option_login_launch".loco())
        }

        Picker(
            preferenceLabel("preferences_general_option_preferred_language_title"),
            selection: $preferredLanguage
        ) {
            Text("preferences_general_option_preferred_language_system_value".loco()).tag(AppLanguage.system)
            Section {
                Group {
                    Text("English").tag(AppLanguage.english)
                    Text("Українська").tag(AppLanguage.ukrainian)
                    Text("Deutsch").tag(AppLanguage.german)
                    Text("Français").tag(AppLanguage.french)
                    Text("Hrvatski").tag(AppLanguage.croatian)
                    Text("Norsk").tag(AppLanguage.norwegian)
                    Text("Čeština").tag(AppLanguage.czech)
                    Text("日本語").tag(AppLanguage.japanese)
                    Text("Polski").tag(AppLanguage.polish)
                    Text("עברית‎").tag(AppLanguage.hebrew)
                }
                Group {
                    Text("Türkçe").tag(AppLanguage.turkish)
                    Text("Italiano").tag(AppLanguage.italian)
                    Text("Español").tag(AppLanguage.spanish)
                    Text("Português").tag(AppLanguage.portuguese)
                    Text("Slovenčina").tag(AppLanguage.slovak)
                    Text("Nederlands").tag(AppLanguage.dutch)
                }
            }
        }
    }
}

#Preview {
    VStack(alignment: .leading) {
        AutomaticEventJoinPicker()
        Divider()
        EventStartAlertPicker()
        Divider()
        EndEventNotificationPicker()
        Divider()
        LaunchAtLoginANDPreferredLanguagePicker()
    }.padding()
}
