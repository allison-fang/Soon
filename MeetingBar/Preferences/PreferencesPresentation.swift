//
//  PreferencesPresentation.swift
//  MeetingBar
//

import Foundation
import SwiftUI

struct CalendarSourcePresentation: Equatable, Identifiable {
    let provider: EventStoreProvider
    let titleKey: String

    var id: EventStoreProvider { provider }

    static let all: [CalendarSourcePresentation] = [
        make(for: .googleCalendar),
        make(for: .macOSEventKit)
    ]

    static func make(for provider: EventStoreProvider) -> CalendarSourcePresentation {
        switch provider {
        case .macOSEventKit:
            CalendarSourcePresentation(
                provider: provider,
                titleKey: "onboarding_apple_calendar_title"
            )
        case .googleCalendar:
            CalendarSourcePresentation(
                provider: provider,
                titleKey: "onboarding_google_calendar_title"
            )
        }
    }
}

enum PreferencesTab: CaseIterable, Hashable {
    case general
    case calendars
    case meetingOpening
    case menuBar
    case notifications
    case advanced

    static let defaultSelection: PreferencesTab = .general

    // This metadata is the single source of truth for sidebar labels, icons,
    // identity, and ordering.
    var titleKey: String {
        switch self {
        case .general:
            "preferences_tab_general"
        case .calendars:
            "preferences_tab_calendars"
        case .meetingOpening:
            "preferences_tab_meeting_opening"
        case .menuBar:
            "preferences_tab_menu_bar"
        case .notifications:
            "preferences_tab_notifications"
        case .advanced:
            "preferences_tab_advanced"
        }
    }

    var systemImage: String {
        switch self {
        case .general:
            "gearshape"
        case .calendars:
            "calendar"
        case .meetingOpening:
            "arrow.up.right.square"
        case .menuBar:
            "menubar.rectangle"
        case .notifications:
            "bell"
        case .advanced:
            "slider.horizontal.3"
        }
    }

}

enum PreferencesStatusBarTimeOption: CaseIterable, Equatable {
    case show
    case showUnderTitle
    case hide

    var format: EventTimeFormat {
        switch self {
        case .show:
            .show
        case .showUnderTitle:
            .show_under_title
        case .hide:
            .hide
        }
    }

    var titleKey: String {
        switch self {
        case .show:
            "preferences_appearance_status_bar_time_show_value"
        case .showUnderTitle:
            "preferences_appearance_status_bar_time_show_under_title_value"
        case .hide:
            "preferences_appearance_status_bar_time_hide_value"
        }
    }
}

enum PreferencesStatusTone: Equatable {
    case warning
    case error
    /// Work under way; shows a spinner instead of an icon.
    case busy
}

enum PreferencesProviderConnectionState: Equatable {
    case initializing
    case connected
    case authRequired
    case permissionRequired
    case stale
    /// Some connected accounts are fine while others failed and show their
    /// last known calendars.
    case accountsNeedAttention
    case error
}

/// Something wrong with a calendar source or one of its accounts, with the
/// fix when there is one.
struct CalendarNotice: Equatable {
    enum Action: Equatable {
        case reconnect
        case openCalendarSettings
    }

    let textKey: String
    let tone: PreferencesStatusTone
    var action: Action?
}

struct PreferencesCalendarPresentation: Equatable {
    let activeProvider: EventStoreProvider
    let connectionState: PreferencesProviderConnectionState
    let selectedCalendarCount: Int
    let availableCalendarCount: Int
    /// Google is the source but no account was ever added.
    let hasNoGoogleAccount: Bool
    let providerTitleKey: String
    /// Nil while everything works: the calendars listed are the sign of that.
    let notice: CalendarNotice?
    let emptyStateTextKey: String
    /// What setup needs next while Done is unavailable.
    let nextStepHintKey: String

