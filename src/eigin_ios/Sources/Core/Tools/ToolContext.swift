import Foundation

/// Per-invocation context for tool execution.
///
/// Services are resolved from Factory at point of use.
/// This struct carries only per-invocation context that varies between calls.
struct ToolContext {
    var voiceNames: [String] = []
    var accessPolicy: SpaceAccessPolicy = .init(currentSpaceID: nil, publicSpaceIDs: [])
    var spaceID: UUID?
    var chatID: UUID?
    var agentID: UUID?
    var canPromptUser: Bool = true
    var onBrowse: BrowseHandler?
    var onPresentOptions: OptionsHandler?
    var onConnectCapability: ConnectCapabilityHandler?
    var skillConnectionGate: SkillConnectionGate?
    var userMessageID: String?
}
