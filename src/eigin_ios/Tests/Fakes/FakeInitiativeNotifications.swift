@testable import Eigin
import Foundation
import UserNotifications

@MainActor final class FakeInitiativeNotifications: InitiativeNotificationAccess {
    var requests: [UNNotificationRequest] = []
    var deliveries: [DeliveredInitiativeNotification] = []
    var removedDeliveries: [String] = []
    var failAdds = false
    var dropAdds = false
    var failAfter: Int?
    var pendingSnapshots: [[UNNotificationRequest]] = []

    func pending() async -> [UNNotificationRequest] {
        if !pendingSnapshots.isEmpty { requests = pendingSnapshots.removeFirst() }
        return requests
    }

    func add(_ request: UNNotificationRequest) async throws {
        if failAdds || failAfter
            .map({ requests.count >= $0 }) == true { throw InitiativeError.registrationFailed }
        if dropAdds { return }
        requests.removeAll { $0.identifier == request.identifier }
        requests.append(request)
    }

    func delivered() async -> [DeliveredInitiativeNotification] {
        deliveries
    }

    func removeDelivered(_ identifiers: [String]) {
        removedDeliveries += identifiers
        deliveries.removeAll { identifiers.contains($0.identifier) }
    }

    func removePending(_ identifiers: [String]) {
        requests.removeAll { identifiers.contains($0.identifier) }
    }
}
