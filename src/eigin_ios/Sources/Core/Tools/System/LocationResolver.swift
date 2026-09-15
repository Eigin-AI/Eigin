import CoreLocation
import Foundation
import MapKit

/// A resolved location: always carries coordinates, plus a place name when one
/// is known.
struct ResolvedLocation {
    let name: String?
    let latitude: Double
    let longitude: Double
}

/// Shared current-location resolution for awareness tools.
///
/// Resolves the user's current location (coordinates + short place name),
/// requesting permission when allowed. Tools that can prompt must pass
/// `canPromptUser: true`; live calls pass `false` so no prompt appears.
enum LocationResolver {
    @MainActor
    static func resolve(canPromptUser: Bool) async -> Result<ResolvedLocation, LocationError> {
        let manager = CLLocationManager()
        let status = manager.authorizationStatus

        switch status {
        case .notDetermined:
            if canPromptUser {
                let helper = LocationPermissionRequester()
                let granted = await helper.requestPermission(manager: manager)
                if granted == .authorizedWhenInUse || granted == .authorizedAlways {
                    return await resolveAuthorized()
                }
                return .failure(.denied)
            } else {
                return .failure(.cannotPrompt)
            }

        case .denied, .restricted:
            return .failure(.denied)

        case .authorizedWhenInUse, .authorizedAlways:
            return await resolveAuthorized()

        @unknown default:
            return .failure(.unavailable)
        }
    }

    /// Human-readable message for a failed resolution.
    static func message(for error: LocationError) -> String {
        switch error {
        case .denied: "Location access was denied by the user."
        case .cannotPrompt:
            "Location access cannot be requested while chat is in the background."
        case .noFix: "Could not determine current location."
        case .unavailable: "Location access is unavailable."
        }
    }

    private static func resolveAuthorized() async -> Result<ResolvedLocation, LocationError> {
        guard let location = await fetchCurrentLocation() else {
            return .failure(.noFix)
        }

        let placeName = await reverseGeocode(location)
        return .success(
            ResolvedLocation(
                name: placeName,
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            )
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

/// Errors resolving the user's current location.
enum LocationError: Error, Equatable {
    /// Location access was denied by the user.
    case denied
    /// Permission cannot be requested (chat is in the background).
    case cannotPrompt
    /// A location fix could not be obtained in time.
    case noFix
    /// Location services are unavailable.
    case unavailable
}

// MARK: - Permission request

private final class LocationPermissionRequester: NSObject, CLLocationManagerDelegate,
    @unchecked Sendable
{
    private var continuation: CheckedContinuation<CLAuthorizationStatus, Never>?

    @MainActor
    func requestPermission(manager: CLLocationManager) async -> CLAuthorizationStatus {
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
}
