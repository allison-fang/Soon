//
//  NotificationsTab.swift
//  MeetingBar
//

import SwiftUI

struct NotificationsTab: View {
    var body: some View {
        PreferencesGroupedForm {
            Section(header: Text("notifications_event_start_title".loco())) {
                EventStartAlertPicker()
            }

            Section(header: Text("notifications_event_end_title".loco())) {
                EndEventNotificationPicker()
            }

            Section(header: Text("preferences_notifications_automation_title".loco())) {
                AutomaticEventJoinPicker()
            }
        }
    }
}
