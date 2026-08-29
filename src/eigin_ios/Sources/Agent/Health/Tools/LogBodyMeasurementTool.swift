import Foundation

struct LogBodyMeasurementTool: Tool {
    static let capability = ToolCapability(
        kind: .builtIn, key: "log_body_measurement",
        displayName: Localized.Tools.Log.bodyMeasurement,
        defaultPermissionLevel: .ask, category: .health
    )

    let name = "log_body_measurement"
    var isSmallContext: Bool = false
    let healthService: (any HealthService)?
    let canPromptUser: Bool
    var displayName: String {
        Self.capability.displayName
    }

    var capabilities: [ToolCapability] {
        [Self.capability]
    }

    var category: ToolCapability.Category {
        .health
    }

    var defaultPermissionLevel: ToolPermissionLevel {
        .ask
    }

    func definition() -> ToolDefinition {
        ToolDefinition(
            name: name,
            description: "Log a body measurement to Apple Health.",
            parameters: JSONSchema(
                type: "object",
                properties: [
                    "weight_kg": .init(
                        type: "number",
                        description: "Body weight in kilograms."
                    ),
                    "date": .init(
                        type: "string",
                        description:
                        "Date/time to log (e.g. \"2026-04-12 08:00\"). Defaults to now."
                    ),
                ],
                required: ["weight_kg"]
            )
        )
    }

    func disclosure(for toolCall: ToolCall) -> ToolDisclosure? {
        guard let args = ToolHelpers.parseArguments(toolCall.function.arguments),
              let weight = args["weight_kg"] as? Double
        else { return nil }
        return ToolDisclosure(
            actionPhrase: Localized.Permission.Disclosure.logBodyMeasurement,
            detail: .inline("\(weight.formatted()) kg")
        )
    }

    @MainActor func execute(_ toolCall: ToolCall, agent: Agent) async -> ToolResult {
        let id = toolCall.id

        guard let service = healthService else {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: ["Health service unavailable."]), isError: true
            )
        }

        let auth = await service.authorize(canPromptUser: canPromptUser)
        if case .denied(let reason) = auth {
            return ToolResult(
                toolCallID: id, content: ToolHelpers.output(errors: [reason]), isError: true
            )
        }

        guard let args = ToolHelpers.parseArguments(toolCall.function.arguments) else {
            return ToolResult(
                toolCallID: id, content: ToolHelpers.output(errors: ["Invalid JSON arguments."]),
                isError: true
            )
        }

        guard let weight = args["weight_kg"] as? Double else {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: ["Missing 'weight_kg' (number)."]),
                isError: true
            )
        }

        let date: Date = if let dateString = args["date"] as? String,
                            let parsed = LocalDateFormatter.parse(dateString)
        {
            parsed
        } else {
            Date()
        }

        do {
            try await service.logWeight(weight, date: date)

            let result: [String: Any] = [
                "logged": true,
                "weight_kg": weight,
                "date": LocalDateFormatter.string(from: date),
            ]

            return ToolResult(
                toolCallID: id, content: ToolHelpers.output(result: result), isError: false
            )
        } catch {
            return ToolResult(
                toolCallID: id, content: ToolHelpers.output(errors: [error.localizedDescription]),
                isError: true
            )
        }
    }
}
