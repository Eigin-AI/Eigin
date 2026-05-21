import Foundation

enum AppKeys {
    static let bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.example.app"

    static let keychainServiceName: String = bundleIdentifier

    static let backgroundTaskIdentifier: String = bundleIdentifier + ".backgroundprompt"

    static let downloadSessionIdentifier: String = bundleIdentifier + ".download"

    static let notifyOnGemmaReadyKey: String = bundleIdentifier + ".notifyOnGemmaReady"

    static let logSinkQueueLabel: String = bundleIdentifier + ".logsink"

    static let supportEmail: String =
        Bundle.main.infoDictionary?["EiginSupportEmail"] as? String ?? "support@eigin.ai"
}
