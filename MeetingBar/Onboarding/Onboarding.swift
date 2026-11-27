//
//  OnboardingView.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 24.08.2020.
//  Copyright © 2020 Andrii Leitsius. All rights reserved.
//
import SwiftUI

/// Setup steps the onboarding flow walks through.
enum OnboardingStep: Hashable {
    case welcome
    case calendars
}

enum OnboardingFlowPolicy {
    static func canContinueCalendarSelection(
        selectedCalendarIDs: [String],
        availableCalendarIDs: [String]
    ) -> Bool {
        !Set(selectedCalendarIDs).isDisjoint(with: availableCalendarIDs)
    }
}

@MainActor
final class OnboardingRouter: ObservableObject {
    @Published var currentStep: OnboardingStep = .welcome
}

struct OnboardingView: View {
    @StateObject private var router = OnboardingRouter()

    var body: some View {
        VStack(alignment: .leading) {
            switch router.currentStep {
            case .welcome:
                WelcomeScreen(router: router)
            case .calendars:
                CalendarsScreen(router: router)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
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
