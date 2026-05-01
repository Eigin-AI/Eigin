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
