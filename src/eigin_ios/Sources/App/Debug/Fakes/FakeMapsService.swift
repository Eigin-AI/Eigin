#if DEBUG || EIGIN_DEV
import CoreLocation
import Foundation

final class FakeMapsService: MapsService, @unchecked Sendable {
    var searchResults: [Place] = []
    var searchError: (any Error)?
    var route: Route?
    var directionsError: (any Error)?

    private(set) var searchCalls: [(query: String, near: CLLocationCoordinate2D?)] = []
    private(set) var directionsCalls: [(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D,
        mode: TravelMode
    )] = []

    func searchPlaces(
        query: String,
        near: CLLocationCoordinate2D?
    ) async -> Result<[Place], any Error> {
        searchCalls.append((query: query, near: near))
        if let searchError { return .failure(searchError) }
        return .success(searchResults)
    }

    func directions(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        mode: TravelMode
    ) async -> Result<Route, any Error> {
        directionsCalls.append((from: origin, to: destination, mode: mode))
        if let directionsError { return .failure(directionsError) }
        guard let route else { return .failure(MapsError.noRoute) }
        return .success(route)
    }
}
#endif
