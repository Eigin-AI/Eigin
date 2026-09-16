import Foundation
import OSLog

// MARK: - LogMessage

/// A log message with privacy-aware string interpolation.
///
/// Use `\(public: value)` for data safe to display, and `\(private: value)`
/// for sensitive data that should be redacted outside debug mode.
struct LogMessage: ExpressibleByStringInterpolation {
    enum Segment {
        case literal(String)
        case `public`(String)
        case `private`(String)
    }

    let segments: [Segment]

    init(stringInterpolation: StringInterpolation) {
        segments = stringInterpolation.segments
    }

    init(stringLiteral value: String) {
        segments = [.literal(value)]
    }

    struct StringInterpolation: StringInterpolationProtocol {
        var segments: [Segment] = []

        init(literalCapacity: Int, interpolationCount: Int) {
            segments.reserveCapacity(literalCapacity + interpolationCount)
        }

        mutating func appendLiteral(_ literal: String) {
            guard !literal.isEmpty else { return }
            segments.append(.literal(literal))
        }

        mutating func appendInterpolation(public value: @autoclosure ()
            -> any CustomStringConvertible)
        {
            segments.append(.public(String(describing: value())))
        }

        mutating func appendInterpolation(private value: @autoclosure ()
            -> any CustomStringConvertible)
        {
            segments.append(.private(String(describing: value())))
        }
    }

    /// Renders with private segments replaced by `<REDACTED>`.
    var redactedDescription: String {
        segments.map { segment in
            switch segment {
            case .literal(let s): s
            case .public(let s): s
            case .private: "<REDACTED>"
            }
        }.joined()
    }

    /// Renders all segments including private data.
    var fullDescription: String {
        segments.map { segment in
            switch segment {
            case .literal(let s), .public(let s), .private(let s): s
            }
        }.joined()
    }
}

// MARK: - AppLogger

/// Unified logging with OSLog + optional file sink.
///
/// ```swift
/// AppLogger.info("Loaded \(public: count) items for \(private: userID)", category: .chat)
/// ```
enum AppLogger {
    /// Minimum severity for file logging. OSLog always receives all levels.
    enum LogLevel: Int, CaseIterable, Identifiable {
        case debug = 0
        case info = 1
        case warning = 2
        case error = 3

        var id: Int {
            rawValue
        }

        var displayName: String {
            switch self {
            case .debug: "Debug"
            case .info: "Info"
            case .warning: "Warning"
            case .error: "Error"
            }
        }

        fileprivate var osLogType: OSLogType {
            switch self {
            case .debug: .debug
            case .info: .info
            case .warning: .error
            case .error: .fault
            }
        }

        fileprivate var label: String {
            switch self {
            case .debug: "DEBUG"
            case .info: "INFO"
            case .warning: "WARN"
            case .error: "ERROR"
            }
        }
    }

    enum Category: String {
        case general
        case chat
        case mcp
        case backgroundPrompt
        case livecall
        case tool
        case network
        case onboarding
        case routing
        case watch
    }

    static func debug(_ message: LogMessage, category: Category = .general) {
        log(message, level: .debug, category: category)
    }

    static func info(_ message: LogMessage, category: Category = .general) {
        log(message, level: .info, category: category)
    }

    static func warning(_ message: LogMessage, category: Category = .general) {
        log(message, level: .warning, category: category)
    }

    static func error(_ message: LogMessage, category: Category = .general) {
        log(message, level: .error, category: category)
    }

    /// Read the current file log contents.
    static func readLog() -> String {
        LogSink.shared.read()
    }

    /// URL to the current log file for sharing, or `nil` if no file exists.
    static func exportLog() -> URL? {
        LogSink.shared.export()
    }

    /// Clear the file log.
    static func clearLog() {
        LogSink.shared.clear()
    }

    // MARK: - Private

    private static let loggers = OSAllocatedUnfairLock(initialState: [String: os.Logger]())
    private static let subsystem = AppKeys.bundleIdentifier

    private static func osLogger(for category: Category) -> os.Logger {
        loggers.withLock { cache in
            if let existing = cache[category.rawValue] { return existing }
            let logger = os.Logger(subsystem: subsystem, category: category.rawValue)
            cache[category.rawValue] = logger
            return logger
        }
    }

    private static func log(_ message: LogMessage, level: LogLevel, category: Category) {
        let rendered = message.redactedDescription
        let logger = osLogger(for: category)
        let osLevel = level.osLogType

        switch osLevel {
        case .debug: logger.debug("\(rendered, privacy: .public)")
        case .info: logger.info("\(rendered, privacy: .public)")
        case .error: logger.error("\(rendered, privacy: .public)")
        case .fault: logger.fault("\(rendered, privacy: .public)")
        default: logger.log("\(rendered, privacy: .public)")
        }

        if UserDefaults.standard.bool(forKey: StorageKey.logSinkToFile) {
            let minLevel = LogLevel(rawValue: UserDefaults.standard
                .integer(forKey: StorageKey.logFileLevel)) ?? .debug
            guard level.rawValue >= minLevel.rawValue else { return }

            let debugMode = UserDefaults.standard.bool(forKey: StorageKey.logDebugMode)
            let text = debugMode ? message.fullDescription : message.redactedDescription
            LogSink.shared.append("[\(level.label)] [\(category.rawValue.uppercased())] \(text)")
        }
    }
}

// MARK: - LogSink

/// Serial-queue file writer with simple rotation.
private final class LogSink: Sendable {
    static let shared = LogSink()

    private let queue = DispatchQueue(label: AppKeys.logSinkQueueLabel)
    private let maxSize: UInt64 = 1024 * 1024 // 1 MB

    private var logURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("eigin.log")
    }

    private var rotatedURL: URL {
        logURL.deletingLastPathComponent().appendingPathComponent("eigin.1.log")
    }

    func append(_ line: String) {
        queue.async { [self] in
            let url = logURL
            let timestamp = Date()
                .formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
            let entry = "\(timestamp) \(line)\n"

            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }

            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            if let data = entry.data(using: .utf8) {
                handle.write(data)
            }

            rotateIfNeeded(url: url)
        }
    }

    func read() -> String {
        queue.sync {
            (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
        }
    }

    func export() -> URL? {
        queue.sync {
            let url = logURL
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
    }

    func clear() {
        queue.async { [self] in
            try? FileManager.default.removeItem(at: logURL)
            try? FileManager.default.removeItem(at: rotatedURL)
        }
    }

    private func rotateIfNeeded(url: URL) {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? UInt64, size > maxSize else { return }
        let rotated = rotatedURL
        try? FileManager.default.removeItem(at: rotated)
        try? FileManager.default.moveItem(at: url, to: rotated)
    }
}
