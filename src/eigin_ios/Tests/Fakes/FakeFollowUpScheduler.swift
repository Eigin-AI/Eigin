@testable import Eigin
import Foundation

@MainActor
final class FakeFollowUpScheduler: FollowUpScheduling {
    var scheduledDates: [Date?] = []
    var error: Error?
    let requestID = UUID()
    var deliveryStatus: FollowUpDeliveryStatus = .scheduled
    var prompted: Bool?
    var spaceID: UUID?

    func schedule(
        title: String,
        body: String,
        message: String,
        summary: String?,
        deliverAt: Date?,
        agentID: UUID,
        agentName: String?,
        agentEmoji: String?,
        spaceID: UUID?,
        canPromptUser: Bool
    ) async throws -> FollowUpScheduleResult {
        if let error { throw error }
        scheduledDates.append(deliverAt)
        prompted = canPromptUser
        self.spaceID = spaceID
        return FollowUpScheduleResult(
            requestID: requestID,
            dueAt: deliverAt ?? .now,
            deliveryStatus: deliveryStatus
        )
    }
}
