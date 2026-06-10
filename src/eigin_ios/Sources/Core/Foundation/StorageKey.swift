enum StorageKey {
    static let selectedTheme = "selectedThemeID"
    static let appLanguage = "appLanguage"
    static let logSinkToFile = "logSinkToFile"
    static let logDebugMode = "logDebugMode"
    static let logFileLevel = "logFileLevel"
    static let onboardingComplete = "onboardingComplete"
    static let onboardingStep = "onboardingStep"
    /// The `CFBundleVersion` of the last app build for which the Gemma model
    /// prewarm pass completed successfully. When the running build version
    /// differs, `GemmaModelManager` runs a fresh prewarm pass.
    static let gemmaPrewarmedBuild = "gemmaPrewarmedBuild"
    /// Whether the user has declined to download the local Gemma model.
    static let gemmaDeclined = "coreml-gemma-declined"
}
