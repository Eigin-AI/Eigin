import EiginSDK
import Foundation

/// Routes SDK diagnostics through the application's destination-specific privacy rules.
final class SDKDiagnosticReceiver: EiginSDK.Diagnostics.Receiver, Sendable {
    /// Installs diagnostics before SDK initialization using the persisted logging settings.
    static func install() {
        EiginSDK.Diagnostics.setReceiver(SDKDiagnosticReceiver(), options: options)
    }

    /// Applies the current logging settings to future SDK events.
    static func updateOptions() {
        EiginSDK.Diagnostics.updateOptions(options)
    }

    private static var options: EiginSDK.Diagnostics.Options {
        let rawLevel = UserDefaults.standard.object(forKey: StorageKey.logFileLevel) as? Int
        let level = AppLogger
            .LogLevel(rawValue: rawLevel ?? AppLogger.LogLevel.info.rawValue) ?? .info
        let minimumLevel: EiginSDK.Diagnostics.Level = switch level {
        case .debug: .debug
        case .info: .info
        case .warning: .warning
        case .error: .error
        }
        return .init(
            minimumLevel: minimumLevel,
            includePrivate: UserDefaults.standard.bool(forKey: StorageKey.logDebugMode)
        )
    }

    func receive(event: EiginSDK.Diagnostics.Event) {
        let message = Self.message(for: event)
        switch event.level {
        case .debug: AppLogger.debug(message, category: .sdk)
        case .info: AppLogger.info(message, category: .sdk)
        case .warning: AppLogger.warning(message, category: .sdk)
        case .error: AppLogger.error(message, category: .sdk)
        }
    }

    /// Preserves classification until AppLogger chooses a rendering for each destination.
    private static func message(for event: EiginSDK.Diagnostics.Event) -> LogMessage {
        var segments: [LogMessage.Segment] = [.public("[\(event.component)] \(event.message)")]
        if let context = event.context {
            segments.append(.public(" operation_id=\(context.operationId)"))
            if let parent = context.parentOperationId {
                segments.append(.public(" parent_operation_id=\(parent)"))
            }
        }
        for field in event.fields {
            segments.append(.public(" \(field.name)="))
            switch field.privacy {
            case .public: segments.append(.public(field.value ?? "<UNAVAILABLE>"))
            case .private: segments.append(.private(field.value ?? "<REDACTED>"))
            }
        }
        return LogMessage(segments: segments)
    }
}
