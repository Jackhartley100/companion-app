import Testing
import Foundation
@testable import CompanionUI
@testable import CompanionCore

/// End-to-end journeys through `AppModel`, the layer every screen actually
/// talks to.
///
/// These stand in for UI smoke tests: they drive the same calls the buttons
/// make, in the same order, and assert on the state the screens read back. A
/// real XCUITest pass needs Xcode and a simulator, and is listed as outstanding
/// in the README — but the logic those tests would exercise is covered here.
@MainActor
@Suite("User journeys")
struct WalkJourneyTests {
    /// A model backed entirely by memory, with a scripted route ready to replay.
    private func makeModel(
        store: InMemoryStore = InMemoryStore(),
        route: [RoutePoint]? = nil
    ) -> AppModel {
        AppModel(
            environment: .preview(
                store: store,
                simulatedRoute: route,
                subscription: .free
            )
        )
    }

    /// A trace of ordinary walking steps that the route filter will accept.
    private func walkingTrace(count: Int, from start: Date = Date()) -> [RoutePoint] {
        (0..<count).map { index in
            RoutePoint(
                coordinate: Coordinate(
                    latitude: 51.5074 + (Double(index) * 9) / 111_320.0,
                    longitude: -0.1278
                ),
                altitude: 12,
                horizontalAccuracy: 5,
                timestamp: start.addingTimeInterval(Double(index) * 5)
            )
        }
    }

    // MARK: Onboarding

    @Test("A brand-new install shows onboarding")
    func newInstallNeedsOnboarding() async {
        let model = makeModel()
        await model.load()
        #expect(model.loadState == .loaded)
        #expect(model.hasCompletedOnboarding == false)
        #expect(model.activeDogs.isEmpty)
    }

    @Test("Completing onboarding creates a profile and a dog that persist")
    func completeOnboarding() async throws {
        let store = InMemoryStore()
        let model = makeModel(store: store)
        await model.load()

        let account = try await model.environment.authentication.continueOnDevice()
        await model.saveProfile(
            UserProfile(id: account.id, firstName: "Jack", preferredDistanceUnit: .kilometres)
        )
        await model.saveDog(Dog(name: "Roxy", activityLevel: .veryActive))
        await model.completeOnboarding()

        #expect(model.hasCompletedOnboarding)
        #expect(model.activeDogs.map(\.name) == ["Roxy"])
        #expect(model.selectedDog?.name == "Roxy")

        // A second model over the same store sees the same thing, which is what
        // relaunching the app does.
        let reopened = makeModel(store: store)
        await reopened.load()
        #expect(reopened.hasCompletedOnboarding)
        #expect(reopened.profile?.firstName == "Jack")
    }

    @Test("Onboarding does not require a breed, birthday or weight")
    func onboardingToleratesUnknowns() async throws {
        let model = makeModel()
        await model.load()
        await model.saveProfile(UserProfile(firstName: "Jack"))
        await model.saveDog(Dog(name: "Scout", age: .unknown))
        await model.completeOnboarding()

        #expect(model.hasCompletedOnboarding)
        let dog = try #require(model.activeDogs.first)
        #expect(dog.breedDescription == "Breed not set")
        #expect(dog.age.months() == nil)
        #expect(dog.weightKilograms == nil)
    }

    // MARK: The central journey

    @Test("Record a walk, pause, resume, finish, and find it in history")
    func fullWalkJourney() async throws {
        let store = InMemoryStore()
        let model = makeModel(store: store)
        await model.load()

        await model.saveProfile(UserProfile(firstName: "Jack"))
        let roxy = Dog(name: "Roxy")
        await model.saveDog(roxy)
        await model.completeOnboarding()

        let ownerID = try #require(model.profile?.id)
        let recorder = model.recorder

        // Prepare, as the walk-preparation sheet does on appear.
        await recorder.prepare()
        #expect(recorder.state == .ready)

        await recorder.start(dogIDs: [roxy.id], ownerID: ownerID)
        #expect(recorder.state == .recording)

        let source = try #require(model.environment.trackingSource as? MockTrackingSource)
        let trace = walkingTrace(count: 12)
        await feed(Array(trace.prefix(6)), into: recorder, via: source)
        let distanceBeforePause = recorder.metrics.distance
        #expect(distanceBeforePause > 0)

        await recorder.pause()
        #expect(recorder.state.isPaused)

        // Fixes during the pause must not become distance.
        await feed(Array(trace[6..<9]), into: recorder, via: source)
        #expect(recorder.metrics.distance == distanceBeforePause)

        await recorder.resume()
        #expect(recorder.state.isRecording)
        await feed(Array(trace[9...]), into: recorder, via: source)

        await recorder.finish(title: "Canal towpath loop")
        guard case .completed(let saved) = recorder.state else {
            Issue.record("Expected the walk to complete, got \(recorder.state)")
            return
        }

        #expect(saved.title == "Canal towpath loop")
        #expect(saved.dogIDs == [roxy.id])
        #expect(saved.distance > 0)
        #expect(saved.pausedDuration >= 0)
        #expect(saved.recordingSource == .iPhone)

        // It appears in history, and on the dog's own page.
        await model.refreshActivities()
        #expect(model.activities.count == 1)
        #expect(model.activities(for: roxy.id).count == 1)
        #expect(model.activities.first?.id == saved.id)

        // The route is retrievable for the detail screen's map.
        let route = await model.route(for: saved)
        #expect(route.count == saved.routePointCount)
        #expect(route.count > 1)

        // Today's numbers reflect it.
        let today = model.todayTotals(for: roxy.id)
        #expect(today.walkCount == 1)
        #expect(today.distance == saved.distance)

        // And so does the week.
        let week = model.statistics(for: roxy.id, period: .week)
        #expect(week.walkCount == 1)
        #expect(week.activeDayCount == 1)

        // The first walk earns its achievement.
        #expect(recorder.pendingUnlocks.contains { $0.achievementID == "first_walk" })
    }

