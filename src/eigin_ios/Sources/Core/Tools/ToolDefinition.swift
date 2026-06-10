import Foundation

/// Wire format for a tool definition in the OpenAI-compatible `tools` array.
struct ToolDefinition: Encodable, Sendable {
    let type: String
    let function: FunctionDefinition

    init(name: String, description: String, parameters: JSONSchema) {
        type = "function"
        function = FunctionDefinition(name: name, description: description, parameters: parameters)
    }

    struct FunctionDefinition: Encodable, Sendable {
        let name: String
        let description: String
        let parameters: JSONSchema
    }
}

/// Minimal JSON Schema representation for encoding tool parameter schemas.
/// OpenAI requires `properties` to be present when type is "object",
/// so we default to an empty dictionary.
struct JSONSchema: Encodable, Sendable {
    let type: String
    var properties: [String: Property]?
    var required: [String]?

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        // OpenAI rejects object schemas without properties
        try container.encode(properties ?? [:], forKey: .properties)
        try container.encodeIfPresent(required, forKey: .required)
    }

    enum CodingKeys: String, CodingKey {
        case type, properties, required
    }

    struct Property: Encodable, Sendable {
        let type: String
        var description: String
        var `enum`: [String]?
        /// Item schema for array-typed properties.
        var items: Items?

        enum CodingKeys: String, CodingKey {
            case type, description, items
            case `enum`
        }

        struct Items: Encodable, Sendable {
            let type: String
            var properties: [String: Property]?
            var required: [String]?

            enum CodingKeys: String, CodingKey {
                case type, properties, required
            }
        }
    }
}
