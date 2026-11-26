//
//  LinksTab.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 13.01.2021.
//  Copyright © 2021 Andrii Leitsius. All rights reserved.
//

import Defaults
import SwiftUI

struct LinksTab: View {
    @Default(.browserForCreateMeeting) var browserForCreateMeeting
    @Default(.defaultBrowser) var defaultBrowser
    @Default(.createMeetingServiceUrl) var createMeetingServiceUrl
    @Default(.createMeetingService) var createMeetingService
    @Default(.browsers) var allBrowser

    @State var showBrowserConfiguration = false

    private var defaultBrowserOptions: [Browser] {
        BrowserPickerOptions.make(
            configured: allBrowser,
            selected: defaultBrowser
        )
    }

    private var createMeetingBrowserOptions: [Browser] {
        BrowserPickerOptions.make(
            configured: allBrowser,
            selected: browserForCreateMeeting
        )
    }

    var body: some View {
        PreferencesGroupedForm {
            Section(header: Text("preferences_meeting_opening_behavior_title".loco())) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("preferences_services_link_meeting_title".loco())
                        Text("preferences_services_link_default_help".loco())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker(
                        "preferences_services_link_meeting_title".loco(),
                        selection: BrowserPickerOptions.selection($defaultBrowser)
                    ) {
                        ForEach(defaultBrowserOptions, id: \.self) { (browser: Browser) in
                            Text(browser.name).tag(browser)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }

            Section(header: Text("preferences_services_link_overrides_title".loco())) {
                ForEach(
                    MeetingProvider.all.filter { !$0.openingModes.isEmpty }, id: \.id
                ) { provider in
                    MeetingProviderOpeningPicker(provider: provider)
                }

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Button(
                        "preferences_configure_browsers_button".loco(),
                        action: clickConfigureBrowser
                    )
                    .sheet(isPresented: $showBrowserConfiguration) {
                        BrowserConfigView()
                    }
                    Text("preferences_configure_browsers_help".loco())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section(header: Text("preferences_section_create_title".loco())) {
                HStack {
                    Text("preferences_services_create_meeting_title".loco())
                    Spacer()
                    CreateMeetingServicePicker()
                        .fixedSize()
                }

                if createMeetingService == CreateMeetingServices.url {
                    HStack {
                        Text("preferences_services_create_meeting_custom_url_value".loco())
                        TextField(
                            "preferences_services_create_meeting_custom_url_placeholder".loco(),
                            text: $createMeetingServiceUrl
                        ).textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                    Text("preferences_services_google_meet_tip".loco())
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }

                Picker(
                    "preferences_services_create_meeting_browser_title".loco(),
                    selection: BrowserPickerOptions.selection($browserForCreateMeeting)
                ) {
                    ForEach(createMeetingBrowserOptions, id: \.self) { (browser: Browser) in
                        Text(browser.name).tag(browser)
                    }
                }
            }
        }
    }

    func clickConfigureBrowser() {
        showBrowserConfiguration.toggle()
    }
}

struct MeetingProviderOpeningPicker: View {
    let provider: MeetingProvider
    /// Fixed label width for legacy column layouts (onboarding). When nil,
    /// the picker renders as a regular form row with a natural label.
    var labelWidth: CGFloat?

    @Default(.providerBrowsers) private var providerBrowsers
    @Default(.providerOpeningModes) private var providerOpeningModes
    @Default(.browsers) private var allBrowsers

    private var selectedValue: MeetingProviderOpeningSelection {
        MeetingProviderOpeningSelectionPolicy.selected(
            provider: provider,
            providerBrowsers: providerBrowsers,
            providerOpeningModes: providerOpeningModes
        )
    }

    private var selection: Binding<MeetingProviderOpeningSelection> {
        Binding(
            get: { selectedValue },
            set: { newSelection in
                let updated = MeetingProviderOpeningSelectionPolicy.updating(
                    provider: provider,
                    selection: newSelection,
                    providerBrowsers: providerBrowsers,
                    providerOpeningModes: providerOpeningModes
                )
                providerBrowsers = updated.providerBrowsers
                providerOpeningModes = updated.providerOpeningModes
            }
        )
    }

    private var browserOptions: [Browser] {
        let selectedBrowser: Browser
        switch selectedValue {
        case .browser(let browser):
            selectedBrowser = browser
        case .mode:
            selectedBrowser = systemDefaultBrowser
        }
        return BrowserPickerOptions.make(
            configured: allBrowsers,
            selected: selectedBrowser
        )
    }

    var body: some View {
        Picker(selection: selection, label: pickerLabel) {
            ForEach(provider.openingModes, id: \.self) { mode in
                Text(mode.titleKey.loco()).tag(
                    MeetingProviderOpeningSelection.mode(mode)
                )
            }
            ForEach(browserOptions, id: \.self) { browser in
                Text(browser.name).tag(MeetingProviderOpeningSelection.browser(browser))
            }
        }

        if case let .mode(mode) = selectedValue,
           let helpKey = mode.helpKey {
            Text(helpKey.loco())
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, labelWidth.map { $0 + 8 } ?? 16)
        }
    }

    @ViewBuilder
    private var pickerLabel: some View {
        let label = Text("preferences_services_link_service_title".loco(provider.displayName))
        if let labelWidth {
            label.frame(width: labelWidth, alignment: .leading)
        } else {
            label
        }
    }
}

struct CreateMeetingServicePicker: View {
    @Default(.createMeetingService) var createMeetingService

    var body: some View {
        Picker(selection: $createMeetingService, label: EmptyView()) {
            Text(CreateMeetingServices.meet.localizedValue).tag(CreateMeetingServices.meet)
            Text(CreateMeetingServices.zoom.localizedValue).tag(CreateMeetingServices.zoom)
            Text(CreateMeetingServices.teams.localizedValue).tag(CreateMeetingServices.teams)
            Text(CreateMeetingServices.jam.localizedValue).tag(CreateMeetingServices.jam)
            Text(CreateMeetingServices.coscreen.localizedValue).tag(CreateMeetingServices.coscreen)
            Text(CreateMeetingServices.gcalendar.localizedValue).tag(
                CreateMeetingServices.gcalendar)
            Text(CreateMeetingServices.outlook_live.localizedValue).tag(
                CreateMeetingServices.outlook_live)
            Text(CreateMeetingServices.outlook_office365.localizedValue).tag(
                CreateMeetingServices.outlook_office365)
            Text(CreateMeetingServices.url.localizedValue).tag(CreateMeetingServices.url)
        }.labelsHidden()
    }
}

#Preview {
    LinksTab().padding().frame(width: 700, height: 620)
}
