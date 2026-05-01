import Foundation

enum AppKeys {
    static let bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.example.app"

    static let keychainServiceName: String = bundleIdentifier

    static let backgroundTaskIdentifier: String = bundleIdentifier + ".backgroundprompt"

    static let downloadSessionIdentifier: String = bundleIdentifier + ".download"

    static let logSinkQueueLabel: String = bundleIdentifier + ".logsink"
}
