@testable import Eigin
import EiginSDK
import Foundation
import Testing

@Suite("SDKDiagnosticReceiver", .serialized)
struct SDKDiagnosticReceiverTests {
    @Test func routesSeverityAndPrivacyToAppLog() {
        let defaults = UserDefaults.standard
        let keys = [StorageKey.logSinkToFile, StorageKey.logFileLevel, StorageKey.logDebugMode]
        let saved = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, saved) {
                if let value { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
        }
        defaults.set(true, forKey: StorageKey.logSinkToFile)
        defaults.set(AppLogger.LogLevel.debug.rawValue, forKey: StorageKey.logFileLevel)
        let receiver = SDKDiagnosticReceiver()
        let marker = UUID().uuidString
        let levels: [(EiginSDK.Diagnostics.Level, String)] = [
            (.debug, "DEBUG"),
            (.info, "INFO"),
            (.warning, "WARN"),
            (.error, "ERROR"),
        ]
        for debugMode in [false, true] {
            defaults.set(debugMode, forKey: StorageKey.logDebugMode)
            for (level, label) in levels {
                let operation = "\(marker)-\(debugMode)-\(label)"
                receiver.receive(event: EiginSDK.Diagnostics.Event(
                    level: level,
                    component: "storage",
                    message: "Operation completed",
                    context: .init(operationId: operation, parentOperationId: "parent-1"),
                    fields: [
                        .init(name: "count", privacy: .public, value: "3"),
                        .init(name: "missing", privacy: .public, value: nil),
                        .init(name: "detail", privacy: .private, value: "private fixture"),
                        .init(name: "withheld", privacy: .private, value: nil),
                    ]
                ))
                let line = AppLogger.readLog().split(separator: "\n")
                    .first { $0.contains(operation) }
                #expect(line != nil)
                #expect(line?.contains("[\(label)] [SDK]") == true)
                #expect(line?.contains("count=3") == true)
                #expect(line?.contains("missing=<UNAVAILABLE>") == true)
                #expect(line?.contains("parent_operation_id=parent-1") == true)
                #expect(line?.contains("withheld=<REDACTED>") == true)
                #expect(line?
                    .contains(debugMode ? "detail=private fixture" : "detail=<REDACTED>") == true)
                if !debugMode { #expect(line?.contains("private fixture") == false) }
            }
        }
    }
}