    static func make(from state: AppState) -> PreferencesCalendarPresentation {
        let connectionState: PreferencesProviderConnectionState

        let availableIDs = Set(state.calendars.map(\.id))
        let selectedIDs = Set(state.selectedCalendarIDs.filter { availableIDs.contains($0) })
        let accounts = state.activeProvider == .googleCalendar ? state.providerHealth.accounts : []
        let connectedAccountCount = accounts.filter { $0.status == .connected }.count
        let hasNoGoogleAccount = state.activeProvider == .googleCalendar
            && accounts.isEmpty
            && state.calendars.isEmpty

        if state.activeProvider == .macOSEventKit,
           state.providerHealth.calendarPermissionRequired {
            connectionState = .permissionRequired
        } else if state.providerHealth.authRequired {
            connectionState = .authRequired
        } else if !accounts.isEmpty {
            connectionState = connectedAccountCount == accounts.count ? .connected : .accountsNeedAttention
        } else if state.providerHealth.isStale {
            connectionState = .stale
        } else if state.providerHealth.lastErrorDescription != nil {
            connectionState = .error
        } else if state.providerHealth.lastSuccessfulRefresh != nil {
            connectionState = .connected
        } else {
            connectionState = .initializing
        }

        // Each account shows its own problem, so only problems no account
        // explains get a notice.
        let notice: CalendarNotice? = switch connectionState {
        case .permissionRequired:
            CalendarNotice(
                textKey: "onboarding_calendar_selection_permission",
                tone: .error,
                action: .openCalendarSettings
            )
        case .authRequired where !hasNoGoogleAccount && accounts.isEmpty:
            CalendarNotice(
                textKey: "onboarding_calendar_selection_reconnect",
                tone: .error,
                action: .reconnect
            )
        case .connected where state.providerHealth.isStale, .stale:
            accounts.isEmpty
                ? CalendarNotice(textKey: "preferences_calendars_refresh_failed", tone: .warning)
                : nil
        case .error:
            CalendarNotice(textKey: "preferences_status_state_error", tone: .error)
        case .initializing, .connected, .authRequired, .accountsNeedAttention:
            nil
        }

        let emptyStateTextKey = if hasNoGoogleAccount {
            "preferences_calendars_google_no_account"
        } else {
            notice?.textKey ?? "onboarding_calendar_selection_empty"
        }

        let nextStepHintKey = if hasNoGoogleAccount {
            "onboarding_hint_add_google_account"
        } else if connectionState == .permissionRequired {
            "onboarding_hint_allow_calendar_access"
        } else {
            "calendars_screen_select_calendar_title"
        }

        return PreferencesCalendarPresentation(
            activeProvider: state.activeProvider,
            connectionState: connectionState,
            selectedCalendarCount: selectedIDs.count,
            availableCalendarCount: state.calendars.count,
            hasNoGoogleAccount: hasNoGoogleAccount,
            providerTitleKey: CalendarSourcePresentation.make(for: state.activeProvider).titleKey,
            notice: notice,
            emptyStateTextKey: emptyStateTextKey,
            nextStepHintKey: nextStepHintKey
        )
    }
}

enum ProviderPickerSelectionPolicy {
    static func synchronizedSelection(
        currentSelection: EventStoreProvider,
        activeProvider: EventStoreProvider,
        providerChangeInProgress: Bool
    ) -> EventStoreProvider {
        providerChangeInProgress ? currentSelection : activeProvider
    }

    static func shouldRequestChange(
        selectedProvider: EventStoreProvider,
        activeProvider: EventStoreProvider,
        providerChangeInProgress: Bool
    ) -> Bool {
        selectedProvider != activeProvider && !providerChangeInProgress
    }
}

struct CalendarAccountRowPresentation: Equatable, Identifiable {
    let id: String
    let email: String?
    /// Nil while the account works.
    let notice: CalendarNotice?
    var canReconnect: Bool { notice?.action == .reconnect }
    /// An account that must sign in again cannot refresh until it does.
    var canRefresh: Bool { !canReconnect }

