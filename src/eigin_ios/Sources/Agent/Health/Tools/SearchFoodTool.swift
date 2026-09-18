import Foundation

struct SearchFoodTool: Tool {
    static let capability = ToolCapability(
        kind: .builtIn, key: "search_food",
        displayName: Localized.Tools.Search.food,
        description: Localized.Tools.Description.searchFood,
        defaultPermissionLevel: .ask, category: .health
    )

    let name = "search_food"
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
            description: "Search for food products by name. Returns nutritional information per 100g and per serving.",
            parameters: JSONSchema(
                type: "object",
                properties: [
                    "query": .init(
                        type: "string",
                        description: "Food name to search for."
                    ),
                    "limit": .init(
                        type: "integer",
                        description: "Maximum number of results (default 5)."
                    ),
                ],
                required: ["query"]
            )
        )
    }

    func disclosure(for toolCall: ToolCall) -> ToolDisclosure? {
        guard let query = ToolHelpers.stringArgument(toolCall, "query") else { return nil }
        return ToolDisclosure(
            actionPhrase: Localized.Permission.Disclosure.lookUpFood,
            detail: .inline(query)
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

        guard let query = args["query"] as? String,
              !query.trimmingCharacters(in: .whitespaces).isEmpty
        else {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: ["Missing or empty 'query'."]),
                isError: true
            )
        }

        let limit = args["limit"] as? Int ?? 5

        let result = await foodLookup.search(query: query, limit: limit)

        switch result {
        case .success(let products):
            let productDicts: [[String: Any]] = products.map { product in
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
                return dict
            }
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(result: [
                    "products": productDicts,
                    "count": products.count,
                ]),
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
