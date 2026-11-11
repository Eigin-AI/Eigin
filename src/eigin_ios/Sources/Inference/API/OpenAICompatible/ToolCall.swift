import Foundation

/// A tool invocation requested by the model in an assistant message.
struct ToolCall: Codable, Equatable {
    let id: String
    let type: String
    let function: FunctionCall

    struct FunctionCall: Codable, Equatable {
        let name: String
        let arguments: String
    }
}
