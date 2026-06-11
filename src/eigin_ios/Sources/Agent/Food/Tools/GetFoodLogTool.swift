import Foundation

struct GetFoodLogTool: Tool {
    static let capability = ToolCapability(
        kind: .builtIn, key: "get_food_log",
        displayName: Localized.Tools.Get.Food.log,
        defaultPermissionLevel: .ask, category: .system
    )

    let name = "get_food_log"
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
        .system
    }

    var defaultPermissionLevel: ToolPermissionLevel {
        .ask
    }

    private static let validFields: Set<String> = [
        "weight", "calories_consumed", "active_calories",
        "resting_calories", "dietary_entries",
    ]

    func definition() -> ToolDefinition {
        ToolDefinition(
            name: name,
            description: "Read food and nutrition data from Apple Health. Only request the specific data points you need.",
            parameters: JSONSchema(
                type: "object",
                properties: [
                    "include": .init(
                        type: "array",
                        description: "Data points to return: \"weight\", \"calories_consumed\", \"active_calories\", \"resting_calories\", \"dietary_entries\".",
                        items: .init(type: "string")
                    ),
                    "date": .init(
                        type: "string",
                        description: "Date to query (e.g. \"2026-04-12\"). Defaults to today."
                    ),
                ],
                required: ["include"]
            )
        )
    }

    @MainActor func execute(_ toolCall: ToolCall, agent: Agent) async -> ToolResult {
        let id = toolCall.id

        guard let service = healthService else {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: ["Health service unavailable."]),
                isError: true
            )
        }

        let auth = await service.authorize(canPromptUser: canPromptUser)
        if case .denied(let reason) = auth {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: [reason]),
                isError: true
            )
        }

        guard let args = ToolHelpers.parseArguments(toolCall.function.arguments) else {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: ["Invalid JSON arguments."]),
                isError: true
            )
        }

        guard let includeArray = args["include"] as? [String], !includeArray.isEmpty else {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: ["Missing or empty 'include' array."]),
                isError: true
            )
        }

        let fields = Set(includeArray).intersection(Self.validFields)
        if fields.isEmpty {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers
                    .output(
                        errors: [
                            "No valid fields in 'include'. Valid: \(Self.validFields.sorted().joined(separator: ", "))",
                        ]
                    ),
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

        var result: [String: Any] = [
            "date": LocalDateFormatter.string(from: date),
        ]
        var warnings: [String] = []

        do {
            if fields.contains("weight") {
                if let weight = try await service.readWeight(for: date) {
                    result["weight_kg"] = weight
                } else {
                    warnings.append("No weight data available.")
                }
            }

            if fields.contains("calories_consumed") {
                result["calories_consumed"] = try await service.readDietaryEnergy(for: date)
            }

            if fields.contains("active_calories") {
                result["active_calories_burned"] = try await service.readActiveEnergy(for: date)
            }

            if fields.contains("resting_calories") {
                result["resting_calories_burned"] = try await service.readBasalEnergy(for: date)
            }

            if fields.contains("dietary_entries") {
                let samples = try await service.readDietarySamples(for: date)
                result["dietary_entries"] = samples.map { sample in
                    var entry: [String: Any] = [
                        "time": LocalDateFormatter.string(from: sample.date),
                        "calories": sample.calories,
                    ]
                    if let name = sample.mealName { entry["meal_name"] = name }
                    if let p = sample.protein { entry["protein_g"] = p }
                    if let f = sample.fat { entry["fat_g"] = f }
                    if let c = sample.carbs { entry["carbs_g"] = c }
                    return entry
                }
            }

            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(
                    result: result,
                    warnings: warnings.isEmpty ? nil : warnings
                ),
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
}