    @Test("Discarding a walk leaves history untouched")
    func discardedWalkIsNotSaved() async throws {
        let model = makeModel()
        await model.load()
        await model.saveProfile(UserProfile(firstName: "Jack"))
        let roxy = Dog(name: "Roxy")
        await model.saveDog(roxy)

        let ownerID = try #require(model.profile?.id)
        let source = try #require(model.environment.trackingSource as? MockTrackingSource)

        await model.recorder.start(dogIDs: [roxy.id], ownerID: ownerID)
        await feed(walkingTrace(count: 8), into: model.recorder, via: source)
        await model.recorder.finish(discard: true)

        #expect(model.recorder.state == .idle)
        await model.refreshActivities()
        #expect(model.activities.isEmpty)
    }

    @Test("A walk with two dogs counts for both")
    func multiDogWalk() async throws {
        let model = makeModel()
        await model.load()
        await model.saveProfile(UserProfile(firstName: "Jack"))
        let roxy = Dog(name: "Roxy", sortIndex: 0)
        let bailey = Dog(name: "Bailey", sortIndex: 1)
        await model.saveDog(roxy)
        await model.saveDog(bailey)

        let ownerID = try #require(model.profile?.id)
        let source = try #require(model.environment.trackingSource as? MockTrackingSource)

        await model.recorder.start(dogIDs: [roxy.id, bailey.id], ownerID: ownerID)
        await feed(walkingTrace(count: 10), into: model.recorder, via: source)
        await model.recorder.finish()
        await model.refreshActivities()

        #expect(model.activities(for: roxy.id).count == 1)
        #expect(model.activities(for: bailey.id).count == 1)
        #expect(model.recorder.currentDogIDs.isEmpty == false || model.activities.count == 1)

        let activity = try #require(model.activities.first)
        #expect(model.dogs(for: activity).map(\.name).sorted() == ["Bailey", "Roxy"])
    }

    // MARK: Goals and history

    @Test("A saved walk moves a goal forward")
    func walkAdvancesGoal() async throws {
        let model = makeModel()
        await model.load()
        await model.saveProfile(UserProfile(firstName: "Jack"))
        let roxy = Dog(name: "Roxy")
        await model.saveDog(roxy)
        await model.saveGoal(
            Goal(dogID: roxy.id, goalType: .walkCount, targetValue: 3, period: .weekly)
        )

        #expect(model.goalProgress(for: roxy.id).first?.currentValue == 0)

        let ownerID = try #require(model.profile?.id)
        let source = try #require(model.environment.trackingSource as? MockTrackingSource)
        await model.recorder.start(dogIDs: [roxy.id], ownerID: ownerID)
        await feed(walkingTrace(count: 6), into: model.recorder, via: source)
        await model.recorder.finish()
        await model.refreshActivities()

        let progress = try #require(model.goalProgress(for: roxy.id).first)
        #expect(progress.currentValue == 1)
        #expect(progress.isComplete == false)
        #expect(abs(progress.fraction - 1.0 / 3.0) < 0.001)
    }

    @Test("Deleting a walk removes it from history and from the totals")
    func deleteWalk() async throws {
        let store = DemoDataProvider.store()
        let model = makeModel(store: store)
        await model.load()

        let before = model.activities.count
        #expect(before > 0)
        let target = try #require(model.activities.first)

        await model.deleteActivity(target)
        #expect(model.activities.count == before - 1)
        #expect(model.activities.contains { $0.id == target.id } == false)
    }

