//
//  OnboardingView.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 24.08.2020.
//  Copyright © 2020 Andrii Leitsius. All rights reserved.
//
import Combine
import Defaults
import KeyboardShortcuts
import LaunchAtLogin
import SwiftUI

/// Setup steps the onboarding flow walks through. Future steps (post-setup
/// recap, etc.) can be inserted without changing how individual screens drive
/// the transition.
enum OnboardingStep: Hashable {
    case welcome
    case calendarSource
    case authorization
    case calendarSelection
    case essentials
    case success
}

enum OnboardingAuthorizationState: Equatable {
    case idle
    case requesting
    case failed(String)
}

enum OnboardingFlowPolicy {
    static func canContinueCalendarSelection(
        selectedCalendarIDs: [String],
        availableCalendarIDs: [String]
    ) -> Bool {
        !Set(selectedCalendarIDs).isDisjoint(with: availableCalendarIDs)
    }

    static func authorizationState(
        for result: ProviderSelectionResult
    ) -> OnboardingAuthorizationState? {
        switch result {
        case .success:
            return nil
        case .cancelled:
            return .failed("access_screen_provider_authorization_cancelled".loco())
        case .authRequired(let description), .failed(let description):
            return .failed(description)
        }
    }
}

@MainActor
final class OnboardingRouter: ObservableObject {
    @Published var currentStep: OnboardingStep = .welcome
    @Published var selectedProvider: EventStoreProvider?
    @Published var authorizationState: OnboardingAuthorizationState = .idle

    func selectProvider(_ provider: EventStoreProvider) {
        selectedProvider = provider
        authorizationState = .idle
        currentStep = .authorization
    }
}

/// Maps a step to its position among the user-facing setup stages. The
/// authorization step shares stage 2 with source selection (it runs
/// automatically), and `success` is terminal, so neither shows a distinct
/// progress position.
enum OnboardingProgressPolicy {
    static let stageTitleKeys = [
        "onboarding_stage_welcome",
        "onboarding_stage_calendar_source",
        "onboarding_stage_calendars",
        "onboarding_stage_essentials"
    ]
    static var totalStages: Int { stageTitleKeys.count }

    static func stageIndex(for step: OnboardingStep) -> Int? {
        switch step {
        case .welcome: 1
        case .calendarSource, .authorization: 2
        case .calendarSelection: 3
        case .essentials: 4
        case .success: nil
        }
    }
}

struct OnboardingView: View {
    @StateObject private var router = OnboardingRouter()

    var body: some View {
        VStack(spacing: 0) {
            OnboardingProgress(step: router.currentStep)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            VStack(alignment: .leading) {
                switch router.currentStep {
                case .welcome:
                    WelcomeScreen(router: router)
                case .calendarSource:
                    AccessScreen(router: router)
                case .authorization:
                    AuthorizationScreen(router: router)
                case .calendarSelection:
                    CalendarsScreen(router: router)
                case .essentials:
                    EssentialsScreen(router: router)
                case .success:
                    OnboardingSuccessScreen()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(20)
        }
    }
}

/// Numbered stepper shown in the window header. Each stage shows its title so
/// users can see what's coming; completed stages show a checkmark. `success`
/// has no stage of its own, so every stage shows as completed there.
private struct OnboardingProgress: View {
    let step: OnboardingStep

    var body: some View {
        let total = OnboardingProgressPolicy.totalStages
        let current = OnboardingProgressPolicy.stageIndex(for: step) ?? total + 1
        HStack(spacing: 10) {
            ForEach(Array(OnboardingProgressPolicy.stageTitleKeys.enumerated()), id: \.offset) { offset, key in
                let stage = offset + 1
                if stage > 1 {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(width: 24, height: 1)
                }
                OnboardingStageLabel(number: stage, title: key.loco(), current: current)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            Text("onboarding_progress".loco("\(min(current, total))", "\(total)"))
        )
    }
}

private struct OnboardingStageLabel: View {
    let number: Int
    let title: String
    let current: Int

    private var isCompleted: Bool { number < current }
    private var isCurrent: Bool { number == current }

    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(isCompleted || isCurrent ? Color.accentColor : Color.clear)
                Circle()
                    .strokeBorder(
                        isCompleted || isCurrent ? Color.accentColor : Color.secondary.opacity(0.5),
                        lineWidth: 1
                    )
                if isCompleted {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Text("\(number)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isCurrent ? Color.white : Color.secondary)
                }
            }
            .frame(width: 20, height: 20)

            Text(title)
                .font(.callout.weight(isCurrent ? .semibold : .regular))
                .foregroundStyle(isCurrent ? Color.primary : Color.secondary)
                .lineLimit(1)
        }
    }
}

/// Shared footer for onboarding screens: an optional Back button on the
/// leading edge and an optional primary action on the trailing edge, with an
/// optional inline hint and busy spinner. Keeps navigation consistent across
/// every step instead of each screen hand-rolling its own button row.
struct OnboardingFooter: View {
    var onBack: (() -> Void)?
    var hint: String?
    var isBusy: Bool = false
    var primaryTitle: String?
    var primaryEnabled: Bool = true
    var primaryAction: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            if let onBack {
                Button("onboarding_back".loco(), action: onBack)
            }
            Spacer()
            if let hint {
                Text(hint)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if isBusy {
                ProgressView().controlSize(.small)
            }
            if let primaryTitle, let primaryAction {
                Button(primaryTitle, action: primaryAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!primaryEnabled || isBusy)
            }
        }
    }
}

