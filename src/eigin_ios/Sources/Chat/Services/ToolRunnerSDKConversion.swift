import EiginSDK

/// Maps host permissions and runner failures without changing chat tool result payloads.
enum ToolRunnerSDKConversion {
    typealias SDK = EiginSDK.Experimental.Agent

    static func permission(_ level: ToolPermissionLevel) -> SDK.Permission {
        switch level {
        case .always: .always
        case .ask: .ask
        case .never: .never
        }
    }

    static func grant(_ response: PermissionResponse) -> SDK.Grant {
        switch response {
        case .allowOnce: .once
        case .allowForChat: .forChat
        case .deny: .deny
        }
    }

    static func error(_ reason: SDK.Denial) -> String {
        switch reason {
        case .policy: Localized.Permission.toolDeniedByPolicy
        case .promptUnavailable: "Permission required. Ask the user to open the app to grant permission for this action."
        case .user: "User denied this action."
        }
    }
}
