import Foundation

struct LogFoodTool: Tool {
    static let capability = ToolCapability(
        kind: .builtIn, key: "log_food",
        displayName: Localized.Tools.Log.food,
        defaultPermissionLevel: .ask, category: .system
    )

    let name = "log_food"
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

    func definition() -> ToolDefinition {
        if isSmallContext {
            return ToolDefinition(
                name: name,
                description: "Log food to Apple Health.",
                parameters: JSONSchema(
                    type: "object",
                    properties: [
                        "calories": .init(type: "number", description: "Calories (kcal)."),
                        "meal_name": .init(
                            type: "string",
                            description: "Name of the food or meal."
                        ),
                    ],
                    required: ["calories", "meal_name"]
                )
            )
        }
        return ToolDefinition(
            name: name,
            description:
            "Log a food entry to Apple Health with calories and optional macronutrients.",
            parameters: JSONSchema(
                type: "object",
                properties: [
                    "calories": .init(
                        type: "number",
                        description: "Calories (kcal)."
                    ),
                    "protein_g": .init(
                        type: "number",
                        description: "Protein in grams (optional)."
                    ),
                    "fat_g": .init(
                        type: "number",
                        description: "Fat in grams (optional)."
                    ),
                    "carbs_g": .init(
                        type: "number",
                        description: "Carbohydrates in grams (optional)."
                    ),
                    "meal_name": .init(
                        type: "string",
                        description: "Name of the food or meal (optional)."
                    ),
                    "date": .init(
                        type: "string",
                        description:
                        "Date/time to log (e.g. \"2026-04-12 12:30\"). Defaults to now."
                    ),
                ],
                required: ["calories", "meal_name"]
            )
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

        guard let calories = args["calories"] as? Double else {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: ["Missing 'calories' (number)."]), isError: true
            )
        }

        let protein = args["protein_g"] as? Double
        let fat = args["fat_g"] as? Double
        let carbs = args["carbs_g"] as? Double
        let mealName = args["meal_name"] as? String

        let date: Date = if let dateString = args["date"] as? String,
                            let parsed = LocalDateFormatter.parse(dateString)
        {
            parsed
        } else {
            Date()
        }

        do {
            try await service.logDietaryEnergy(
                calories: calories, protein: protein, fat: fat,
                carbs: carbs, mealName: mealName, date: date
            )

            var result: [String: Any] = [
                "logged": true,
                "calories": calories,
                "date": LocalDateFormatter.string(from: date),
            ]
            if let mealName { result["meal_name"] = mealName }
            if let protein { result["protein_g"] = protein }
            if let fat { result["fat_g"] = fat }
            if let carbs { result["carbs_g"] = carbs }

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
