import Darwin
import UIKit

@MainActor
struct FeedbackReport: Identifiable {
    let id = UUID()
    let type: FeedbackType
    let description: String
    let includeLogs: Bool

    let appVersion: String
    let buildNumber: String
    let systemVersion: String
    let deviceModel: String

    init(type: FeedbackType, description: String, includeLogs: Bool) {
        self.type = type
        self.description = description
        self.includeLogs = includeLogs
        appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        systemVersion = UIDevice.current.systemVersion
        deviceModel = Self.machineIdentifier()
    }

    private static func machineIdentifier() -> String {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var machine = [UInt8](repeating: 0, count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        let identifier = String(decoding: machine.dropLast(), as: UTF8.self)
#if targetEnvironment(simulator)
        return ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? identifier
#else
        return identifier
#endif
    }

    var subject: String {
        "[Feedback] \(type.displayName)"
    }

    var body: String {
        """
        Hi, I've got feedback for you.

        Type: \(type.displayName)
        App Version: \(appVersion) (\(buildNumber))
        iOS: \(systemVersion)
        Device: \(deviceModel)

        ---

        \(description)
        """
    }

    var logData: Data? {
        guard includeLogs else { return nil }
        return AppLogger.readLog().data(using: .utf8)
    }
}
