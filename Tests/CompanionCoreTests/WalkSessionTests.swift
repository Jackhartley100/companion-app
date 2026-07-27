import Testing
import Foundation
@testable import CompanionCore

private let base = Date(timeIntervalSince1970: 1_770_000_000)
private let dogID = UUID()
private let ownerID = UUID()

private func session(startingAt start: Date = base) -> WalkSession {
    WalkSession(startDate: start, dogIDs: [dogID])
}

@Suite("Walk session arithmetic")
struct WalkSessionTests {
    @Test("Distance accumulates as points are appended")
    func distanceAccumulates() {
        var walk = session()
        for point in SyntheticRoute.line(metres: 1_000, pointCount: 50, startingAt: base) {
            walk.append(point)
        }
        #expect(abs(walk.distance - 1_000) < 5)
    }

    @Test("Incremental distance matches recomputing the whole polyline")
    func incrementalDistanceMatchesFullRecalculation() {
        var walk = session()
        let route = SyntheticRoute.loop(pointCount: 200, startingAt: base)
        for point in route { walk.append(point) }
        #expect(abs(walk.distance - walk.points.totalDistance) < 0.01)
    }

    @Test("Elapsed time includes pauses and moving time excludes them")
    func pauseAccounting() {
        var walk = session()
        walk.pause(at: base.addingTimeInterval(600))
        walk.resume(at: base.addingTimeInterval(900))
        let now = base.addingTimeInterval(1_800)

        #expect(walk.elapsedDuration(asOf: now) == 1_800)
        #expect(walk.pausedDuration(asOf: now) == 300)
        #expect(walk.movingDuration(asOf: now) == 1_500)
    }

    @Test("An open pause counts up to the current moment")
    func openPauseCountsToNow() {
        var walk = session()
        walk.pause(at: base.addingTimeInterval(600))
        let now = base.addingTimeInterval(900)
        #expect(walk.pausedDuration(asOf: now) == 300)
        #expect(walk.movingDuration(asOf: now) == 600)
    }

    @Test("Multiple pauses accumulate")
    func multiplePauses() {
        var walk = session()
        walk.pause(at: base.addingTimeInterval(100))
        walk.resume(at: base.addingTimeInterval(200))
        walk.pause(at: base.addingTimeInterval(400))
        walk.resume(at: base.addingTimeInterval(500))
        let now = base.addingTimeInterval(1_000)
        #expect(walk.pausedDuration(asOf: now) == 200)
        #expect(walk.movingDuration(asOf: now) == 800)
    }

    /// The behaviour that stops a coffee stop being drawn as a walked segment.
    @Test("Points offered while paused are discarded")
    func pausedPointsIgnored() {
        var walk = session()
        let route = SyntheticRoute.line(metres: 1_000, pointCount: 50, startingAt: base)
        walk.append(route[0])
        walk.pause(at: base.addingTimeInterval(10))
        for point in route[1..<25] { walk.append(point) }
        #expect(walk.points.count == 1)
        #expect(walk.distance == 0)

        walk.resume(at: base.addingTimeInterval(200))
        for point in route[25...] { walk.append(point) }
        #expect(walk.points.count == 26)
    }

    @Test("Pausing twice in a row does not open a second interval")
    func doublePauseIsIdempotent() {
        var walk = session()
        walk.pause(at: base.addingTimeInterval(100))
        walk.pause(at: base.addingTimeInterval(150))
        #expect(walk.pauses.count == 1)
    }

    @Test("Resuming when not paused does nothing")
    func resumeWithoutPauseIsIdempotent() {
        var walk = session()
        walk.resume(at: base.addingTimeInterval(100))
        #expect(walk.pauses.isEmpty)
        #expect(walk.movingDuration(asOf: base.addingTimeInterval(200)) == 200)
    }

    @Test("Moving duration is never negative")
    func movingDurationNeverNegative() {
        var walk = session()
        walk.pause(at: base)
        #expect(walk.movingDuration(asOf: base.addingTimeInterval(-100)) == 0)
    }

    @Test("Average speed is distance over moving time, not elapsed time")
    func averageSpeedUsesMovingTime() {
        var walk = session()
        for point in SyntheticRoute.line(metres: 1_000, pointCount: 50, startingAt: base) {
            walk.append(point)
        }
        walk.pause(at: base.addingTimeInterval(500))
        walk.resume(at: base.addingTimeInterval(1_000))
        let now = base.addingTimeInterval(1_500)

        // 1,000 m over 1,000 s of moving time == 1 m/s.
        let speed = walk.averageSpeed(asOf: now)
        #expect(speed != nil)
        #expect(abs((speed ?? 0) - 1.0) < 0.02)
    }

