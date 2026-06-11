import CoreLocation
import Foundation
import MapKit

struct GetTimeAndPlaceTool: Tool {
    static let capability = ToolCapability(
        kind: .builtIn, key: "get_time_and_place",
        displayName: Localized.Tools.System.timeAndPlace,
        defaultPermissionLevel: .always, category: .system
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
        .system
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

        let location = await LocationHelper.fetchLocation(canPromptUser: canPromptUser)

        var result: [String: Any] = ["time": timeString, "timezone": tzName]
        var warnings: [String]?

        switch location {
        case .resolved(let placeName, let lat, let lon):
            if let placeName { result["location"] = placeName }
            result["latitude"] = lat
            result["longitude"] = lon
        case .unavailable(let warning):
            warnings = [warning]
        }

        return ToolResult(
            toolCallID: id,
            content: ToolHelpers.output(result: result, warnings: warnings),
            isError: false
        )
    }
}

// MARK: - LocationHelper

private enum LocationResult {
    /// A resolved location: always carries coordinates, plus a place name when one is known.
    case resolved(name: String?, lat: Double, lon: Double)
    case unavailable(String)
}

private final class LocationHelper: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
    private var continuation: CheckedContinuation<CLAuthorizationStatus, Never>?

    @MainActor
    static func fetchLocation(canPromptUser: Bool) async -> LocationResult {
        let manager = CLLocationManager()
        let status = manager.authorizationStatus

        switch status {
        case .notDetermined:
            if canPromptUser {
                let helper = LocationHelper()
                let granted = await helper.requestPermission(manager: manager)
                if granted == .authorizedWhenInUse || granted == .authorizedAlways {
                    return await resolveLocation()
                }
                return .unavailable("Location access was denied by the user.")
            } else {
                return .unavailable(
                    "Location access cannot be requested while chat is in the background."
                )
            }

        case .denied, .restricted:
            return .unavailable("Location access was denied by the user.")

        case .authorizedWhenInUse, .authorizedAlways:
            return await resolveLocation()

        @unknown default:
            return .unavailable("Location access is unavailable.")
        }
    }

    // MARK: - Permission request via delegate

    @MainActor
    private func requestPermission(manager: CLLocationManager) async -> CLAuthorizationStatus {
        manager.delegate = self
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            manager.requestWhenInUseAuthorization()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard manager.authorizationStatus != .notDetermined else { return }
        continuation?.resume(returning: manager.authorizationStatus)
        continuation = nil
    }

    // MARK: - Location fetching

    private static func resolveLocation() async -> LocationResult {
        guard let location = await fetchCurrentLocation() else {
            return .unavailable("Could not determine current location.")
        }

        let placeName = await reverseGeocode(location)
        return .resolved(
            name: placeName,
            lat: location.coordinate.latitude,
            lon: location.coordinate.longitude
        )
    }

    private static func fetchCurrentLocation() async -> CLLocation? {
        await withTaskGroup(of: CLLocation?.self) { group in
            group.addTask {
                do {
                    for try await update in CLLocationUpdate.liveUpdates() {
                        if let location = update.location { return location }
                    }
                } catch {}
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(5))
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }

    private static func reverseGeocode(_ location: CLLocation) async -> String? {
        guard let request = MKReverseGeocodingRequest(location: location),
              let item = try? await request.mapItems.first,
              let address = item.address
        else { return nil }
        return address.shortAddress
    }
}
