/// Type aliases mapping current model names to the active schema version.
///
/// All app code uses these unqualified names (e.g. `Agent`, `Chat`).
/// When a new schema version is introduced, update these aliases to point
/// to the new version and add a `MigrationStage` in the migration plan.
typealias Agent = SchemaV7.Agent
typealias AgentInitiativeRequest = SchemaV1.AgentInitiativeRequest
typealias AgentToolGrant = SchemaV1.AgentToolGrant
typealias CapabilityProviderSelection = SchemaV5.CapabilityProviderSelection
typealias Chat = SchemaV4.Chat
typealias ChatToolGrant = SchemaV1.ChatToolGrant
typealias FirmSource = SchemaV1.FirmSource
typealias Integration = SchemaV5.Integration
typealias Intent = SchemaV2.Intent
typealias MCPServer = SchemaV6.MCPServer
typealias Message = SchemaV4.Message
typealias Provider = SchemaV1.Provider
typealias Space = SchemaV1.Space
