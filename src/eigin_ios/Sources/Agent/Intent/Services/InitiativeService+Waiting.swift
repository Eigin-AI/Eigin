import Foundation
import SwiftData

extension InitiativeService {
    /// Both headers read the same committed projection, across the agent's spaces.
    func invitations(for agentID: UUID?) -> [WaitingMessage] {
        waiting.filter { $0.agentID == agentID }
    }

    func setActive(_ active: Bool) {
        isActive = active
        dueRefresh?.cancel()
        dueRefresh = nil
        if active { Task { await self.reconcile() } }
    }

    func refreshWaiting() throws {
        let context = ModelContext(modelContainer)
        let now = Date.now
        let next = try WaitingInitiativeStore.reconcile(context: context, now: now)
        waiting = try WaitingMessageStore.messages(context: context, now: now)
        dueRefresh?.cancel()
        dueRefresh = nil
        if isActive, let next {
            let delay = max(1, next.timeIntervalSinceNow)
            dueRefresh = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                guard !Task.isCancelled else { return }
                await self?.reconcile()
            }
        }
    }

    func dismissInvitation(id: String) throws {
        let context = ModelContext(modelContainer)
        if let requestID = followUpID(id) {
            try WaitingMessageStore.dismissFollowUp(id: requestID, context: context)
        } else {
            try WaitingInitiativeStore.dismiss(id: recurringID(id), context: context)
        }
        try refreshWaiting()
        Task { await cleanDeliveredNotifications() }
    }

    func openInvitation(id: String) throws -> UUID {
        let context = ModelContext(modelContainer)
        try WaitingInitiativeStore.reconcile(context: context)
        let chatID: UUID = if let requestID = followUpID(id) {
            try WaitingMessageStore.openFollowUp(id: requestID, context: context)
        } else {
            try WaitingInitiativeStore.open(id: recurringID(id), context: context)
        }
        try refreshWaiting()
        Task { await cleanDeliveredNotifications() }
        return chatID
    }

    /// Notification and list entry share the same persisted follow-up claim.
    func openFollowUp(requestID: UUID, legacySpaceID: UUID? = nil) throws -> UUID {
        let context = ModelContext(modelContainer)
        try WaitingInitiativeStore.reconcile(context: context)
        let chatID = try WaitingMessageStore.openFollowUp(
            id: requestID,
            context: context,
            legacySpaceID: legacySpaceID
        )
        try refreshWaiting()
        Task { await cleanDeliveredNotifications() }
        return chatID
    }

    private func followUpID(_ id: String) -> UUID? {
        guard id.hasPrefix("follow-up:") else { return nil }
        return UUID(uuidString: String(id.dropFirst("follow-up:".count)))
    }

    private func recurringID(_ id: String) -> String {
        id.hasPrefix("recurring:") ? String(id.dropFirst("recurring:".count)) : id
    }

    /// Remove handled deliveries without removing their repeating requests.
    func cleanDeliveredNotifications() async {
        let delivered = await scheduler.notifications.delivered()
        let context = ModelContext(modelContainer)
        guard let items = try? context.fetch(FetchDescriptor<WaitingInitiative>()) else { return }
        guard let requests = try? context.fetch(FetchDescriptor<AgentInitiativeRequest>())
        else { return }
        let handledFollowUps = Set(requests.filter { $0.handledAt != nil || $0.disposition != nil }
            .map(\.id))
        let retained = Set(items.map(\.id))
        let obsolete = delivered.filter { notification in
            if let requestID = notification.followUpID {
                return handledFollowUps.contains(requestID)
            }
            let registrationID = notification.identifier
            guard registrationID.hasPrefix(InitiativeNotificationScheduler.prefix)
            else { return false }
            guard let delivery = try? InitiativeConversationService.validatedDelivery(
                registrationID: registrationID,
                context: context
            ),
                let id = try? WaitingInitiativeStore.notificationOccurrenceID(
                    delivery: delivery,
                    deliveredAt: notification.date
                )
            else { return true }
            return !retained.contains(id)
        }
        scheduler.notifications.removeDelivered(obsolete.map(\.identifier))
        let pending = await scheduler.notifications.pending()
        let handledPending = pending.filter {
            guard let raw = $0.content.userInfo["initiativeRequestID"] as? String,
                  let id = UUID(uuidString: raw) else { return false }
            return handledFollowUps.contains(id)
        }
        scheduler.notifications.removePending(handledPending.map(\.identifier))
    }
}
