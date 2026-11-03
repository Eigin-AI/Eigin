@testable import Eigin
import Foundation
import UserNotifications

@MainActor
final class FakeLocalNotificationCenter: LocalNotificationScheduling {
    private(set) var requests: [UNNotificationRequest] = []
    let shouldFail: Bool
    var suspendAcceptance = false
    private var acceptance: CheckedContinuation<Void, Never>?
    var isWaitingForAcceptance: Bool {
        acceptance != nil
    }

    func accept() {
        acceptance?.resume()
        acceptance = nil
    }

    init(shouldFail: Bool = false) {
        self.shouldFail = shouldFail
    }

    func add(_ request: UNNotificationRequest) async throws {
        if shouldFail { throw NSError(domain: "NotificationTest", code: 1) }
        if suspendAcceptance {
            await withCheckedContinuation { acceptance = $0 }
        }
        requests.append(request)
    }
}

actor FakeNotificationAuthorization: NotificationAuthorizationAccess {
    let status: UNAuthorizationStatus
    private(set) var requestCount = 0

    init(status: UNAuthorizationStatus) {
        self.status = status
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        status
    }

    func requestAuthorization() async throws -> Bool {
        requestCount += 1
        return true
    }
}

@MainActor
struct FakeCommunicationNotificationPreparer: CommunicationNotificationPreparing {
    var onPrepare: () -> Void = {}

    func prepare(
        _ content: UNMutableNotificationContent,
        agentName: String,
        agentEmoji: String?,
        agentID: UUID,
        conversationID: String
    ) async -> UNNotificationContent {
        onPrepare()
        return content
    }
}
