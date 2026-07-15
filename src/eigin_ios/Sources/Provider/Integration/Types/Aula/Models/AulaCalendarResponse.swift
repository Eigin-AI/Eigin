import Foundation

/// Response shape for `calendar.getEventsByProfileIdsAndResourceIds`.
struct AulaCalendarResponse: Decodable {
    let data: [Event]

    struct Event: Decodable {
        let id: Int
        let title: String?
        let startDateTime: String?
        let endDateTime: String?
        let belongsToProfiles: [Int]?
        let primaryResourceText: String?
    }
}
