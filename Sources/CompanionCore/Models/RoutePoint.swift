import Foundation
import CoreLocation

/// A latitude/longitude pair, independent of CoreLocation so that domain code and
/// its tests do not need a location stack.
public struct Coordinate: Codable, Sendable, Hashable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// A single recorded location fix.
///
/// Kept deliberately small: a one-hour walk produces roughly 3,600 of these, and
/// they are persisted separately from activity metadata (see `RouteStore`) so
/// that listing 500 walks does not decode half a million points.
public struct RoutePoint: Codable, Sendable, Hashable {
    public var coordinate: Coordinate
    /// Metres above sea level, or `nil` when the fix carried no vertical estimate.
    public var altitude: Double?
    /// Radius of uncertainty in metres. Negative values from CoreLocation mean
    /// "invalid" and are normalised to `nil` at the boundary.
    public var horizontalAccuracy: Double?
    public var verticalAccuracy: Double?
    /// Metres per second as reported by the device, or `nil` when unavailable.
    public var speed: Double?
    /// Heading in degrees, or `nil` when unavailable.
    public var course: Double?
    public var timestamp: Date

    public init(
        coordinate: Coordinate,
        altitude: Double? = nil,
        horizontalAccuracy: Double? = nil,
        verticalAccuracy: Double? = nil,
        speed: Double? = nil,
        course: Double? = nil,
        timestamp: Date
    ) {
        self.coordinate = coordinate
        self.altitude = altitude
        self.horizontalAccuracy = horizontalAccuracy
        self.verticalAccuracy = verticalAccuracy
        self.speed = speed
        self.course = course
        self.timestamp = timestamp
    }

    public var latitude: Double { coordinate.latitude }
    public var longitude: Double { coordinate.longitude }
}

// MARK: - Geometry

public extension Coordinate {
    /// Great-circle distance in metres using the haversine formula.
    ///
    /// Haversine rather than Vincenty: over the sub-kilometre segments between
    /// consecutive GPS fixes the error against the WGS-84 ellipsoid is far below
    /// the accuracy of the fixes themselves, and it has no convergence failure mode.
    func distance(to other: Coordinate) -> Double {
        let earthRadius = 6_371_008.8 // metres, IUGG mean radius
        let lat1 = latitude * .pi / 180
        let lat2 = other.latitude * .pi / 180
        let deltaLat = (other.latitude - latitude) * .pi / 180
        let deltaLon = (other.longitude - longitude) * .pi / 180

        let a = sin(deltaLat / 2) * sin(deltaLat / 2)
            + cos(lat1) * cos(lat2) * sin(deltaLon / 2) * sin(deltaLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(max(0, 1 - a)))
        return earthRadius * c
    }
}

public extension Array where Element == RoutePoint {
    /// Total distance in metres along the polyline.
    var totalDistance: Double {
        guard count > 1 else { return 0 }
        var total = 0.0
        for index in 1..<count {
            total += self[index - 1].coordinate.distance(to: self[index].coordinate)
        }
        return total
    }

    /// Sum of positive altitude changes in metres, ignoring changes smaller than
    /// `threshold` because barometric and GPS altitude noise otherwise accumulates
    /// into a large fictional climb on flat ground.
    func elevationGain(threshold: Double = 3.0) -> Double? {
        let altitudes = compactMap(\.altitude)
        guard altitudes.count > 1 else { return nil }
        var gain = 0.0
        var reference = altitudes[0]
        for altitude in altitudes.dropFirst() {
            let delta = altitude - reference
            if delta > threshold {
                gain += delta
                reference = altitude
            } else if delta < -threshold {
                reference = altitude
            }
        }
        return gain
    }
}

// MARK: - CoreLocation interoperability

public extension Coordinate {
    init(_ coordinate: CLLocationCoordinate2D) {
        self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

public extension RoutePoint {
    /// Builds a route point from a CoreLocation fix, normalising the sentinel
    /// negative values CoreLocation uses to mean "this field is invalid".
    init(_ location: CLLocation) {
        self.init(
            coordinate: Coordinate(location.coordinate),
            altitude: location.verticalAccuracy >= 0 ? location.altitude : nil,
            horizontalAccuracy: location.horizontalAccuracy >= 0 ? location.horizontalAccuracy : nil,
            verticalAccuracy: location.verticalAccuracy >= 0 ? location.verticalAccuracy : nil,
            speed: location.speed >= 0 ? location.speed : nil,
            course: location.course >= 0 ? location.course : nil,
            timestamp: location.timestamp
        )
    }
}
