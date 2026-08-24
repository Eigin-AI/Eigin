import SwiftData

// MARK: - V1 Baseline

/// The current schema version. All live models are listed here.
/// Model definitions live in `SchemaV1/SchemaV1+<Model>.swift` extension files.
///
/// When a future breaking schema change is needed:
/// 1. Create a `SchemaV2` enum conforming to `VersionedSchema`.
/// 2. Add extension files in `SchemaV2/` for changed models.
/// 3. Create a `MigrationStage` (lightweight or custom) from V1 → V2.
/// 4. Create an `EiginMigrationPlan: SchemaMigrationPlan` with both versions and the stage.
/// 5. Pass `migrationPlan: EiginMigrationPlan.self` to `ModelContainer` in `EiginApp`.
enum SchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            Provider.self,
            Agent.self,
            Chat.self,
            Message.self,
            Space.self,
            AgentToolGrant.self,
            ChatToolGrant.self,
            MCPServer.self,
            FirmSource.self,
            Intent.self,
            AgentInitiativeRequest.self,
        ]
    }
    // Note: model list must exactly match the live @Model types in Sources/Models/Data/.
    // When adding a new model, add it here AND add a SchemaV1+<Model>.swift snapshot.
}

// MARK: - V2: Intents gain tasks/events/schedules, lose decay

/// Schema V2 reshapes `Intent`: the decay model (`reinforcedCount` and the
/// derived strength) is dropped, and intents gain `tasks`, `events`, and
/// `schedules`. Every other model is unchanged and reused from V1.
///
/// Model definitions that changed live in `SchemaV2/SchemaV2+<Model>.swift`.
enum SchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            SchemaV1.Provider.self,
            SchemaV1.Agent.self,
            SchemaV1.Chat.self,
            SchemaV1.Message.self,
            SchemaV1.Space.self,
            SchemaV1.AgentToolGrant.self,
            SchemaV1.ChatToolGrant.self,
            SchemaV1.MCPServer.self,
            SchemaV1.FirmSource.self,
            SchemaV2.Intent.self,
            SchemaV1.AgentInitiativeRequest.self,
        ]
    }
}

// MARK: - V3: Chat gains flow state

/// Schema V3 adds `activeFlow` to `Chat`, tracking progress through a
/// staged flow started via `start_flow`. Every other model is unchanged
/// and reused from V2.
///
/// Model definitions that changed live in `SchemaV3/SchemaV3+<Model>.swift`.
enum SchemaV3: VersionedSchema {
    static let versionIdentifier = Schema.Version(3, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            SchemaV1.Provider.self,
            SchemaV1.Agent.self,
            SchemaV3.Chat.self,
            SchemaV3.Message.self,
            SchemaV1.Space.self,
            SchemaV1.AgentToolGrant.self,
            SchemaV1.ChatToolGrant.self,
            SchemaV1.MCPServer.self,
            SchemaV1.FirmSource.self,
            SchemaV2.Intent.self,
            SchemaV1.AgentInitiativeRequest.self,
        ]
    }
}

// MARK: - V4: Message gains attachments

/// Schema V4 adds `attachmentsData` to `Message`, storing lightweight
/// references to images attached to a chat message. Every other model is
/// unchanged and reused from V3.
///
/// Model definitions that changed live in `SchemaV4/SchemaV4+<Model>.swift`.
enum SchemaV4: VersionedSchema {
    static let versionIdentifier = Schema.Version(4, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            SchemaV1.Provider.self,
            SchemaV1.Agent.self,
            SchemaV4.Chat.self,
            SchemaV4.Message.self,
            SchemaV1.Space.self,
            SchemaV1.AgentToolGrant.self,
            SchemaV1.ChatToolGrant.self,
            SchemaV1.MCPServer.self,
            SchemaV1.FirmSource.self,
            SchemaV2.Intent.self,
            SchemaV1.AgentInitiativeRequest.self,
        ]
    }
}

// MARK: - V5: Integrations

