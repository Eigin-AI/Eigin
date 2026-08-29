import CoreLocation
import Foundation
import MapKit

struct GetDirectionsTool: Tool {
    static let capability = ToolCapability(
        kind: .builtIn, key: "get_directions",
        displayName: Localized.Tools.System.getDirections,
        defaultPermissionLevel: .always, category: .timeAndPlace
    )

    let name = "get_directions"
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
        .timeAndPlace
    }

    var defaultPermissionLevel: ToolPermissionLevel {
        .always
    }

    func definition() -> ToolDefinition {
        ToolDefinition(
            name: name,
            description: """
            Estimate a trip between two coordinates: travel time, distance, and a brief \
            route note. For driving, the time accounts for current traffic. Resolve \
            place coordinates with search_places first. This is a coarse estimate, not \
            turn-by-turn navigation.
            """,
            parameters: JSONSchema(
                type: "object",
                properties: [
                    "origin_latitude": .init(type: "number", description: "Start latitude."),
                    "origin_longitude": .init(type: "number", description: "Start longitude."),
                    "destination_latitude": .init(
                        type: "number",
                        description: "Destination latitude."
                    ),
                    "destination_longitude": .init(
                        type: "number",
                        description: "Destination longitude."
                    ),
                    "mode": .init(
                        type: "string",
                        description: "Travel mode (default drive).",
                        enum: ["drive", "walk", "transit"]
                    ),
                ],
                required: [
                    "origin_latitude", "origin_longitude",
                    "destination_latitude", "destination_longitude",
                ]
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

        guard let originLat = args["origin_latitude"] as? Double,
              let originLon = args["origin_longitude"] as? Double,
              let destLat = args["destination_latitude"] as? Double,
              let destLon = args["destination_longitude"] as? Double
        else {
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(
                    errors: ["Missing origin or destination coordinates."]
                ),
                isError: true
            )
        }

        let mode = (args["mode"] as? String).flatMap(TravelMode.init(rawValue:)) ?? .drive
        let origin = CLLocationCoordinate2D(latitude: originLat, longitude: originLon)
        let destination = CLLocationCoordinate2D(latitude: destLat, longitude: destLon)

        let result = await maps.directions(from: origin, to: destination, mode: mode)

        switch result {
        case .success(let route):
            var dict: [String: Any] = [
                "mode": mode.rawValue,
                "travel_time": Self.formatTime(route.travelTime),
                "distance": Self.formatDistance(route.distance),
            ]
            if let summary = route.summary { dict["route"] = summary }
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(result: dict),
                isError: false
            )
        case .failure(let error):
            // Transit data is often unavailable — report it as a warning, not a hard failure.
            if let mapsError = error as? MapsError, mapsError == .transitUnavailable {
                return ToolResult(
                    toolCallID: id,
                    content: ToolHelpers.output(
                        warnings: ["Transit directions aren't available for this area."]
                    ),
                    isError: false
                )
            }
            return ToolResult(
                toolCallID: id,
                content: ToolHelpers.output(errors: [error.localizedDescription]),
                isError: true
            )
        }
    }

    // MARK: - Formatting

    private static func formatTime(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: seconds) ?? "\(Int(seconds / 60)) min"
    }

    private static func formatDistance(_ meters: CLLocationDistance) -> String {
        MKDistanceFormatter().string(fromDistance: meters)
    }
}