    @Test("Average speed is nil before there is anything to average")
    func averageSpeedNilWhenEmpty() {
        let walk = session()
        #expect(walk.averageSpeed(asOf: base.addingTimeInterval(60)) == nil)
    }

    @Test("Current speed uses only the trailing window")
    func currentSpeedUsesWindow() {
        var walk = session()
        // Slow first: 200 m over 400 s.
        for point in SyntheticRoute.line(metres: 200, pointCount: 20, startingAt: base, secondsBetweenPoints: 21) {
            walk.append(point)
        }
        // Then fast: 100 m over 20 s, ending at t=420.
        let fastStart = base.addingTimeInterval(400)
        for point in SyntheticRoute.line(
            from: Coordinate(latitude: 51.5074 + 200 / 111_320.0, longitude: -0.1278),
            metres: 100,
            pointCount: 10,
            startingAt: fastStart,
            secondsBetweenPoints: 2
        ) {
            walk.append(point)
        }

        let now = base.addingTimeInterval(420)
        let current = walk.currentSpeed(asOf: now, window: 30)
        // The recent window is the fast section: ~5 m/s, not the ~0.7 m/s average.
        #expect(current != nil)
        #expect((current ?? 0) > 3)
    }

    @Test("Current speed is nil while paused")
    func currentSpeedNilWhilePaused() {
        var walk = session()
        for point in SyntheticRoute.line(pointCount: 20, startingAt: base) { walk.append(point) }
        walk.pause(at: base.addingTimeInterval(100))
        #expect(walk.currentSpeed(asOf: base.addingTimeInterval(110)) == nil)
    }

    @Test("A finished session becomes an activity with matching numbers")
    func makeActivity() {
        var walk = session()
        for point in SyntheticRoute.line(metres: 2_000, pointCount: 100, startingAt: base) {
            walk.append(point)
        }
        walk.pause(at: base.addingTimeInterval(600))
        walk.resume(at: base.addingTimeInterval(720))
        let end = base.addingTimeInterval(1_800)

        let activity = walk.makeActivity(
            ownerID: ownerID,
            endDate: end,
            title: "Morning Walk",
            visibility: .privateOnly
        )

        #expect(activity.id == walk.id)
        #expect(activity.title == "Morning Walk")
        #expect(activity.elapsedDuration == 1_800)
        #expect(activity.pausedDuration == 120)
        #expect(activity.movingDuration == 1_680)
        #expect(abs(activity.distance - walk.distance) < 0.01)
        #expect(activity.dogIDs == [dogID])
        #expect(activity.ownerID == ownerID)
        #expect(activity.routePointCount == 100)
        #expect(activity.recordingSource == .iPhone)
        #expect(activity.hasRoute)
    }

    @Test("A session round-trips through Codable for crash recovery")
    func codableRoundTrip() throws {
        var walk = session()
        for point in SyntheticRoute.loop(pointCount: 40, startingAt: base) { walk.append(point) }
        walk.pause(at: base.addingTimeInterval(100))
        walk.resume(at: base.addingTimeInterval(160))

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let restored = try decoder.decode(WalkSession.self, from: encoder.encode(walk))
        #expect(restored.id == walk.id)
        #expect(restored.points.count == walk.points.count)
        #expect(abs(restored.distance - walk.distance) < 0.01)
        #expect(restored.pauses.count == 1)
    }
}

@Suite("Activity derived values")
struct WalkActivityTests {
    @Test("Average pace is the inverse of average speed")
    func paceInvertsSpeed() {
        let activity = WalkActivity(
            title: "Test",
            startDate: base,
            endDate: base.addingTimeInterval(1_000),
            elapsedDuration: 1_000,
            movingDuration: 1_000,
            distance: 1_000,
            dogIDs: [dogID],
            ownerID: ownerID
        )
        #expect(activity.averageSpeed == 1.0)
        #expect(activity.averagePace == 1.0)
    }

    @Test("Pace and speed are nil for a zero-distance activity")
    func zeroDistanceHasNoPace() {
        let activity = WalkActivity(
            title: "Test",
            startDate: base,
            endDate: base.addingTimeInterval(600),
            elapsedDuration: 600,
            movingDuration: 600,
            distance: 0,
            dogIDs: [dogID],
            ownerID: ownerID
        )
        #expect(activity.averageSpeed == nil)
        #expect(activity.averagePace == nil)
    }
}
