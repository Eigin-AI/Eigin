import Foundation

/// Which cloud AI providers the user has allowed Eigin to share data with.
///
/// Consent is per provider address, asked once, before anything personal is
/// sent (App Store guideline 5.1.2). On-device models never need it.
protocol AIConsentStore: Sendable {
    /// Whether conversations may be sent to the provider at `baseURL`.
    func isAllowed(baseURL: String) -> Bool
    /// Records that the user allowed sharing with the provider at `baseURL`.
    func allow(baseURL: String)
}

extension AIConsentStore {
    /// Whether the user must be asked before anything is sent to `baseURL`.
    func needsConsent(baseURL: String) -> Bool {
        !ProviderPreset.isLocal(baseURL) && !isAllowed(baseURL: baseURL)
    }
}

/// Raised instead of sending when the provider has not been allowed yet.
enum AIConsentError: LocalizedError {
    case notAllowed

    var errorDescription: String? {
        "Sharing with this AI provider has not been allowed."
    }
}

/// Keeps consent in `UserDefaults`, outside the SwiftData schema.
final class DefaultAIConsentStore: AIConsentStore {
    private nonisolated(unsafe) let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func isAllowed(baseURL: String) -> Bool {
        allowed().contains(baseURL)
    }

    func allow(baseURL: String) {
        defaults.set(Array(allowed().union([baseURL])).sorted(), forKey: StorageKey.aiConsent)
    }

    private func allowed() -> Set<String> {
        Set(defaults.stringArray(forKey: StorageKey.aiConsent) ?? [])
    }
}