/// Schema V5 adds the `Integration` model, a connected instance of an
/// external service (e.g. a Google account) that provides capabilities to
/// skills, and the `CapabilityProviderSelection` model, which records which
/// connected integration is active for a capability when more than one
/// provides it. Every other model is unchanged and reused from V4.
///
/// Model definitions live in `SchemaV5/SchemaV5+Integration.swift` and
/// `SchemaV5/SchemaV5+CapabilityProviderSelection.swift`. The latter was
/// added after V5 shipped but before release, so it's folded into V5 in
/// place rather than introducing a V6 migration.
enum SchemaV5: VersionedSchema {
    static let versionIdentifier = Schema.Version(5, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            SchemaV1.Provider.self,
            SchemaV1.Agent.self,
            SchemaV4.Chat.self,
            SchemaV4.Message.self,
            SchemaV1.Space.self,
            SchemaV1.AgentToolGrant.self,
            SchemaV1.ChatToolGrant.self,
            SchemaV1.MCPServer.self,
            SchemaV1.FirmSource.self,
            SchemaV2.Intent.self,
            SchemaV1.AgentInitiativeRequest.self,
            SchemaV5.Integration.self,
            SchemaV5.CapabilityProviderSelection.self,
        ]
    }
}

// MARK: - V6: MCP server instructions

/// Schema V6 adds `serverInstructions` to `MCPServer`, caching the server's
/// self-reported `initialize` instructions so the skill-activation catalog can
/// render name + instructions + tools without a live connection. Every other
/// model is unchanged and reused from V5.
///
/// Model definitions that changed live in `SchemaV6/SchemaV6+MCPServer.swift`.
enum SchemaV6: VersionedSchema {
    static let versionIdentifier = Schema.Version(6, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            SchemaV1.Provider.self,
            SchemaV1.Agent.self,
            SchemaV4.Chat.self,
            SchemaV4.Message.self,
            SchemaV1.Space.self,
            SchemaV1.AgentToolGrant.self,
            SchemaV1.ChatToolGrant.self,
            SchemaV6.MCPServer.self,
            SchemaV1.FirmSource.self,
            SchemaV2.Intent.self,
            SchemaV1.AgentInitiativeRequest.self,
            SchemaV5.Integration.self,
            SchemaV5.CapabilityProviderSelection.self,
        ]
    }
}

// MARK: - V7: Agent gains automatic model selection

/// Schema V7 adds `autoModel` to `Agent`, recording whether the model is chosen by
/// ``ModelRouter`` or pinned by the user. Every other model is unchanged and reused
/// from V6.
///
/// Model definitions that changed live in `SchemaV7/SchemaV7+Agent.swift`.
enum SchemaV7: VersionedSchema {
    static let versionIdentifier = Schema.Version(7, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            SchemaV1.Provider.self,
            SchemaV7.Agent.self,
            SchemaV4.Chat.self,
            SchemaV4.Message.self,
            SchemaV1.Space.self,
            SchemaV1.AgentToolGrant.self,
            SchemaV1.ChatToolGrant.self,
            SchemaV6.MCPServer.self,
            SchemaV1.FirmSource.self,
            SchemaV2.Intent.self,
            SchemaV1.AgentInitiativeRequest.self,
            SchemaV5.Integration.self,
            SchemaV5.CapabilityProviderSelection.self,
        ]
    }
}

// MARK: - V8: FirmSource gains memory signals

/// Schema V8 turns `FirmSource` from a static store into a memory record: it
/// gains `accessCount` and `lastAccessedAt` (use signals), `importance` (a
/// safety net for rare-but-critical facts), and `expired` (soft-hidden state).
/// Every other model is unchanged and reused from V7.
///
/// Model definitions that changed live in `SchemaV8/SchemaV8+FirmSource.swift`.
enum SchemaV8: VersionedSchema {
    static let versionIdentifier = Schema.Version(8, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            SchemaV1.Provider.self,
            SchemaV7.Agent.self,
            SchemaV4.Chat.self,
            SchemaV4.Message.self,
            SchemaV1.Space.self,
            SchemaV1.AgentToolGrant.self,
            SchemaV1.ChatToolGrant.self,
            SchemaV6.MCPServer.self,
            SchemaV8.FirmSource.self,
            SchemaV2.Intent.self,
            SchemaV1.AgentInitiativeRequest.self,
            SchemaV5.Integration.self,
            SchemaV5.CapabilityProviderSelection.self,
        ]
    }
}

// MARK: - V9: FirmSource gains a consolidation-review stamp

/// Schema V9 adds `lastReviewedAt` to `FirmSource`, letting background
/// consolidation rotate through the base least-recently-reviewed first. Every
/// other model is unchanged and reused from V8.
///
/// Model definitions that changed live in `SchemaV9/SchemaV9+FirmSource.swift`.
enum SchemaV9: VersionedSchema {
    static let versionIdentifier = Schema.Version(9, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            SchemaV1.Provider.self,
            SchemaV7.Agent.self,
            SchemaV4.Chat.self,
            SchemaV4.Message.self,
            SchemaV1.Space.self,
            SchemaV1.AgentToolGrant.self,
            SchemaV1.ChatToolGrant.self,
            SchemaV6.MCPServer.self,
            SchemaV9.FirmSource.self,
            SchemaV2.Intent.self,
            SchemaV1.AgentInitiativeRequest.self,
            SchemaV5.Integration.self,
            SchemaV5.CapabilityProviderSelection.self,
        ]
    }
}