    /// Google accounts in name order, each with how its latest refresh went.
    /// A refresh that failed as a whole, such as one that timed out, leaves
    /// every account showing its last known meetings.
    static func rows(
        for accounts: [ProviderAccountHealth],
        refreshFailed: Bool = false
    ) -> [CalendarAccountRowPresentation] {
        accounts
            .map { account in
                switch account.status {
                case .connected where refreshFailed:
                    CalendarAccountRowPresentation(
                        id: account.id,
                        email: account.email,
                        notice: CalendarNotice(textKey: "preferences_calendars_refresh_failed", tone: .warning)
                    )
                case .connected:
                    CalendarAccountRowPresentation(
                        id: account.id,
                        email: account.email,
                        notice: nil
                    )
                case .authRequired:
                    CalendarAccountRowPresentation(
                        id: account.id,
                        email: account.email,
                        notice: CalendarNotice(
                            textKey: "preferences_calendars_google_account_reconnect_required",
                            tone: .error,
                            action: .reconnect
                        )
                    )
                case .failed:
                    CalendarAccountRowPresentation(
                        id: account.id,
                        email: account.email,
                        notice: CalendarNotice(textKey: "preferences_calendars_refresh_failed", tone: .warning)
                    )
                }
            }
            .sorted {
                ($0.email ?? $0.id).localizedStandardCompare($1.email ?? $1.id) == .orderedAscending
            }
    }
}

struct CalendarListSection: Equatable, Identifiable {
    let source: String
    let calendars: [MBCalendar]
    /// The Google account the calendars come from, with its status and actions.
    var account: CalendarAccountRowPresentation?

    var id: String { account?.id ?? source }

    /// Drives the section's "all calendars" switch: on only when every
    /// calendar in it is selected.
    func allSelected(in selectedIDs: [String]) -> Bool {
        !calendars.isEmpty && Set(calendars.map(\.id)).isSubset(of: selectedIDs)
    }
}

enum CalendarListPresentation {
    /// Calendars grouped by account, with the accounts and the calendars in
    /// each listed in name order.
    static func sections(for calendars: [MBCalendar]) -> [CalendarListSection] {
        Dictionary(grouping: calendars, by: \.source)
            .map { source, calendars in
                CalendarListSection(
                    source: source,
                    calendars: calendars.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
                )
            }
            .sorted { $0.source.localizedStandardCompare($1.source) == .orderedAscending }
    }

    /// One section per connected account, in name order, each holding that
    /// account's calendars. An account with no calendars yet still gets its
    /// section so it can be reconnected or removed.
    static func sections(
        for calendars: [MBCalendar],
        accounts: [ProviderAccountHealth],
        isStale: Bool = false
    ) -> [CalendarListSection] {
        guard !accounts.isEmpty else { return sections(for: calendars) }
        var remaining = calendars
        // Stale with every account fine means the refresh failed as a whole.
        let refreshFailed = isStale && accounts.allSatisfy { $0.status == .connected }
        let rows = CalendarAccountRowPresentation.rows(for: accounts, refreshFailed: refreshFailed)
        let accountSections = rows.map { row in
            let key = row.email.map(GoogleAccountKey.make(email:))
            let owned = remaining.filter { $0.email.map(GoogleAccountKey.make(email:)) == key }
            remaining.removeAll { $0.email.map(GoogleAccountKey.make(email:)) == key }
            return CalendarListSection(
                source: row.email ?? row.id,
                calendars: owned.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending },
                account: row
            )
        }
        return accountSections + sections(for: remaining)
    }
}

extension Browser {
    /// A browser with no app path opens links in the Mac's default browser.
    /// Older settings saved that choice under other names, such as "Default
    /// Browser", so pickers show every such value as the one system option.
    var pickerValue: Browser { path.isEmpty ? systemDefaultBrowser : self }
}

enum BrowserPickerOptions {
    static func make(
        configured: [Browser],
        selected: Browser,
        systemDefault: Browser = systemDefaultBrowser
    ) -> [Browser] {
        var options = [systemDefault]
        for browser in configured + [selected] {
            let option = browser.path.isEmpty ? systemDefault : browser
            if !options.contains(option) {
                options.append(option)
            }
        }
        return options
    }

    static func selection(_ browser: Binding<Browser>) -> Binding<Browser> {
        Binding(get: { browser.wrappedValue.pickerValue }, set: { browser.wrappedValue = $0 })
    }
}

