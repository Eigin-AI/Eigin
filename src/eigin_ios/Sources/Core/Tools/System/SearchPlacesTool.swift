import CoreLocation
import Foundation

struct SearchPlacesTool: Tool {
    static let capability = ToolCapability(
        kind: .builtIn, key: "search_places",
        displayName: Localized.Tools.System.searchPlaces,
        defaultPermissionLevel: .always, category: .system
    )

    let name = "search_places"
    var isSmallContext: Bool = false
    let maps: any MapsService

    init(maps: any MapsService = AppleMapsService()) {
        self.maps = maps
    }

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
        .always
    }

    func definition() -> ToolDefinition {
        ToolDefinition(
            name: name,
            description: """
            Search for places by name or category (e.g. "Bioparc Málaga", "pharmacy"). \
            Pass latitude and longitude to bias results near a point — use the user's \
            current coordinates from get_time_and_place for nearby searches. Returns up \
            to 5 places with name, address, and coordinates.
            """,
            parameters: JSONSchema(
                type: "object",
                properties: [
                    "query": .init(
                        type: "string",
                        description: "Place name or category to search for."
                    ),
                    "latitude": .init(
                        type: "number",
                        description: "Optional latitude to bias results near."
                    ),
                    "longitude": .init(
                        type: "number",
                        description: "Optional longitude to bias results near."
                    ),
                ],
                required: ["query"]
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

        guard let query = args["query"] as? String,
              !query.trimmingCharacters(in: .whitespaces).isEmpty
        else {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: ["Missing or empty 'query'."]),
                isError: true
            )
        }

        var near: CLLocationCoordinate2D?
        if let latitude = args["latitude"] as? Double,
           let longitude = args["longitude"] as? Double
        {
            near = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }

        let result = await maps.searchPlaces(query: query, near: near)

        switch result {
        case .success(let places):
            let placeDicts: [[String: Any]] = places.map { place in
                var dict: [String: Any] = [
                    "name": place.name,
                    "latitude": place.latitude,
                    "longitude": place.longitude,
                ]
                if let address = place.address, !address.isEmpty { dict["address"] = address }
                if let category = place.category, !category.isEmpty { dict["category"] = category }
                return dict
            }
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(result: [
                    "places": placeDicts,
                    "count": places.count,
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
