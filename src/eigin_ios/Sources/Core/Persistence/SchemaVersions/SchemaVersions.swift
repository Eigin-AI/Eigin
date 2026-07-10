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
enum EiginMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self, SchemaV3.self, SchemaV4.self, SchemaV5.self]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2, migrateV2toV3, migrateV3toV4, migrateV4toV5]
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
}
