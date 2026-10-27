import Foundation
import os

/// Tracks whether the first-run tour has been completed and whether it should
/// be shown again on launch. Every feature in Dojix is available to everyone;
/// there are no plans, tiers or trials.
@Observable
final class OnboardingManager: @unchecked Sendable {
    // Note: @unchecked Sendable because OnboardingManager is stored in AppState
    // (non-isolated). All property mutations happen on the MainActor via SwiftUI views.
    private static let logger = Logger(subsystem: "com.dojix", category: "Onboarding")
    private static let onboardingCompleteKey = "onboarding_complete"
    private static let tourOnLaunchKey = "show_tour_on_launch"
    private static let firstOnboardingDoneKey = "first_onboarding_done"

    var isOnboardingComplete: Bool

    init() {
        // The tour shows on first launch only (it used to reappear on every launch
        // until the user found "Don't show this again"). It can be reopened from Settings.
        let firstDone = UserDefaults.standard.bool(forKey: Self.firstOnboardingDoneKey)
        self.isOnboardingComplete = firstDone && !UserDefaults.standard.bool(forKey: Self.tourOnLaunchKey)
    }

    /// Show the tour again now (Settings > About > Show Welcome Tour)
    func showTourAgain() {
        isOnboardingComplete = false
    }

    /// Whether this is the very first onboarding (never completed before)
    var isFirstOnboarding: Bool {
        !UserDefaults.standard.bool(forKey: Self.firstOnboardingDoneKey)
    }

    /// Whether the tour should show on every launch (off unless the user had it on)
    var showTourOnLaunch: Bool {
        UserDefaults.standard.bool(forKey: Self.tourOnLaunchKey)
    }

    /// Mark onboarding as complete for this launch
    func completeOnboarding() {
        isOnboardingComplete = true
        UserDefaults.standard.set(true, forKey: Self.onboardingCompleteKey)
        if !UserDefaults.standard.bool(forKey: Self.firstOnboardingDoneKey) {
            UserDefaults.standard.set(true, forKey: Self.firstOnboardingDoneKey)
            Self.logger.info("First onboarding complete")
        }
    }

    /// Disable tour on future launches
    func disableTourOnLaunch() {
        UserDefaults.standard.set(false, forKey: Self.tourOnLaunchKey)
    }

    /// Reset onboarding (for testing)
    func resetOnboarding() {
        isOnboardingComplete = false
        UserDefaults.standard.set(false, forKey: Self.onboardingCompleteKey)
    }
}
