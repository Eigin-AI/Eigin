import EiginSDK
import Foundation

/// Maps SDK output provenance to stable app identities; Rust owns ordering and retention.
struct TurnOutputSDKConversion {
    typealias SDK = EiginSDK.Experimental.Agent
    private let sdk = SDK.Output()
    private let identityPrefix = UUID().uuidString
    private var draftIDs: [UInt64: String] = [:]

    var messages: [ChatMessage] {
        sdk.output().map(message)
    }

    var committedMessages: [ChatMessage] {
        sdk.retainedOutput().map(message)
    }

    mutating func beginDraft(localID: String) throws {
        try draftIDs[sdk.beginDraft()] = localID
    }

    mutating func updateDraft(_ content: String) throws {
        try sdk.updateDraft(content: content)
    }

    mutating func beginTools() throws {
        try sdk.beginTools()
    }

    mutating func recordBatch(
        _ value: EiginSDK.Experimental.Conversation.Message
    ) throws -> ChatMessage {
        try message(sdk.recordBatch(message: value))
    }

    mutating func recordResult(
        _ value: EiginSDK.Experimental.Conversation.Message
    ) throws -> ChatMessage {
        try message(sdk.recordResult(message: value))
    }

    mutating func recordInlineExchange(
        _ values: [EiginSDK.Experimental.Conversation.Message]
    ) throws -> [ChatMessage] {
        try sdk.recordInlineExchange(messages: values).map(message)
    }

    mutating func retainInterruptedProse() throws -> ChatMessage? {
        try sdk.retainInterruptedProse().map(message)
    }

    mutating func finish(_ value: EiginSDK.Experimental.Conversation.Message?) throws {
        try sdk.finish(message: value)
    }

    func checkpoint() -> [ChatMessage] {
        sdk.checkpoint().map(message)
    }

    private func message(_ entry: SDK.OutputEntry) -> ChatMessage {
        let localID: String = switch entry.origin {
        case .recorded(let id):
            draftIDs[id] ?? "\(identityPrefix)-output-\(id)"
        case .interruptedTool(let index):
            "\(identityPrefix)-interrupted-\(index)"
        }
        return RoundSDKConversion.message(entry.message, localID: localID)
    }
}
