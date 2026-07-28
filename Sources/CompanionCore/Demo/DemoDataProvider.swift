import Foundation

/// The single source of demonstration content for previews, tests and demo mode.
///
/// ## Keeping demo data out of real data
///
/// Every activity produced here carries `recordingSource == .demo`. Demo mode
/// runs against a `FileStore` rooted at a separate directory, so nothing written
/// in demo mode can reach the owner's real store even in principle — the
/// separation is a filesystem boundary, not a flag that a bug could flip.
public enum DemoDataProvider {
    public static let ownerID = UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!
    public static let roxyID = UUID(uuidString: "00000000-0000-0000-0000-0000000000B1")!
    public static let baileyID = UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!

    /// A fixed reference date so preview screenshots and test expectations do
    /// not change from one day to the next.
    public static let referenceDate = Date(timeIntervalSince1970: 1_770_000_000)

    public static func profile(onboardingCompleted: Bool = true) -> UserProfile {
        UserProfile(
            id: ownerID,
            firstName: "Jack",
            preferredDistanceUnit: .kilometres,
            preferredWeightUnit: .kilograms,
            weekStart: .monday,
            defaultDogID: roxyID,
            onboardingCompleted: onboardingCompleted
        )
    }

    public static func roxy(asOf date: Date = referenceDate) -> Dog {
        Dog(
            id: roxyID,
            name: "Roxy",
            breedName: "Belgian Malinois",
            isMixedBreed: false,
            age: .dateOfBirth(
                Calendar.current.date(byAdding: .month, value: -10, to: date) ?? date
            ),
            sex: .female,
            weightKilograms: 27,
            activityLevel: .veryActive,
            sortIndex: 0
        )
    }

    public static func bailey(asOf date: Date = referenceDate) -> Dog {
        Dog(
            id: baileyID,
            name: "Bailey",
            breedName: "German Shepherd and Husky",
            isMixedBreed: true,
            age: .estimatedMonths(15),
            sex: .female,
            weightKilograms: 21,
            activityLevel: .moderate,
            sortIndex: 1
        )
    }

    public static var dogs: [Dog] { [roxy(), bailey()] }

    public static func goals() -> [Goal] {
        [
            Goal(
                id: UUID(uuidString: "00000000-0000-0000-0000-0000000000C1")!,
                dogID: roxyID,
                goalType: .distance,
                targetValue: 30_000,
                period: .weekly,
                startDate: referenceDate.addingTimeInterval(-60 * 86_400)
            ),
            Goal(
                id: UUID(uuidString: "00000000-0000-0000-0000-0000000000C2")!,
                dogID: baileyID,
                goalType: .activeDays,
                targetValue: 5,
                period: .weekly,
                startDate: referenceDate.addingTimeInterval(-60 * 86_400)
            )
        ]
    }

    /// Eight weeks of plausible history.
    ///
    /// Not a uniform walk every day: some days have two walks, some have none,
    /// and distances vary. Perfectly regular data hides exactly the bugs that
    /// charts, streaks and "active days" calculations have — a chart that only
    /// ever sees identical bars is not really being exercised.
    public static func activities(
        endingAt endDate: Date = referenceDate,
        weeks: Int = 8,
        calendar: Calendar = .current
    ) -> [WalkActivity] {
        activitiesWithRoutes(endingAt: endDate, weeks: weeks, calendar: calendar).map(\.activity)
    }

