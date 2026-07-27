import Testing
import Foundation
@testable import CompanionCore

/// Fixed reference point so distances in these tests are reasoned about in
/// metres rather than in degrees.
private let origin = Coordinate(latitude: 51.5074, longitude: -0.1278)
private let base = Date(timeIntervalSince1970: 1_770_000_000)

/// Builds a point `metresNorth` from `origin`, `secondsLater` after `base`.
private func point(
    metresNorth: Double,
    secondsLater: TimeInterval,
    accuracy: Double? = 5,
    timestamp: Date? = nil
) -> RoutePoint {
    RoutePoint(
        coordinate: Coordinate(
            latitude: origin.latitude + metresNorth / 111_320.0,
            longitude: origin.longitude
        ),
        horizontalAccuracy: accuracy,
        timestamp: timestamp ?? base.addingTimeInterval(secondsLater)
    )
}

@Suite("Route filtering")
struct RouteFilterTests {
    @Test("The first usable fix is always accepted")
    func firstFixAccepted() {
        var filter = RouteFilter()
        let decision = filter.evaluate(point(metresNorth: 0, secondsLater: 0))
        #expect(decision == .accepted(point(metresNorth: 0, secondsLater: 0)))
    }

    @Test("A fix with unusable accuracy is rejected")
    func poorAccuracyRejected() {
        var filter = RouteFilter()
        #expect(
            filter.evaluate(point(metresNorth: 0, secondsLater: 0, accuracy: 120))
                == .rejected(.poorAccuracy)
        )
    }

    @Test("A fix with no accuracy reading at all is rejected")
    func missingAccuracyRejected() {
        var filter = RouteFilter()
        #expect(
            filter.evaluate(point(metresNorth: 0, secondsLater: 0, accuracy: nil))
                == .rejected(.poorAccuracy)
        )
    }

    @Test("A cached fix from before the walk started is rejected as stale")
    func staleFixRejected() {
        var filter = RouteFilter()
        let cached = point(
            metresNorth: 0,
            secondsLater: 0,
            timestamp: base.addingTimeInterval(-120)
        )
        #expect(filter.evaluate(cached, now: base) == .rejected(.staleTimestamp))
    }

    /// The behaviour that stops a walk's distance being inflated by a
    /// cell-tower positioning jump.
    @Test("A physically impossible jump is rejected")
    func impossibleJumpRejected() {
        var filter = RouteFilter(configuration: .forActivity(.walk))
        _ = filter.evaluate(point(metresNorth: 0, secondsLater: 0))
        // 300 m in 2 seconds is 150 m/s.
        let jump = point(metresNorth: 300, secondsLater: 2)
        #expect(filter.evaluate(jump) == .rejected(.impossibleSpeed))
    }

    @Test("Distance is not accumulated while standing still")
    func jitterRejected() {
        var filter = RouteFilter()
        _ = filter.evaluate(point(metresNorth: 0, secondsLater: 0))
        // 1 m of movement against a 5 m accuracy reading is noise.
        #expect(
            filter.evaluate(point(metresNorth: 1, secondsLater: 5))
                == .rejected(.belowMovementThreshold)
        )
    }

    @Test("The jitter threshold widens as accuracy worsens")
    func jitterThresholdScalesWithAccuracy() {
        // 8 m of movement is real against a ±5 m fix...
        var precise = RouteFilter()
        _ = precise.evaluate(point(metresNorth: 0, secondsLater: 0, accuracy: 5))
        #expect(precise.evaluate(point(metresNorth: 8, secondsLater: 5, accuracy: 5)) != .rejected(.belowMovementThreshold))

        // ...but indistinguishable from noise against a ±40 m fix.
        var vague = RouteFilter()
        _ = vague.evaluate(point(metresNorth: 0, secondsLater: 0, accuracy: 40))
        #expect(
            vague.evaluate(point(metresNorth: 8, secondsLater: 5, accuracy: 40))
                == .rejected(.belowMovementThreshold)
        )
    }

    @Test("Genuine walking movement is accepted")
    func realMovementAccepted() {
        var filter = RouteFilter()
        _ = filter.evaluate(point(metresNorth: 0, secondsLater: 0))
        // 7 m in 5 s is 1.4 m/s — an ordinary walking pace.
        guard case .accepted = filter.evaluate(point(metresNorth: 7, secondsLater: 5)) else {
            Issue.record("A normal walking step should be accepted")
            return
        }
    }

    @Test("A rejected fix does not become the new reference point")
    func rejectedFixDoesNotAdvanceReference() {
        var filter = RouteFilter(configuration: .forActivity(.walk))
        _ = filter.evaluate(point(metresNorth: 0, secondsLater: 0))
        _ = filter.evaluate(point(metresNorth: 500, secondsLater: 2)) // impossible
        // The next genuine step is measured from the last *good* point, so the
        // bad fix cannot poison the following comparison.
        #expect(filter.lastAcceptedPoint?.latitude == origin.latitude)
    }

    @Test("Filtering a whole trace keeps the real steps and drops the noise")
    func wholeTraceFiltering() {
        let trace = [
            point(metresNorth: 0, secondsLater: 0),
            point(metresNorth: 1, secondsLater: 5),      // jitter
            point(metresNorth: 8, secondsLater: 10),     // real
            point(metresNorth: 900, secondsLater: 12),   // impossible jump
            point(metresNorth: 16, secondsLater: 15),    // real
            point(metresNorth: 24, secondsLater: 20, accuracy: 90) // unusable
        ]
        let result = RouteFilter.filter(trace)
        #expect(result.accepted.count == 3)
        #expect(result.rejections.contains(.belowMovementThreshold))
        #expect(result.rejections.contains(.impossibleSpeed))
        #expect(result.rejections.contains(.poorAccuracy))
    }

    @Test("Resetting clears the reference point so a pause gap is not measured")
    func resetClearsReference() {
        var filter = RouteFilter()
        _ = filter.evaluate(point(metresNorth: 0, secondsLater: 0))
        filter.reset()
        #expect(filter.lastAcceptedPoint == nil)
        // A point far away is now the first point again, not an impossible jump.
        guard case .accepted = filter.evaluate(point(metresNorth: 5_000, secondsLater: 600)) else {
            Issue.record("After a reset the next fix starts a fresh segment")
            return
        }
    }
}

