import Foundation
import SwiftData

/// Sendable value type for passing intent data across isolation boundaries.
struct IntentSnapshot: Sendable {
    let id: UUID
    let content: String
    let status: IntentStatus
    let tasks: [IntentTask]
    let events: [IntentEvent]
    let schedules: [IntentSchedule]
    let createdAt: Date
    let updatedAt: Date

    /// Blended temporal relevance, used for ordering (see ``IntentRelevance``).
    var relevance: Double {
        IntentRelevance.relevance(for: self)
    }
}

extension Intent {
    /// A `Sendable` snapshot of this persisted intent.
    var snapshot: IntentSnapshot {
        IntentSnapshot(
            id: id,
            content: content,
            status: intentStatus,
            tasks: tasks,
            events: events,
            schedules: schedules,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

/// Manages agent intents — self-set goals that guide behavior across conversations.
///
/// Intents persist until explicitly resolved or dismissed; there is no decay.
protocol IntentService: Sendable {
    func activeIntents(agentID: UUID, limit: Int, accessPolicy: SpaceAccessPolicy) async throws
        -> [IntentSnapshot]
    func allIntents(agentID: UUID, limit: Int, accessPolicy: SpaceAccessPolicy) async throws
        -> [IntentSnapshot]
    func create(
        content: String,
        agentID: UUID,
        spaceID: UUID?,
        chatID: UUID?,
        tasks: [IntentTask],
        events: [IntentEvent],
        schedules: [IntentSchedule]
    ) async throws -> UUID
    /// Updates an intent in place. Non-nil collections fully replace the
    /// existing ones; nil leaves a field untouched. Touches `updatedAt`.
    func update(
        id: UUID,
        content: String?,
        tasks: [IntentTask]?,
        events: [IntentEvent]?,
        schedules: [IntentSchedule]?
    ) async throws
    func resolve(id: UUID) async throws
    func dismiss(id: UUID) async throws
}

/// Default implementation backed by SwiftData.
final class DefaultIntentService: IntentService, @unchecked Sendable {
    private let modelContainer: ModelContainer

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    func activeIntents(
        agentID: UUID,
        limit: Int = 5,
        accessPolicy: SpaceAccessPolicy = SpaceAccessPolicy(currentSpaceID: nil, publicSpaceIDs: [])
    ) async throws -> [IntentSnapshot] {
        let context = ModelContext(modelContainer)
        let activeStatus = IntentStatus.active.rawValue
        let descriptor = FetchDescriptor<Intent>(
            predicate: #Predicate { $0.agentID == agentID && $0.status == activeStatus }
        )
        return try context.fetch(descriptor)
            .filter { accessPolicy.canAccess(itemSpaceID: $0.spaceID) }
            .map(\.snapshot)
            .sorted { $0.relevance > $1.relevance }
            .prefix(limit)
            .map(\.self)
    }

    func allIntents(
        agentID: UUID,
        limit: Int = 20,
        accessPolicy: SpaceAccessPolicy = SpaceAccessPolicy(currentSpaceID: nil, publicSpaceIDs: [])
    ) async throws -> [IntentSnapshot] {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<Intent>(
            predicate: #Predicate { $0.agentID == agentID },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
            .filter { accessPolicy.canAccess(itemSpaceID: $0.spaceID) }
            .prefix(limit)
            .map(\.snapshot)
    }

    func create(
        content: String,
        agentID: UUID,
        spaceID: UUID?,
        chatID: UUID?,
        tasks: [IntentTask] = [],
        events: [IntentEvent] = [],
        schedules: [IntentSchedule] = []
    ) async throws -> UUID {
        let context = ModelContext(modelContainer)
        let intent = Intent(
            agentID: agentID,
            content: content,
            spaceID: spaceID,
            chatID: chatID,
            tasks: tasks,
            events: events,
            schedules: schedules
        )
        context.insert(intent)
        try context.save()
        return intent.id
    }

    func update(
        id: UUID,
        content: String?,
        tasks: [IntentTask]?,
        events: [IntentEvent]?,
        schedules: [IntentSchedule]?
    ) async throws {
        let context = ModelContext(modelContainer)
        guard let intent = try fetch(id: id, in: context) else {
            throw IntentServiceError.notFound(id: id)
        }
        if let content { intent.content = content }
        if let tasks { intent.tasks = tasks }
        if let events { intent.events = events }
        if let schedules { intent.schedules = schedules }
        intent.updatedAt = .now
        try context.save()
    }

    func resolve(id: UUID) async throws {
        try await setStatus(.resolved, for: id)
    }

    func dismiss(id: UUID) async throws {
        try await setStatus(.dismissed, for: id)
    }

    private func setStatus(_ status: IntentStatus, for id: UUID) async throws {
        let context = ModelContext(modelContainer)
        guard let intent = try fetch(id: id, in: context) else {
            throw IntentServiceError.notFound(id: id)
        }
        intent.intentStatus = status
        try context.save()
    }

    private func fetch(id: UUID, in context: ModelContext) throws -> Intent? {
        try context.fetch(FetchDescriptor<Intent>(predicate: #Predicate { $0.id == id })).first
    }
}

enum IntentServiceError: LocalizedError {
    case notFound(id: UUID)

    var errorDescription: String? {
        switch self {
        case .notFound(let id):
            "Intent not found: \(id.uuidString)"
        }
    }
}

/// No-op implementation used as the environment default and for previews.
struct PreviewIntentService: IntentService {
    func activeIntents(
        agentID: UUID,
        limit: Int,
        accessPolicy: SpaceAccessPolicy
    ) async throws -> [IntentSnapshot] {
        []
    }

    func allIntents(
        agentID: UUID,
        limit: Int,
        accessPolicy: SpaceAccessPolicy
    ) async throws -> [IntentSnapshot] {
        []
    }

    func create(
        content: String,
        agentID: UUID,
        spaceID: UUID?,
        chatID: UUID?,
        tasks: [IntentTask],
        events: [IntentEvent],
        schedules: [IntentSchedule]
    ) async throws -> UUID {
        UUID()
    }

    func update(
        id: UUID,
        content: String?,
        tasks: [IntentTask]?,
        events: [IntentEvent]?,
        schedules: [IntentSchedule]?
    ) async throws {}
    func resolve(id: UUID) async throws {}
    func dismiss(id: UUID) async throws {}
}