struct RegexEditDraft: Equatable, Identifiable {
    let originalValue: String?
    var value: String

    /// Identity for `.sheet(item:)` presentation. `nil` originalValue (an add)
    /// gets a distinct id from any edit so the editor rebuilds with the right
    /// seed value each time it is presented.
    var id: String { originalValue ?? "" }

    static func adding() -> RegexEditDraft {
        RegexEditDraft(originalValue: nil, value: "")
    }

    static func editing(_ regex: String) -> RegexEditDraft {
        RegexEditDraft(originalValue: regex, value: regex)
    }
}

enum RegexListSaveResult: Equatable {
    case saved([String])
    case duplicate
    case originalMissing
}

enum RegexListEditingPolicy {
    static func saving(
        _ draft: RegexEditDraft,
        in regexes: [String]
    ) -> RegexListSaveResult {
        if let originalValue = draft.originalValue {
            guard let index = regexes.firstIndex(of: originalValue) else {
                return .originalMissing
            }
            guard draft.value == originalValue || !regexes.contains(draft.value) else {
                return .duplicate
            }

            var updated = regexes
            updated[index] = draft.value
            return .saved(updated)
        }

        guard !regexes.contains(draft.value) else {
            return .duplicate
        }
        return .saved(regexes + [draft.value])
    }
}

enum MeetingProviderBrowserSelection {
    static func selectedBrowser(
        providerID: String,
        providerBrowsers: [String: Browser]
    ) -> Browser {
        providerBrowsers[providerID] ?? systemDefaultBrowser
    }

    static func updating(
        providerID: String,
        browser: Browser,
        providerBrowsers: [String: Browser]
    ) -> [String: Browser] {
        var updated = providerBrowsers
        if browser == systemDefaultBrowser {
            updated.removeValue(forKey: providerID)
        } else {
            updated[providerID] = browser
        }
        return updated
    }
}

enum MeetingProviderOpeningSelection: Hashable {
    case browser(Browser)
    case mode(MeetingOpeningMode)
}

struct MeetingProviderOpeningPreferences: Equatable {
    let providerBrowsers: [String: Browser]
    let providerOpeningModes: [String: String]
}

enum MeetingProviderOpeningSelectionPolicy {
    static func selected(
        provider: MeetingProvider,
        providerBrowsers: [String: Browser],
        providerOpeningModes: [String: String]
    ) -> MeetingProviderOpeningSelection {
        if let modeID = providerOpeningModes[provider.id],
           let mode = MeetingOpeningMode(rawValue: modeID),
           provider.openingModes.contains(mode) {
            return .mode(mode)
        }
        if let browser = providerBrowsers[provider.id] {
            if let mode = legacyOpeningMode(for: provider, browser: browser) {
                return .mode(mode)
            }
            return .browser(browser.pickerValue)
        }
        return .browser(systemDefaultBrowser)
    }

    static func updating(
        provider: MeetingProvider,
        selection: MeetingProviderOpeningSelection,
        providerBrowsers: [String: Browser],
        providerOpeningModes: [String: String]
    ) -> MeetingProviderOpeningPreferences {
        var browsers = providerBrowsers
        var modes = providerOpeningModes

        switch selection {
        case .browser(let browser):
            modes.removeValue(forKey: provider.id)
            if browser == systemDefaultBrowser {
                browsers.removeValue(forKey: provider.id)
            } else {
                browsers[provider.id] = browser
            }
        case .mode(let mode):
            guard provider.openingModes.contains(mode) else {
                modes.removeValue(forKey: provider.id)
                return MeetingProviderOpeningPreferences(
                    providerBrowsers: browsers,
                    providerOpeningModes: modes
                )
            }
            modes[provider.id] = mode.rawValue
            if let browser = browsers[provider.id],
               legacyOpeningMode(for: provider, browser: browser) != nil {
                browsers.removeValue(forKey: provider.id)
            }
        }

        return MeetingProviderOpeningPreferences(
            providerBrowsers: browsers,
            providerOpeningModes: modes
        )
    }
}
