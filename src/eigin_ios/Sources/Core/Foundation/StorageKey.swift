enum StorageKey {
    static let selectedTheme = "selectedThemeID"
    static let appLanguage = "appLanguage"
    static let logSinkToFile = "logSinkToFile"
    static let logDebugMode = "logDebugMode"
    static let logFileLevel = "logFileLevel"
    static let onboardingComplete = "onboardingComplete"
    static let onboardingStep = "onboardingStep"
    /// The name the user gave during onboarding, seeded into the first conversation.
    static let onboardingUserName = "onboardingUserName"
    /// The user's selected ``OnboardingPriority`` raw value, persisted for later use.
    static let onboardingPriority = "onboardingPriority"
    /// The chat the onboarding conversation became, opened once when the app first
    /// loads — superseded by `PendingDestination.chat`; remapped at launch, not written
    /// anymore.
    static let pendingOnboardingChat = "pendingOnboardingChat"
    /// Asset directories with a download in progress (`AssetDownloadRegistry`).
    static let assetDownloadsInProgress = "assetDownloadsInProgress"
    /// Whether the user has declined to download the local Gemma model.
    static let gemmaDeclined = "coreml-gemma-declined"
    /// The chat watch-triggered questions continue, resolved by `WatchChat`.
    /// Lives in `UserDefaults` rather than the SwiftData schema, so the watch
    /// context carries across taps without a migration.
    static let watchChat = "watchChat"
}
