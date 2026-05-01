import Foundation

/// Lightweight info about a single tool call within a group.
struct ToolCallInfo: Identifiable, Equatable {
    let id: String
    let name: String
    let status: ToolEventStatus
    let arguments: String?
    let result: String?

    init(
        id: String,
        name: String,
        status: ToolEventStatus,
        arguments: String? = nil,
        result: String? = nil
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.arguments = arguments
        self.result = result
    }
}