@Suite("Route geometry")
struct RouteGeometryTests {
    @Test("Haversine distance matches a known north-south separation")
    func haversineAccuracy() {
        // One degree of latitude is about 111.32 km.
        let a = Coordinate(latitude: 51.0, longitude: 0)
        let b = Coordinate(latitude: 52.0, longitude: 0)
        let distance = a.distance(to: b)
        #expect(abs(distance - 111_195) < 500)
    }

    @Test("A 1 km synthetic line measures 1 km")
    func lineDistance() {
        let route = SyntheticRoute.line(metres: 1_000, pointCount: 50)
        #expect(abs(route.totalDistance - 1_000) < 5)
    }

    @Test("Total distance of an empty or single-point route is zero")
    func degenerateRoutes() {
        #expect([RoutePoint]().totalDistance == 0)
        #expect([SyntheticRoute.line(pointCount: 1)[0]].totalDistance == 0)
    }

    @Test("Elevation gain ignores noise below the threshold")
    func elevationGainIgnoresNoise() {
        let noisy = (0..<20).map { index in
            RoutePoint(
                coordinate: origin,
                altitude: 20 + (index % 2 == 0 ? 1.0 : -1.0),
                timestamp: base.addingTimeInterval(Double(index))
            )
        }
        #expect(noisy.elevationGain() == 0)
    }

    @Test("Elevation gain counts a genuine climb")
    func elevationGainCountsClimb() {
        let climb = (0..<10).map { index in
            RoutePoint(
                coordinate: origin,
                altitude: 20 + Double(index) * 10,
                timestamp: base.addingTimeInterval(Double(index))
            )
        }
        let gain = try? #require(climb.elevationGain())
        #expect(gain != nil)
        #expect(abs((gain ?? 0) - 90) < 1)
    }

    @Test("Route preview keeps the first and last coordinate")
    func previewKeepsEndpoints() {
        let route = SyntheticRoute.loop(pointCount: 500)
        let preview = RoutePreview.sample(from: route, limit: 60)
        #expect(preview.count == 60)
        #expect(preview.first == route.first?.coordinate)
        #expect(preview.last == route.last?.coordinate)
    }

    @Test("Route preview leaves a short route untouched")
    func previewPassesShortRouteThrough() {
        let route = SyntheticRoute.loop(pointCount: 10)
        #expect(RoutePreview.sample(from: route, limit: 60).count == 10)
    }
}
