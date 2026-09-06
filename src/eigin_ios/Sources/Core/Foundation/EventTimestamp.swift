import Foundation

/// Formats dates for prompts the user reads — permission sheets and other
/// confirmations — in the app's language and the reader's hour cycle.
///
/// Tool arguments and results use ``LocalDateFormatter``, which is agent-facing
/// and deliberately machine-shaped.
enum EventTimestamp {
    /// A date and time, e.g. `"Fri, Sep 11, 12:00 PM"` (`"fre. 11. sep. 12.00"` in Danish).
    static func string(for date: Date) -> String {
        formatter(template: "EEEdMMMjmm").string(from: date)
    }

    /// A time on its own, for the end of a same-day range.
    static func time(for date: Date) -> String {
        formatter(template: "jmm").string(from: date)
    }

    private static func formatter(template: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: UserDefaults.standard
            .string(forKey: StorageKey.appLanguage) ?? "en")
        formatter.timeZone = .current
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter
    }
}