/// Final setup step: a short first-run pass over the choices that affect daily
/// use immediately. The rest of the product-level configuration stays in
/// Preferences, where users have more context.
private struct EssentialsScreen: View {
    @ObservedObject var router: OnboardingRouter
    @EnvironmentObject var onboardingHandler: OnboardingHandler
    @State private var isCompleting = false
    @State private var errorMessage: String?

    @Default(.joinEventNotification) private var joinEventNotification
    @Default(.joinEventNotificationTime) private var joinEventNotificationTime
    @Default(.defaultBrowser) private var defaultBrowser
    @Default(.browsers) private var allBrowsers

    private var defaultBrowserOptions: [Browser] {
        BrowserPickerOptions.make(configured: allBrowsers, selected: defaultBrowser)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("onboarding_essentials_title".loco())
                .font(.title2)
                .bold()
            Text("onboarding_essentials_description".loco())
                .foregroundStyle(.secondary)

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    LaunchAtLogin.Toggle {
                        Text("preferences_general_option_login_launch".loco())
                    }

                    Divider()

                    HStack {
                        Text("preferences_services_link_meeting_title".loco())
                        Spacer()
                        defaultBrowserPicker
                    }

                    HStack {
                        Text(preferenceLabel("preferences_general_shortcut_join_next"))
                        Spacer()
                        KeyboardShortcuts.Recorder(for: .joinEventShortcut)
                    }

                    Divider()

                    HStack {
                        Toggle(
                            "shared_send_notification_toggle".loco(),
                            isOn: $joinEventNotification
                        )
                        Spacer()
                        notificationTimePicker
                    }
                }
                .padding(8)
            }

            Text("onboarding_essentials_hint".loco())
                .font(.caption)
                .foregroundStyle(.secondary)

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }

            Spacer()

            OnboardingFooter(
                onBack: { router.currentStep = .calendarSelection },
                isBusy: isCompleting,
                primaryTitle: "onboarding_start_using".loco(),
                primaryAction: { Task { await complete() } }
            )
        }
    }

    private var defaultBrowserPicker: some View {
        Picker("", selection: BrowserPickerOptions.selection($defaultBrowser)) {
            ForEach(defaultBrowserOptions, id: \.self) { (browser: Browser) in
                Text(browser.name).tag(browser)
            }
        }
        .labelsHidden()
        .fixedSize()
    }

    private var notificationTimePicker: some View {
        Picker("", selection: $joinEventNotificationTime) {
            Text("general_when_event_starts".loco()).tag(TimeBeforeEvent.atStart)
            Text("general_one_minute_before".loco()).tag(TimeBeforeEvent.minuteBefore)
            Text("general_three_minute_before".loco()).tag(TimeBeforeEvent.threeMinuteBefore)
            Text("general_five_minute_before".loco()).tag(TimeBeforeEvent.fiveMinuteBefore)
        }
        .labelsHidden()
        .fixedSize()
        .disabled(!joinEventNotification)
    }

    private func complete() async {
        guard let provider = router.selectedProvider else { return }
        isCompleting = true
        errorMessage = nil
        let result = await onboardingHandler.onComplete(provider)
        isCompleting = false

        switch result {
        case .success:
            router.currentStep = .success
        case .cancelled:
            errorMessage = "access_screen_provider_authorization_cancelled".loco()
        case .authRequired(let message), .failed(let message):
            errorMessage = message
        }
    }
}

private struct OnboardingSuccessScreen: View {
    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(.green)
            Text("onboarding_success_title".loco())
                .font(.title)
                .bold()
            Text("onboarding_success_description".loco())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            OnboardingFooter(
                primaryTitle: "onboarding_done".loco(),
                primaryAction: { NSApplication.shared.keyWindow?.close() }
            )
        }
    }
}
