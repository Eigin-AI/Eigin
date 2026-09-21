import Foundation
import MCP

/// Bridges a remote MCP tool to the app's ``Tool`` protocol.
///
/// The chat loop and permission system see this as a regular tool.
/// Execution proxies through the ``MCPServerConnection`` actor.
struct MCPToolProxy: Tool {
    /// Built-in fallback capability for all MCP tools.
    static let defaultCapability = ToolCapability(
        kind: .builtIn, key: "mcp_server",
        displayName: Localized.Ui.useMcpServers,
        defaultPermissionLevel: .ask, category: .extensions
    )

    let name: String
    let displayName: String

    var capabilities: [ToolCapability] {
        [ToolCapability(
            kind: .discovered, key: name,
            displayName: displayName,
            defaultPermissionLevel: Self.defaultCapability.defaultPermissionLevel,
            category: .extensions
        )]
    }

    var category: ToolCapability.Category {
        .extensions
    }

    var defaultPermissionLevel: ToolPermissionLevel {
        .ask
    }

    /// Maximum characters returned from an MCP tool call.
    /// Matches ``HTMLSanitizer/maxOutputLength`` used by web tools.
    static let maxOutputLength = 20000

    private let mcpTool: MCP.Tool
    private let connection: MCPServerConnection

    init(mcpTool: MCP.Tool, serverName: String, connection: MCPServerConnection) {
        // Namespace to avoid collisions: "mcp__<server>__<tool>"
        name = MCPNaming.toolName(serverName: serverName, toolName: mcpTool.name)
        let toolLabel = mcpTool.title ?? mcpTool.name.titleCased
        displayName = "\(serverName): \(toolLabel)"
        self.mcpTool = mcpTool
        self.connection = connection
    }

    func definition() -> ToolDefinition {
        ToolDefinition(
            name: name,
            description: mcpTool.description ?? "MCP tool: \(mcpTool.name)",
            parameters: convertSchema(mcpTool.inputSchema)
        )
    }

    @MainActor func execute(_ toolCall: ToolCall, agent: Agent) async -> ToolResult {
        let id = toolCall.id

        let mcpArguments = Self.decodeArguments(toolCall.function.arguments)

        do {
            let (content, isError) = try await connection.callTool(
                name: mcpTool.name,
                arguments: mcpArguments
            )

            var resultText = content.map { contentToString($0) }.joined(separator: "\n")

            if isError == true {
                return ToolResult(
                    toolCallID: id,
                    content: ToolHelpers.output(errors: [resultText]),
                    isError: true
                )
            }

            var warnings: [String]?
            if resultText.count > Self.maxOutputLength {
                let originalLength = resultText.count
                resultText = String(resultText.prefix(Self.maxOutputLength))
                warnings =
                    [
                        "Output truncated from \(originalLength) to \(Self.maxOutputLength) characters.",
                    ]
            }

            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(result: ["output": resultText], warnings: warnings),
                isError: false
            )
        } catch {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: [error.localizedDescription]),
                isError: true
            )
        }
    }

    // MARK: - Schema Conversion

    /// Converts the MCP tool's `Value`-based input schema into the app's `JSONSchema`.
    private func convertSchema(_ schema: Value) -> JSONSchema {
        guard case .object(let obj) = schema else {
            return JSONSchema(type: "object")
        }

        var properties: [String: JSONSchema.Property] = [:]
        var required: [String] = []

        if case .object(let props) = obj["properties"] {
            for (key, value) in props {
                properties[key] = convertProperty(value)
            }
        }

        if case .array(let req) = obj["required"] {
            required = req.compactMap { value -> String? in
                if case .string(let s) = value { return s }
                return nil
            }
        }

        return JSONSchema(
            type: "object",
            properties: properties.isEmpty ? nil : properties,
            required: required.isEmpty ? nil : required
        )
    }

    /// Converts a single MCP schema property value into a `JSONSchema.Property`.
    private func convertProperty(_ value: Value) -> JSONSchema.Property {
        guard case .object(let obj) = value else {
            return JSONSchema.Property(type: "string", description: "No description provided.")
        }

        let type: String = if case .string(let t) = obj["type"] {
            t
        } else {
            "string"
        }

        let description: String = if case .string(let d) = obj["description"], !d.isEmpty {
            d
        } else {
            "No description provided."
        }

        var enumValues: [String]?
        if case .array(let arr) = obj["enum"] {
            enumValues = arr.compactMap { value -> String? in
                if case .string(let s) = value { return s }
                return nil
            }
        }

        // GPT requires `items` on array-typed properties.
        var items: JSONSchema.Property.Items?
        if type == "array" {
            if case .object(let itemsObj) = obj["items"],
               case .string(let itemType) = itemsObj["type"]
            {
                items = JSONSchema.Property.Items(type: itemType)
            } else {
                items = JSONSchema.Property.Items(type: "string")
            }
        }

        return JSONSchema.Property(
            type: type,
            description: description,
            enum: enumValues,
            items: items
        )
    }

    // MARK: - Arguments

    /// Decodes a tool call's JSON arguments string into MCP `Value` arguments.
    ///
    /// Decodes to `Value` directly — `JSONSerialization`'s `NSNumber` boxing
    /// can't distinguish `true` from `1`.
    static func decodeArguments(_ json: String) -> [String: Value]? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([String: Value].self, from: data)
    }

    /// Converts MCP tool content to a plain string.
    private func contentToString(_ content: MCP.Tool.Content) -> String {
        switch content {
        case .text(let text):
            text
        case .image(data: let data, mimeType: let mimeType, metadata: _):
            "[Image: \(mimeType), \(data.count) chars base64]"
        case .resource(resource: let resource, annotations: _, _meta: _):
            "[Resource: \(resource)]"
        case .audio(data: let data, mimeType: let mimeType):
            "[Audio: \(mimeType), \(data.count) chars base64]"
        case .resourceLink(
            uri: let uri,
            name: let name,
            title: _,
            description: _,
            mimeType: _,
            annotations: _
        ):
            "[Resource link: \(name) (\(uri))]"
        }
    }
}
