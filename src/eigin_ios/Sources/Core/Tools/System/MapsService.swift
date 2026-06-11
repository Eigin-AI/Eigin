import CoreLocation
import Foundation

// MARK: - Protocol

/// Boundary for map lookups: finding places and estimating trips between points.
protocol MapsService: Sendable {
    /// Search for places matching a query, optionally biased near a coordinate.
    func searchPlaces(
        query: String,
        near: CLLocationCoordinate2D?
    ) async -> Result<[Place], any Error>

    /// Estimate a trip between two coordinates by travel mode.
    func directions(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        mode: TravelMode
    ) async -> Result<Route, any Error>
}

// MARK: - Value Types

/// A located place returned by a search.
struct Place {
    let name: String
    let address: String?
    let latitude: Double
    let longitude: Double
    let category: String?
}

/// A coarse trip estimate between two points.
struct Route {
    let travelTime: TimeInterval
    let distance: CLLocationDistance
    /// A short human-readable route note, when one is available.
    let summary: String?
}

/// Supported travel modes for directions.
enum TravelMode: String {
    case drive
    case walk
    case transit
}

/// Errors a `MapsService` can surface that callers handle specially.
enum MapsError: Error, Equatable {
    /// No route could be found between the two points.
    case noRoute
    /// Transit routing data is sparse or unavailable for the region.
    case transitUnavailable
}
