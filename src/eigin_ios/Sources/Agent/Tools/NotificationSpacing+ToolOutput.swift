import Foundation

extension NotificationSpacingWarning {
    var message: String {
        let times = formattedTimes
        return "Notification scheduled for \(times.proposed). Another is at \(times.existing). Consider combining them or choosing another time if that suits the user better."
    }

    fileprivate var formattedTimes: (proposed: String, existing: String) {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        let zone = formatter.timeZone ?? .current
        let offsetsDiffer = zone.secondsFromGMT(for: proposedAt) != zone
            .secondsFromGMT(for: existingAt)
        func format(_ date: Date) -> String {
            let text = formatter.string(from: date)
            guard offsetsDiffer,
                  let abbreviation = zone.abbreviation(for: date) else { return text }
            return "\(text) \(abbreviation)"
        }
        let proposed = format(proposedAt)
        if Calendar.current.isDate(proposedAt, inSameDayAs: existingAt) {
            formatter.dateStyle = .none
        }
        return (proposed, format(existingAt))
    }
}

extension NotificationSpacingConflict: LocalizedError {
    var errorDescription: String? {
        let times = occurrence.formattedTimes
        let minutes = (interval / 60).formatted(.number.precision(.fractionLength(0 ... 2)))
        return "Notification not saved: \(times.proposed) is less than \(minutes) minutes from another at \(times.existing). Combine them or choose another time."
    }
}
