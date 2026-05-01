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

/// Incremental delta for a tool call arriving via streaming SSE chunks.
/// Each field is optional because chunks only carry partial data.
/// Some providers omit `index` or send complete tool calls instead of deltas.
struct ToolCallDelta: Decodable {
    let index: Int?
    let id: String?
    let type: String?
    let function: FunctionFragment?
    let extraContent: ExtraContent?

    struct FunctionFragment: Decodable {
        let name: String?
        let arguments: String?
    }

    /// Gemini-specific extra content that carries thinking metadata.
    struct ExtraContent: Decodable {
        let google: GoogleExtra?

        struct GoogleExtra: Decodable {
            let thoughtSignature: String?

            enum CodingKeys: String, CodingKey {
                case thoughtSignature = "thought_signature"
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case index, id, type, function
        case extraContent = "extra_content"
    }
}
