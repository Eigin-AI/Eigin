import Foundation

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

    init(
        type: FeedbackType,
        description: String,
        includeLogs: Bool,
        deviceInfo: any DeviceInfoService = DefaultDeviceInfoService()
    ) {
        self.type = type
        self.description = description
        self.includeLogs = includeLogs
        appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        systemVersion = deviceInfo.systemVersion()
        deviceModel = deviceInfo.deviceIdentifier()
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
