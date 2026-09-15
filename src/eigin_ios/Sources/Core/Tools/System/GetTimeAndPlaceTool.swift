import CoreLocation
import Foundation
import MapKit

struct GetTimeAndPlaceTool: Tool {
    static let capability = ToolCapability(
        kind: .builtIn, key: "get_time_and_place",
        displayName: Localized.Tools.System.timeAndPlace,
        defaultPermissionLevel: .always, category: .timeAndPlace
    )

    let name = "get_time_and_place"
    var isSmallContext: Bool = false
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

    /// Whether the tool may trigger a location permission prompt (false during live calls).
    let canPromptUser: Bool

    func definition() -> ToolDefinition {
        ToolDefinition(
            name: name,
            description: "Get the current time, timezone, and location.",
            parameters: JSONSchema(type: "object")
        )
    }

    @MainActor func execute(_ toolCall: ToolCall, agent: Agent) async -> ToolResult {
        let id = toolCall.id
        let now = Date()
        let timeZone = TimeZone.current

        let timeString = LocalDateFormatter.string(from: now)

        let tzName = timeZone.abbreviation() ?? "UTC"

        var result: [String: Any] = ["time": timeString, "timezone": tzName]
        var warnings: [String]?

        switch await LocationResolver.resolve(canPromptUser: canPromptUser) {
        case .success(let location):
            if let name = location.name { result["location"] = name }
            result["latitude"] = location.latitude
            result["longitude"] = location.longitude
        case .failure(let error):
            warnings = [LocationResolver.message(for: error)]
        }

        return ToolResult(
            toolCallID: id,
            content: ToolHelpers.output(result: result, warnings: warnings),
            isError: false
        )
    }
}
