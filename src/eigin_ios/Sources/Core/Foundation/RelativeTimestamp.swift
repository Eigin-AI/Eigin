import Foundation

enum RelativeTimestamp {
    static func string(for date: Date) -> String {
        let calendar = Calendar.current
        let now = Date.now

        if now.timeIntervalSince(date) < 60 {
            return Localized.Timestamp.justNow
        }

        if calendar.isDateInToday(date) {
            return Localized.Timestamp.today
        }

        if calendar.isDateInYesterday(date) {
            return Localized.Timestamp.yesterday
        }

        let appLocale = Locale(identifier: UserDefaults.standard
            .string(forKey: StorageKey.appLanguage) ?? "en")

        let daysAgo = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: date),
            to: calendar.startOfDay(for: now)
        ).day ?? 0
        if daysAgo >= 2, daysAgo <= 6 {
            let formatter = DateFormatter()
            formatter.locale = appLocale
            formatter.dateFormat = "EEEE"
            return formatter.string(from: date)
        }

        let formatter = DateFormatter()
        formatter.locale = appLocale
        formatter.dateStyle = .short
        return formatter.string(from: date)
    }
}
