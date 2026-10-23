import Foundation
import SwiftData

/// Persists permission overrides for one agent; absent rows inherit defaults.
@MainActor
struct ToolGrantStore {
    let context: ModelContext
    let agentID: UUID
    var save: (ModelContext) throws -> Void = { try $0.save() }

    func set(_ capability: ToolCapability, level: ToolPermissionLevel) throws {
        try update(capability, level: level == capability.defaultPermissionLevel ? nil : level)
    }

    /// A nil level removes the per-tool override and restores connection inheritance.
    func setDiscovered(toolName: String, level: ToolPermissionLevel?) throws {
        let capability = ToolCapability(
            kind: .discovered, key: toolName, displayName: toolName,
            defaultPermissionLevel: MCPToolProxy.defaultCapability.defaultPermissionLevel,
            category: .extensions
        )
        try update(capability, level: level)
    }

    private func update(_ capability: ToolCapability, level: ToolPermissionLevel?) throws {
        // Flush other edits before this synchronous write, so rollback only undoes this grant.
        try save(context)
        do {
            let id = agentID
            let key = capability.key
            let matches = try context.fetch(FetchDescriptor<AgentToolGrant>(
                predicate: #Predicate { $0.agentID == id && $0.key == key }
            )).filter { $0.kind == capability.kind }
            if let level {
                if let first = matches.first {
                    first.level = level
                    for duplicate in matches.dropFirst() {
                        context.delete(duplicate)
                    }
                } else {
                    context.insert(AgentToolGrant(
                        agentID: agentID,
                        capability: capability,
                        level: level
                    ))
                }
            } else {
                for row in matches {
                    context.delete(row)
                }
            }
            try save(context)
        } catch {
            context.rollback()
            throw error
        }
    }
}