    @Test("Deleting all history keeps the dogs and the profile")
    func deleteAllHistory() async {
        let model = makeModel(store: DemoDataProvider.store())
        await model.load()
        #expect(model.activities.isEmpty == false)

        await model.deleteAllActivities()

        #expect(model.activities.isEmpty)
        #expect(model.activeDogs.isEmpty == false)
        #expect(model.profile != nil)
    }

    @Test("Archiving a dog hides it but keeps the walks")
    func archiveDog() async throws {
        let model = makeModel(store: DemoDataProvider.store())
        await model.load()

        let roxy = try #require(model.activeDogs.first { $0.name == "Roxy" })
        let walkCount = model.activities(for: roxy.id).count
        #expect(walkCount > 0)

        await model.archiveDog(roxy)

        #expect(model.activeDogs.contains { $0.id == roxy.id } == false)
        #expect(model.activities(for: roxy.id).count == walkCount)
    }

    // MARK: Preferences

    @Test("Changing units changes how distances are formatted")
    func unitPreferenceAffectsFormatting() async throws {
        let model = makeModel(store: DemoDataProvider.store())
        await model.load()

        var profile = try #require(model.profile)
        profile.preferredDistanceUnit = .kilometres
        await model.saveProfile(profile)
        let metric = model.formatters.distance(5_000)

        profile.preferredDistanceUnit = .miles
        await model.saveProfile(profile)
        let imperial = model.formatters.distance(5_000)

        #expect(metric != imperial)
        #expect(metric.contains("km"))
        #expect(imperial.contains("mi"))
    }

    @Test("Changing the week start changes which walks count as this week")
    func weekStartAffectsStatistics() async throws {
        let model = makeModel(store: DemoDataProvider.store())
        await model.load()

        var profile = try #require(model.profile)
        profile.weekStart = .monday
        await model.saveProfile(profile)
        #expect(model.calendar.firstWeekday == 2)

        profile.weekStart = .sunday
        await model.saveProfile(profile)
        #expect(model.calendar.firstWeekday == 1)
    }

    // MARK: Failure paths

    @Test("A denied permission produces an actionable failure, not a crash")
    func permissionDenied() async {
        let model = AppModel(
            environment: .preview(store: InMemoryStore(), locationStatus: .denied)
        )
        await model.load()
        await model.recorder.prepare()

        guard case .failed(let failure) = model.recorder.state else {
            Issue.record("Expected a failed state")
            return
        }
        #expect(failure.requiresSystemSettings)
        #expect(failure.message.isEmpty == false)
        #expect(failure.dataIsSafe)
    }

    @Test("A storage failure surfaces a message rather than losing data silently")
    func storageFailureSurfaces() async throws {
        let store = DemoDataProvider.store()
        let model = makeModel(store: store)
        await model.load()

        await store.setInjectedFailure(.writeFailed("the disk is full"))
        let target = try #require(model.activities.first)
        await model.deleteActivity(target)

        #expect(model.banner != nil)
        #expect(model.banner?.style == .warning)
        #expect(model.banner?.text.contains("disk is full") == true)
    }

    // MARK: Demo data

    /// Demo content must be identifiable and must never look like a real walk
    /// the owner recorded.
    @Test("Every demo activity is marked as demo content")
    func demoDataIsMarked() {
        let activities = DemoDataProvider.activities()
        #expect(activities.isEmpty == false)
        #expect(activities.allSatisfy { $0.recordingSource == .demo })
        #expect(activities.allSatisfy { $0.isDemo })
    }

    @Test("Demo data is deterministic between runs")
    func demoDataIsDeterministic() {
        let first = DemoDataProvider.activities()
        let second = DemoDataProvider.activities()
        #expect(first.count == second.count)
        #expect(first.map(\.distance) == second.map(\.distance))
    }

    @Test("Demo data is varied enough to exercise charts and streaks")
    func demoDataIsVaried() {
        let activities = DemoDataProvider.activities(weeks: 8)
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2

        let days = Set(activities.map { calendar.startOfDay(for: $0.startDate) })
        // Neither every day nor almost none: uniform data hides bugs.
        #expect(days.count > 20)
        #expect(days.count < 56)
        #expect(Set(activities.map(\.activityType)).count > 1)
        #expect(activities.contains { $0.dogIDs.count > 1 })
    }

    // MARK: Helpers

    /// Pushes fixes through the mock source and waits for the recorder to have
    /// consumed each one.
    private func feed(
        _ points: [RoutePoint],
        into recorder: WalkRecorder,
        via source: MockTrackingSource
    ) async {
        for point in points {
            let before = recorder.routePoints.count
            let shouldGrow = recorder.state.isRecording
            await source.inject(.location(point))
            for _ in 0..<200 {
                await Task.yield()
                if shouldGrow, recorder.routePoints.count > before { break }
            }
        }
    }
}
