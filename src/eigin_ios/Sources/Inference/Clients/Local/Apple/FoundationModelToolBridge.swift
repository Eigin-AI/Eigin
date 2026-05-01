import FoundationModels

final class CapturedToolCalls: @unchecked Sendable {
    private var calls: [ToolCall] = []
    private let lock = NSLock()

    func append(name: String, arguments: String) {
        lock.lock()
        defer { lock.unlock() }
        calls.append(ToolCall(
            id: "call_\(UUID().uuidString.prefix(8))",
            type: "function",
            function: ToolCall.FunctionCall(name: name, arguments: arguments)
        ))
    }

    func drain() -> [ToolCall] {
        lock.lock()
        defer { lock.unlock() }
        let result = calls
        calls = []
        return result
    }
}

struct BridgedToolInterrupt: Error {}

struct BridgedTool: @unchecked Sendable, FoundationModels.Tool {
    let name: String
    let description: String
    let parameters: GenerationSchema
    let capture: CapturedToolCalls

    init(from definition: ToolDefinition, capture: CapturedToolCalls) {
        name = definition.function.name
        description = definition.function.description
        parameters = Self.convertSchema(definition.function.parameters)
        self.capture = capture
    }

    func call(arguments: GeneratedContent) async throws -> String {
        capture.append(name: name, arguments: arguments.jsonString)
        throw BridgedToolInterrupt()
    }

    private static func convertSchema(_ schema: JSONSchema) -> GenerationSchema {
        let requiredNames = Set(schema.required ?? [])
        var properties: [GenerationSchema.Property] = []

        if let props = schema.properties {
            for (name, prop) in props.sorted(by: { $0.key < $1.key }) {
                let isRequired = requiredNames.contains(name)
                properties.append(convertProperty(name: name, prop: prop, required: isRequired))
            }
        }

        return GenerationSchema(type: GeneratedContent.self, properties: properties)
    }

    private static func convertProperty(
        name: String, prop: JSONSchema.Property, required: Bool
    ) -> GenerationSchema.Property {
        switch prop.type {
        case "string":
            required
                ? .init(name: name, description: prop.description, type: String.self)
                : .init(name: name, description: prop.description, type: String?.self)
        case "integer":
            required
                ? .init(name: name, description: prop.description, type: Int.self)
                : .init(name: name, description: prop.description, type: Int?.self)
        case "number":
            required
                ? .init(name: name, description: prop.description, type: Double.self)
                : .init(name: name, description: prop.description, type: Double?.self)
        case "boolean":
            required
                ? .init(name: name, description: prop.description, type: Bool.self)
                : .init(name: name, description: prop.description, type: Bool?.self)
        default:
            required
                ? .init(name: name, description: prop.description, type: String.self)
                : .init(name: name, description: prop.description, type: String?.self)
        }
    }
}
