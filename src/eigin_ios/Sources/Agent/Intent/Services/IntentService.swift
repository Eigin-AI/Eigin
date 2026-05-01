import Foundation
import SwiftData

/// Sendable value type for passing intent data across isolation boundaries.
struct IntentSnapshot {
    let id: UUID
    let content: String
    let status: IntentStatus
    let effectiveStrength: Double
    let reinforcedCount: Int
    let createdAt: Date
    let updatedAt: Date
}

/// Manages agent intents — self-set goals that guide behavior across conversations.
protocol IntentService: Sendable {
    func activeIntents(agentID: UUID, limit: Int, accessPolicy: SpaceAccessPolicy) async throws
        -> [IntentSnapshot]
    func allIntents(agentID: UUID, limit: Int, accessPolicy: SpaceAccessPolicy) async throws
        -> [IntentSnapshot]
    func create(content: String, agentID: UUID, spaceID: UUID?, chatID: UUID?) async throws -> UUID
    func reinforce(id: UUID) async throws
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
            predicate: #Predicate { $0.agentID == agentID && $0.status == activeStatus },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        let intents = try context.fetch(descriptor)
        return intents
            .filter { accessPolicy.canAccess(itemSpaceID: $0.spaceID) }
            .map { intent in
                IntentSnapshot(
                    id: intent.id,
                    content: intent.content,
                    status: intent.intentStatus,
                    effectiveStrength: intent.effectiveStrength,
                    reinforcedCount: intent.reinforcedCount,
                    createdAt: intent.createdAt,
                    updatedAt: intent.updatedAt
                )
            }
            .filter { $0.effectiveStrength > IntentDecay.activeThreshold }
            .sorted { $0.effectiveStrength > $1.effectiveStrength }
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
        let intents = try context.fetch(descriptor)
        return intents
            .filter { accessPolicy.canAccess(itemSpaceID: $0.spaceID) }
            .prefix(limit)
            .map { intent in
                IntentSnapshot(
                    id: intent.id,
                    content: intent.content,
                    status: intent.intentStatus,
                    effectiveStrength: intent.effectiveStrength,
                    reinforcedCount: intent.reinforcedCount,
                    createdAt: intent.createdAt,
                    updatedAt: intent.updatedAt
                )
            }
    }

    func create(
        content: String,
        agentID: UUID,
        spaceID: UUID?,
        chatID: UUID?
    ) async throws -> UUID {
        let context = ModelContext(modelContainer)
        let intent = Intent(agentID: agentID, content: content, spaceID: spaceID, chatID: chatID)
        context.insert(intent)
        try context.save()
        return intent.id
    }

    func reinforce(id: UUID) async throws {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<Intent>(
            predicate: #Predicate { $0.id == id }
        )
        guard let intent = try context.fetch(descriptor).first else {
            throw IntentServiceError.notFound(id: id)
        }
        intent.reinforcedCount += 1
        intent.updatedAt = .now
        try context.save()
    }

    func resolve(id: UUID) async throws {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<Intent>(
            predicate: #Predicate { $0.id == id }
        )
        guard let intent = try context.fetch(descriptor).first else {
            throw IntentServiceError.notFound(id: id)
        }
        intent.intentStatus = .resolved
        try context.save()
    }

    func dismiss(id: UUID) async throws {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<Intent>(
            predicate: #Predicate { $0.id == id }
        )
        guard let intent = try context.fetch(descriptor).first else {
            throw IntentServiceError.notFound(id: id)
        }
        intent.intentStatus = .dismissed
        try context.save()
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
        chatID: UUID?
    ) async throws -> UUID {
        UUID()
    }

    func reinforce(id: UUID) async throws {}
    func resolve(id: UUID) async throws {}
    func dismiss(id: UUID) async throws {}
}
