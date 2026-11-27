//
//  OnboardingHandler.swift
//  MeetingBar
//
//  Holds the app-level callback that the calendars step invokes to finish
//  setup. Injected as an EnvironmentObject so no view needs to reach into
//  AppDelegate directly.
//

import Foundation

/// Observable wrapper around onboarding application workflows.
///
/// AppDelegate creates one instance, stores the completion logic in it, and
/// injects it into `OnboardingView` via `.environmentObject(handler)`.
@MainActor
final class OnboardingHandler: ObservableObject {
    var onComplete:
        @MainActor (EventStoreProvider) async -> ProviderSelectionResult

    @Published var appModel: AppModel?

    init(
        onComplete:
            @escaping @MainActor (EventStoreProvider) async -> ProviderSelectionResult
    ) {
        self.onComplete = onComplete
    }
}
