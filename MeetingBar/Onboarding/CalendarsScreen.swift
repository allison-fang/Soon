//
//  CalendarsScreen.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 13.01.2021.
//  Copyright © 2021 Andrii Leitsius. All rights reserved.
//

import SwiftUI

struct CalendarsScreen: View {
    @ObservedObject var router: OnboardingRouter
    @EnvironmentObject var onboardingHandler: OnboardingHandler

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let appModel = onboardingHandler.appModel {
                // Observe appModel here so the footer's enabled state recomputes
                // when a calendar is toggled (CalendarsScreen itself only
                // observes the router and handler, which don't change on toggle).
                CalendarSelectionStep(router: router, appModel: appModel)
            } else {
                ProgressView()
                Spacer()
                OnboardingFooter(onBack: { router.currentStep = .welcome })
            }
        }
    }
}

private struct CalendarSelectionStep: View {
    @ObservedObject var router: OnboardingRouter
    @ObservedObject var appModel: AppModel
    @EnvironmentObject var onboardingHandler: OnboardingHandler
    @State private var isCompleting = false
    @State private var errorMessage: String?

    var body: some View {
        CalendarsTab()
            .environmentObject(appModel)
            .frame(maxHeight: .infinity)

        if let errorMessage {
            Text(errorMessage)
                .foregroundStyle(.red)
        }

        OnboardingFooter(
            onBack: { router.currentStep = .welcome },
            hint: canFinish
                ? nil
                : PreferencesCalendarPresentation.make(from: appModel.state).nextStepHintKey.loco(),
            isBusy: isCompleting,
            primaryTitle: "onboarding_done".loco(),
            primaryEnabled: canFinish,
            primaryAction: { Task { await complete() } }
        )
    }

    private func complete() async {
        isCompleting = true
        errorMessage = nil
        let result = await onboardingHandler.onComplete(appModel.state.activeProvider)
        isCompleting = false

        switch result {
        case .success:
            NSApplication.shared.keyWindow?.close()
        case .cancelled:
            break
        case .authRequired(let message), .failed(let message):
            errorMessage = message
        }
    }

    private var canFinish: Bool {
        !appModel.state.providerChangeInProgress
            && OnboardingFlowPolicy.canContinueCalendarSelection(
                selectedCalendarIDs: appModel.state.selectedCalendarIDs,
                availableCalendarIDs: appModel.state.calendars.map(\.id)
            )
    }
}
