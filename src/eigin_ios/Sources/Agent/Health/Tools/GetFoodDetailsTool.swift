import Foundation

struct GetFoodDetailsTool: Tool {
    static let capability = ToolCapability(
        kind: .builtIn, key: "get_food_details",
        displayName: Localized.Tools.Get.Food.details,
        defaultPermissionLevel: .ask, category: .health
    )

    let name = "get_food_details"
    var isSmallContext: Bool = false
    let foodLookup: any FoodLookupService

    init(foodLookup: any FoodLookupService = OpenFoodFactsClient()) {
        self.foodLookup = foodLookup
    }

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
            description: "Get detailed nutritional information for a food product by barcode.",
            parameters: JSONSchema(
                type: "object",
                properties: [
                    "barcode": .init(
                        type: "string",
                        description: "Product barcode."
                    ),
                ],
                required: ["barcode"]
            )
        )
    }

    @MainActor func execute(_ toolCall: ToolCall, agent: Agent) async -> ToolResult {
        let id = toolCall.id

        guard let args = ToolHelpers.parseArguments(toolCall.function.arguments) else {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: ["Invalid JSON arguments."]),
                isError: true
            )
        }

        guard let barcode = args["barcode"] as? String, !barcode.isEmpty else {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: ["Missing or empty 'barcode'."]),
                isError: true
            )
        }

        let result = await foodLookup.getProduct(barcode: barcode)

        switch result {
        case .success(let product):
            var dict: [String: Any] = [
                "barcode": product.barcode,
                "name": product.name,
            ]
            if let brands = product.brands, !brands.isEmpty { dict["brands"] = brands }
            if let serving = product.servingSize { dict["serving_size"] = serving }
            if let cal = product.caloriesPer100g { dict["calories_per_100g"] = cal }
            if let cal = product.caloriesPerServing { dict["calories_per_serving"] = cal }
            if let p = product.proteinPer100g { dict["protein_per_100g"] = p }
            if let f = product.fatPer100g { dict["fat_per_100g"] = f }
            if let c = product.carbsPer100g { dict["carbs_per_100g"] = c }
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(result: dict),
                isError: false
            )
        case .failure(let error):
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: [error.localizedDescription]),
                isError: true
            )
        }
    }
}
