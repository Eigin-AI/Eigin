import Foundation

extension FirmEntity {
    /// Returns true if the entity is valid at the given date.
    ///
    /// - `valid_from` falls back to `created_at`, then `.distantPast`
    /// - `valid_until` falls back to `.distantFuture` (no expiry)
    /// - Date-only `valid_until` values are treated as end-of-day (23:59:59)
    func isValid(at date: Date) -> Bool {
        let from = parseDate(fieldNamed: "valid_from")
            ?? parseDate(fieldNamed: "created_at")
            ?? .distantPast
        let until = parseDate(fieldNamed: "valid_until", endOfDayIfDateOnly: true)
            ?? .distantFuture
        return from <= date && date <= until
    }

    // MARK: - Private

    private func parseDate(fieldNamed name: String, endOfDayIfDateOnly: Bool = false) -> Date? {
        guard let field = fields.first(where: { $0.name == name }) else { return nil }
        let raw: String
        switch field.value {
        case .dateTime(let value): raw = value
        case .string(let value): raw = value
        default: return nil
        }
        return LocalDateFormatter.parse(raw, endOfDayIfDateOnly: endOfDayIfDateOnly)
    }
}