    /// The same history, paired with the full route behind each walk.
    ///
    /// Demo mode uses this so that opening a walk shows a drawn route rather
    /// than an empty map; the plain `activities` above drops the points, which
    /// is all previews and tests need.
    public static func activitiesWithRoutes(
        endingAt endDate: Date = referenceDate,
        weeks: Int = 8,
        calendar: Calendar = .current
    ) -> [(activity: WalkActivity, route: [RoutePoint])] {
        var activities: [(activity: WalkActivity, route: [RoutePoint])] = []
        // A fixed seed keeps demo content identical between launches, so a
        // screenshot taken today matches one taken next week.
        var seed: UInt64 = 20_260_727

        func next() -> Double {
            // xorshift64: deterministic, no dependency, good enough for shaping
            // demo data. Not used for anything requiring real randomness.
            seed ^= seed << 13
            seed ^= seed >> 7
            seed ^= seed << 17
            return Double(seed % 10_000) / 10_000
        }

        let dayCount = weeks * 7
        for dayOffset in stride(from: dayCount - 1, through: 0, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -dayOffset, to: endDate) else {
                continue
            }
            let roll = next()
            // Roughly five active days in seven.
            guard roll > 0.28 else { continue }
            let walkCount = roll > 0.88 ? 2 : 1

            for walkIndex in 0..<walkCount {
                let hour = walkIndex == 0 ? 7 + Int(next() * 3) : 17 + Int(next() * 4)
                guard let start = calendar.date(
                    bySettingHour: hour,
                    minute: Int(next() * 55),
                    second: 0,
                    of: day
                ) else { continue }

                let isLongWalk = calendar.isDateInWeekend(start) && next() > 0.5
                let distance = isLongWalk
                    ? 4_500 + next() * 4_000
                    : 1_400 + next() * 2_600
                // Between 3.2 and 5.4 km/h, which is a realistic walking range.
                let speed = 0.9 + next() * 0.6
                let movingDuration = distance / speed
                let pausedDuration = next() > 0.7 ? next() * 240 : 0

                let withBailey = next() > 0.65
                let dogIDs = withBailey ? [roxyID, baileyID] : [roxyID]

                // Roughly one fix every 12 m, matching what a real recording
                // logs. Sparser than that and consecutive points sit further
                // apart than the map's 60 m gap threshold, so a continuous walk
                // would be drawn as a row of disconnected fragments.
                let route = SyntheticRoute.wander(
                    centre: Coordinate(
                        latitude: 51.5074 + (next() - 0.5) * 0.02,
                        longitude: -0.1278 + (next() - 0.5) * 0.02
                    ),
                    radiusMetres: distance / (2 * .pi),
                    pointCount: max(60, Int(distance / 12)),
                    variation: next(),
                    startingAt: start
                )

                activities.append((
                    activity: WalkActivity(
                        title: WalkTitleGenerator(calendar: calendar)
                            .title(for: start, activityType: isLongWalk ? .hike : .walk),
                        activityType: isLongWalk ? .hike : .walk,
                        startDate: start,
                        endDate: start.addingTimeInterval(movingDuration + pausedDuration),
                        elapsedDuration: movingDuration + pausedDuration,
                        movingDuration: movingDuration,
                        pausedDuration: pausedDuration,
                        distance: distance,
                        elevationGain: 8 + next() * 40,
                        dogIDs: dogIDs,
                        ownerID: ownerID,
                        recordingSource: .demo,
                        routePointCount: route.count,
                        routePreview: RoutePreview.sample(from: route),
                        createdAt: start,
                        updatedAt: start
                    ),
                    route: route
                ))
            }
        }
        return activities.sorted { $0.activity.startDate > $1.activity.startDate }
    }

    /// A ready-made in-memory store for previews.
    public static func store(
        populated: Bool = true,
        onboardingCompleted: Bool = true
    ) -> InMemoryStore {
        guard populated else {
            return InMemoryStore(profile: profile(onboardingCompleted: onboardingCompleted))
        }
        return InMemoryStore(
            profile: profile(onboardingCompleted: onboardingCompleted),
            dogs: dogs,
            activities: activities(),
            goals: goals()
        )
    }

    /// A single finished walk, for the summary and detail previews.
    public static func sampleActivity(
        startDate: Date = referenceDate.addingTimeInterval(-3_600)
    ) -> WalkActivity {
        let route = SyntheticRoute.loop(radiusMetres: 420, pointCount: 90, startingAt: startDate)
        return WalkActivity(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000D1")!,
            title: "Evening Walk",
            activityType: .walk,
            startDate: startDate,
            endDate: startDate.addingTimeInterval(2_640),
            elapsedDuration: 2_640,
            movingDuration: 2_460,
            pausedDuration: 180,
            distance: route.totalDistance,
            elevationGain: 24,
            dogIDs: [roxyID],
            ownerID: ownerID,
            notes: "Met the spaniel from number 12 again.",
            recordingSource: .demo,
            routePointCount: route.count,
            routePreview: RoutePreview.sample(from: route)
        )
    }

    public static func sampleRoute(
        startDate: Date = referenceDate.addingTimeInterval(-3_600)
    ) -> [RoutePoint] {
        SyntheticRoute.loop(radiusMetres: 420, pointCount: 90, startingAt: startDate)
    }
}
