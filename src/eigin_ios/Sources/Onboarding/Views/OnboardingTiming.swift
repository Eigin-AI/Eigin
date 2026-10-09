import Foundation

/// The rhythm of the onboarding setup screens, in one place for tuning.
enum OnboardingTiming {
    // MARK: - Opening

    /// When the welcome title starts: as the rise settles, not after it. The
    /// opening's own moves are in ``OpeningTimeline``.
    static let welcomeTitleDelay: Duration = .seconds(OpeningTimeline.titleAt)

    // MARK: - Screen changes

    /// The outgoing screen's fade. The next title waits for it.
    static let turnFade: Double = 0.2
    /// Beat before each later screen's title, so it starts once the old one is gone.
    static let turnTitleDelay: Duration = .milliseconds(250)
    /// Longest wait for the keyboard to leave before the screen changes anyway.
    static let keyboardSettleLimit: Duration = .milliseconds(600)

    // MARK: - Speech

    /// Beat between the title appearing and the body streaming.
    static let streamDelay: Duration = .milliseconds(600)
    /// Pace of the simulated stream, per word.
    static let wordInterval: Duration = .milliseconds(45)
    /// Beat after the line lands before the screen's content appears.
    static let contentDelay: Duration = .milliseconds(700)
}
