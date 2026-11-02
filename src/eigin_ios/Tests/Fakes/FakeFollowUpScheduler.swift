@testable import Eigin
import Foundation

@MainActor
final class FakeFollowUpScheduler: FollowUpScheduling {
    var scheduledDates: [Date?] = []
    var error: Error?
    let requestID = UUID()

    func schedule(
        title: String,
        body: String,
        message: String,
        summary: String?,
        deliverAt: Date?,
        agentID: UUID,
        agentName: String?,
        agentEmoji: String?
    ) async throws -> UUID {
        if let error { throw error }
        scheduledDates.append(deliverAt)
        return requestID
    }
}