/// Migration plan for the on-device store.
///
/// V1 → V2 is a lightweight stage: adding the new `Intent` collections (each
/// defaulting to empty) and dropping `reinforcedCount` are both changes
/// SwiftData can infer automatically. No data is lost — existing intents keep
/// their content, status, and timestamps.
///
/// V2 → V3 is a lightweight stage: adding `activeFlow` (defaulting to `nil`)
/// to `Chat`. No data is lost.
///
/// V3 → V4 is a lightweight stage: adding `attachmentsData` (defaulting to
/// `nil`) to `Message`. No data is lost.
///
/// V4 → V5 is a lightweight stage: adding the new `Integration` model. No
/// existing data is touched.
///
/// V5 → V6 is a lightweight stage: adding `serverInstructions` (defaulting to
/// `nil`) to `MCPServer`. No existing data is touched.
///
/// V6 → V7 is a lightweight stage: adding `autoModel` (defaulting to `true`) to
/// `Agent`. Existing agents opt into automatic model selection starting from the
/// model they already have, so nothing changes until a model actually misbehaves.
///
/// V7 → V8 is a custom stage: adding `accessCount`, `lastAccessedAt`,
/// `importance` (0.5), and `expired` (false) to `FirmSource`. Existing memories
/// are seeded as if touched once at upgrade time (`accessCount = 1`,
/// `lastAccessedAt = now`) — a "migration-as-access" grace period. This mirrors
/// creation-as-access for new memories, keeps ranking relevance-ordered (a
/// uniform floor), and, crucially, stops pre-existing knowledge from looking
/// ancient-and-unused the day eviction ships. Disuse from upgrade forward is
/// what drives forgetting, not age that predates the feature.
///
/// V8 → V9 is a lightweight stage: adding `lastReviewedAt` (defaulting to `nil`)
/// to `FirmSource`. No existing data is touched.
enum EiginMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [
            SchemaV1.self, SchemaV2.self, SchemaV3.self, SchemaV4.self, SchemaV5.self,
            SchemaV6.self, SchemaV7.self, SchemaV8.self, SchemaV9.self,
        ]
    }

    static var stages: [MigrationStage] {
        [
            migrateV1toV2, migrateV2toV3, migrateV3toV4, migrateV4toV5, migrateV5toV6,
            migrateV6toV7, migrateV7toV8, migrateV8toV9,
        ]
    }

    static let migrateV1toV2 = MigrationStage.lightweight(
        fromVersion: SchemaV1.self,
        toVersion: SchemaV2.self
    )

    static let migrateV2toV3 = MigrationStage.lightweight(
        fromVersion: SchemaV2.self,
        toVersion: SchemaV3.self
    )

    static let migrateV3toV4 = MigrationStage.lightweight(
        fromVersion: SchemaV3.self,
        toVersion: SchemaV4.self
    )

    static let migrateV4toV5 = MigrationStage.lightweight(
        fromVersion: SchemaV4.self,
        toVersion: SchemaV5.self
    )

    static let migrateV5toV6 = MigrationStage.lightweight(
        fromVersion: SchemaV5.self,
        toVersion: SchemaV6.self
    )

    static let migrateV6toV7 = MigrationStage.lightweight(
        fromVersion: SchemaV6.self,
        toVersion: SchemaV7.self
    )

    static let migrateV7toV8 = MigrationStage.custom(
        fromVersion: SchemaV7.self,
        toVersion: SchemaV8.self,
        willMigrate: nil,
        didMigrate: { context in
            // Seed existing entries as touched once at upgrade time, so later
            // eviction sweeps don't mistake them for ancient-and-unused.
            let now = Date()
            let sources = try context.fetch(FetchDescriptor<SchemaV8.FirmSource>())
            for source in sources {
                source.accessCount = 1
                source.lastAccessedAt = now
            }
            try context.save()
        }
    )

    static let migrateV8toV9 = MigrationStage.lightweight(
        fromVersion: SchemaV8.self,
        toVersion: SchemaV9.self
    )
}
