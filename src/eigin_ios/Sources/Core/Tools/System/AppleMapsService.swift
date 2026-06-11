import CoreLocation
import Foundation
import MapKit

/// MapKit-backed implementation of `MapsService`.
///
/// `MKLocalSearch` and `MKDirections` are server queries against Apple Maps —
/// they take coordinates and text and never read the device's location, so this
/// service needs no location authorization of its own.
struct AppleMapsService: MapsService {
    /// Maximum number of places returned from a search.
    private let resultLimit = 5

    // MARK: - Search

    func searchPlaces(
        query: String,
        near: CLLocationCoordinate2D?
    ) async -> Result<[Place], any Error> {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        if let near {
            request.region = MKCoordinateRegion(
                center: near,
                latitudinalMeters: 10000,
                longitudinalMeters: 10000
            )
        }

        do {
            let response = try await MKLocalSearch(request: request).start()
            let places = response.mapItems.prefix(resultLimit).map { item in
                Place(
                    name: item.name ?? "Unknown",
                    address: item.address?.shortAddress,
                    latitude: item.location.coordinate.latitude,
                    longitude: item.location.coordinate.longitude,
                    category: item.pointOfInterestCategory.map(Self.readableCategory)
                )
            }
            return .success(Array(places))
        } catch {
            return .failure(error)
        }
    }

    // MARK: - Directions

    func directions(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        mode: TravelMode
    ) async -> Result<Route, any Error> {
        let request = MKDirections.Request()
        request.source = MKMapItem(
            location: CLLocation(latitude: origin.latitude, longitude: origin.longitude),
            address: nil
        )
        request.destination = MKMapItem(
            location: CLLocation(latitude: destination.latitude, longitude: destination.longitude),
            address: nil
        )
        request.transportType = mode.transportType

        // MapKit does not return transit route steps, only an ETA.
        if mode == .transit {
            do {
                let eta = try await MKDirections(request: request).calculateETA()
                return .success(Route(
                    travelTime: eta.expectedTravelTime,
                    distance: eta.distance,
                    summary: nil
                ))
            } catch {
                return .failure(MapsError.transitUnavailable)
            }
        }

        // Departing now makes driving estimates traffic-aware.
        request.departureDate = Date()
        do {
            let response = try await MKDirections(request: request).calculate()
            guard let route = response.routes.first else {
                return .failure(MapsError.noRoute)
            }
            return .success(Route(
                travelTime: route.expectedTravelTime,
                distance: route.distance,
                summary: route.name.isEmpty ? nil : route.name
            ))
        } catch {
            return .failure(error)
        }
    }

    // MARK: - Helpers

    /// Strip MapKit's `MKPOICategory` prefix for a readable category name.
    private static func readableCategory(_ category: MKPointOfInterestCategory) -> String {
        category.rawValue.replacingOccurrences(of: "MKPOICategory", with: "")
    }
}

private extension TravelMode {
    var transportType: MKDirectionsTransportType {
        switch self {
        case .drive: .automobile
        case .walk: .walking
        case .transit: .transit
        }
    }
}
