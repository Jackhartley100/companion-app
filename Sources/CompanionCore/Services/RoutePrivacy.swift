import Foundation

/// Removes the parts of a route that reveal where someone lives.
///
/// A walk almost always starts and ends at the owner's front door. Sharing the
/// raw polyline therefore publishes a home address, which is the single most
/// sensitive thing this app holds. Trimming happens on the way *out* — the full
/// route is always kept on device so the owner's own history stays accurate.
public enum RoutePrivacy {
    /// Returns the route with everything within `radius` metres of the first and
    /// last points removed.
    ///
    /// - Parameter radius: Metres to hide at each end. 200 m covers a street or
    ///   two, enough that the remaining route does not point at one address.
    /// - Returns: The trimmed route, or an empty array when the whole walk falls
    ///   inside the hidden radius — a short walk around the block cannot be
    ///   shared as a map without giving away where it started.
    public static func trimmingEndpoints(
        _ points: [RoutePoint],
        radius: Double = 200
    ) -> [RoutePoint] {
        guard points.count > 2, radius > 0 else { return [] }
        guard let start = points.first?.coordinate, let end = points.last?.coordinate else {
            return []
        }

        var lower = 0
        while lower < points.count, start.distance(to: points[lower].coordinate) < radius {
            lower += 1
        }

        var upper = points.count - 1
        while upper > lower, end.distance(to: points[upper].coordinate) < radius {
            upper -= 1
        }

        guard lower < upper else { return [] }
        return Array(points[lower...upper])
    }

    /// Whether a route would still be worth sharing after trimming.
    public static func canShareMap(_ points: [RoutePoint], radius: Double = 200) -> Bool {
        trimmingEndpoints(points, radius: radius).count > 1
    }
}
