import CoreLocation
import Foundation

/// A plain, `Codable`, `Hashable` coordinate.
///
/// `CLLocationCoordinate2D` is none of those things, and coverage data gets
/// archived to disk constantly, so the model layer uses this instead and
/// converts at the MapKit boundary.
struct Coordinate: Codable, Hashable {
    var latitude: Double
    var longitude: Double

    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    init(_ coordinate: CLLocationCoordinate2D) {
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
    }

    var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }
}
