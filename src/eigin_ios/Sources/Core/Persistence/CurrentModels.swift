/// Type aliases mapping current model names to the active schema version.
///
/// All app code uses these unqualified names (e.g. `Agent`, `Chat`).
/// When a new schema version is introduced, update these aliases to point
/// to the new version and add a `MigrationStage` in the migration plan.
typealias Agent = SchemaV7.Agent
typealias AgentInitiativeRequest = SchemaV14.AgentInitiativeRequest
typealias AgentToolGrant = SchemaV1.AgentToolGrant
typealias CapabilityProviderSelection = SchemaV5.CapabilityProviderSelection
typealias Chat = SchemaV12.Chat
typealias ChatToolGrant = SchemaV1.ChatToolGrant
typealias FirmSource = SchemaV9.FirmSource
typealias InitiativeOccurrence = SchemaV11.InitiativeOccurrence
typealias InitiativeRegistration = SchemaV11.InitiativeRegistration
typealias Integration = SchemaV5.Integration
typealias Intent = SchemaV2.Intent
typealias IntentInitiative = SchemaV11.IntentInitiative
typealias MCPServer = SchemaV15.MCPServer
typealias Message = SchemaV12.Message
typealias Provider = SchemaV1.Provider
typealias Space = SchemaV1.Space

typealias InitiativeCursor = SchemaV13.InitiativeCursor
typealias WaitingInitiative = SchemaV13.WaitingInitiative
