import SwiftUI
import Observation
import CompanionCore

/// The app's loaded state, and the actions that change it.
///
/// One model rather than one per screen: dogs, activities and goals are read by
/// almost every screen, and duplicating that loading per view leads to screens
/// disagreeing about what the owner just did. It stays a coordinator — every
/// calculation lives in `CompanionCore`, and nothing here does arithmetic on a
/// route.
@MainActor
@Observable
public final class AppModel {
    public enum LoadState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    // MARK: Loaded data

    public private(set) var loadState: LoadState = .loading
    public private(set) var profile: UserProfile?
    public private(set) var dogs: [Dog] = []
    public private(set) var activities: [WalkActivity] = []
    public private(set) var goals: [Goal] = []
    public private(set) var unlocks: [AchievementUnlock] = []

    /// The dog the app is currently talking about.
    public var selectedDogID: UUID? {
        didSet {
            guard oldValue != selectedDogID else { return }
            Task { await persistSelectedDog() }
        }
    }

    /// Writes the selected dog into the stored profile.
    ///
    /// The profile is re-read here rather than captured in the `didSet`. A
    /// captured copy is a stale snapshot by the time the task runs, and it will
    /// happily overwrite any field changed in between — which is how selecting a
    /// dog during onboarding was able to clobber `onboardingCompleted` and drop
    /// the owner back to the welcome screen on next launch.
    private func persistSelectedDog() async {
        guard var profile, profile.defaultDogID != selectedDogID else { return }
        profile.defaultDogID = selectedDogID
        await saveProfile(profile)
    }

    /// A non-fatal problem worth telling the owner about, without losing the screen.
    public var banner: BannerMessage?

    public let environment: AppEnvironment
    public let recorder: WalkRecorder

    public init(environment: AppEnvironment) {
        self.environment = environment
        self.recorder = environment.makeRecorder(calendar: .current)
    }

    // MARK: Derived values

    public var calendar: Calendar {
        StatisticsEngine.calendar(for: profile?.weekStart ?? .system)
    }

    public var formatters: Formatters {
        Formatters(
            distanceUnit: profile?.preferredDistanceUnit ?? .default(),
            weightUnit: profile?.preferredWeightUnit ?? .default()
        )
    }

    public var activeDogs: [Dog] { dogs.filter { !$0.isArchived } }

    public var selectedDog: Dog? {
        guard let selectedDogID else { return activeDogs.first }
        return activeDogs.first { $0.id == selectedDogID } ?? activeDogs.first
    }

    public var hasCompletedOnboarding: Bool {
        profile?.onboardingCompleted == true && !activeDogs.isEmpty
    }

    /// Activities that the given dog came on, newest first.
    public func activities(for dogID: UUID?) -> [WalkActivity] {
        guard let dogID else { return activities }
        return activities.filter { $0.dogIDs.contains(dogID) }
    }

    public func dogs(for activity: WalkActivity) -> [Dog] {
        activity.dogIDs.compactMap { id in dogs.first { $0.id == id } }
    }

    public func statistics(for dogID: UUID?, period: StatisticsPeriod, now: Date = Date()) -> PeriodStatistics {
        StatisticsEngine(calendar: calendar)
            .statistics(for: activities(for: dogID), period: period, containing: now)
    }

    public func todayTotals(for dogID: UUID?, now: Date = Date()) -> DailyTotals {
        StatisticsEngine(calendar: calendar).today(for: activities(for: dogID), date: now)
    }

    public func streak(for dogID: UUID?, now: Date = Date()) -> Streak {
        StreakCalculator(calendar: calendar).streak(for: activities(for: dogID), asOf: now)
    }

    public func goals(for dogID: UUID?) -> [Goal] {
        goals.filter { $0.isActive && ($0.dogID == dogID || $0.dogID == nil) }
    }

    public func goalProgress(for dogID: UUID?, now: Date = Date()) -> [GoalProgress] {
        GoalEvaluator(calendar: calendar)
            .progress(for: goals(for: dogID), activities: activities, asOf: now)
    }

    public func insights(for dog: Dog?, now: Date = Date()) -> [Insight] {
        guard let dog else { return [] }
        return InsightEngine(calendar: calendar, formatters: formatters).insights(
            dogName: dog.name,
            activities: activities(for: dog.id),
            goalProgress: goalProgress(for: dog.id, now: now),
            streak: streak(for: dog.id, now: now),
            now: now
        )
    }

    public func achievementStatuses(for dogID: UUID?, now: Date = Date()) -> [AchievementStatus] {
        AchievementEngine(calendar: calendar).statuses(
            context: AchievementContext(
                activities: activities(for: dogID),
                goalProgress: goalProgress(for: dogID, now: now),
                streak: streak(for: dogID, now: now),
                dogID: dogID
            ),
            existing: unlocks
        )
    }

    public func hasAchievement(for activityID: UUID) -> Bool {
        unlocks.contains { $0.walkID == activityID }
    }

    // MARK: Loading

    public func load() async {
        loadState = .loading
        do {
            let profile = try await environment.profileRepository.load()
            async let dogs = environment.dogRepository.all()
            async let activities = environment.activityRepository.activities(matching: .all)
            async let goals = environment.goalRepository.activeGoals()
            async let unlocks = environment.achievementRepository.unlocks()

            self.profile = profile
            self.dogs = try await dogs
            self.activities = try await activities
            self.goals = try await goals
            self.unlocks = try await unlocks
            self.selectedDogID = profile?.defaultDogID ?? self.activeDogs.first?.id
            loadState = .loaded
        } catch let error as RepositoryError {
            loadState = .failed(error.userMessage)
        } catch {
            loadState = .failed(error.localizedDescription)
        }

        await recorder.checkForRecoverableSession()
    }

    /// Reloads only the activity-derived data, after a walk is saved or deleted.
    public func refreshActivities() async {
        do {
            activities = try await environment.activityRepository.activities(matching: .all)
            unlocks = try await environment.achievementRepository.unlocks()
        } catch let error as RepositoryError {
            banner = BannerMessage(text: error.userMessage, style: .warning)
        } catch {
            banner = BannerMessage(text: error.localizedDescription, style: .warning)
        }
    }

    // MARK: Mutations

    /// Serialises profile writes.
    ///
    /// The profile is edited from several places at once — the settings
    /// pickers, the dog selector's `didSet`, and onboarding — and each does a
    /// read, a change and a write. Without ordering, two of those overlapping
    /// means the slower write lands last and silently reverts the other's
    /// change. That is how completing onboarding could be undone by the dog
    /// selection that happened moments earlier.
    private var profileWriteTask: Task<Void, Never>?

    public func saveProfile(_ profile: UserProfile) async {
        // Assigned before any suspension, so the next read-modify-write in this
        // turn already sees this change and builds on it rather than on a stale
        // copy.
        self.profile = profile

        let previous = profileWriteTask
        let task = Task { [weak self] in
            // Waiting on the previous write is what guarantees the store ends up
            // with the newest version rather than whichever write finished last.
            await previous?.value
            guard let self else { return }
            do {
                try await self.environment.profileRepository.save(profile)
            } catch {
                self.banner = BannerMessage(text: self.message(for: error), style: .warning)
            }
        }
        profileWriteTask = task
        await task.value
    }

    public func completeOnboarding() async {
        guard var profile else { return }
        profile.onboardingCompleted = true
        environment.analytics.track(.onboardingCompleted)
        await saveProfile(profile)
    }

    public func saveDog(_ dog: Dog) async {
        do {
            try await environment.dogRepository.save(dog)
            dogs = try await environment.dogRepository.all()
            if selectedDogID == nil { selectedDogID = dog.id }
        } catch {
            banner = BannerMessage(text: message(for: error), style: .warning)
        }
    }

    public func archiveDog(_ dog: Dog) async {
        var updated = dog
        updated.isArchived = true
        await saveDog(updated)
        if selectedDogID == dog.id { selectedDogID = activeDogs.first?.id }
    }

    public func saveGoal(_ goal: Goal) async {
        do {
            try await environment.goalRepository.save(goal)
            goals = try await environment.goalRepository.activeGoals()
            environment.analytics.track(
                .goalCreated(type: goal.goalType.rawValue, period: goal.period.rawValue)
            )
        } catch {
            banner = BannerMessage(text: message(for: error), style: .warning)
        }
    }

    public func deleteGoal(_ goal: Goal) async {
        do {
            try await environment.goalRepository.delete(id: goal.id)
            goals = try await environment.goalRepository.activeGoals()
        } catch {
            banner = BannerMessage(text: message(for: error), style: .warning)
        }
    }

    public func updateActivity(_ activity: WalkActivity) async {
        do {
            try await environment.activityRepository.save(activity, route: nil)
            await refreshActivities()
        } catch {
            banner = BannerMessage(text: message(for: error), style: .warning)
        }
    }

    public func deleteActivity(_ activity: WalkActivity) async {
        do {
            try await environment.activityRepository.delete(id: activity.id)
            await refreshActivities()
        } catch {
            banner = BannerMessage(text: message(for: error), style: .warning)
        }
    }

    public func deleteAllActivities() async {
        do {
            try await environment.activityRepository.deleteAll()
            await refreshActivities()
            banner = BannerMessage(text: "Your activity history has been deleted.", style: .info)
        } catch {
            banner = BannerMessage(text: message(for: error), style: .warning)
        }
    }

    public func route(for activity: WalkActivity) async -> [RoutePoint] {
        (try? await environment.activityRepository.route(for: activity.id)) ?? []
    }

    /// Signs out and returns the app to onboarding.
    ///
    /// There is no backend yet — `AuthenticationProvider.localDevice.isRecoverable`
    /// is `false` — so a local-only account has nothing to sign back into
    /// elsewhere. The only honest behaviour is a full local reset: profile, dogs
    /// and every walk are removed from this device, exactly as a fresh install
    /// would be. The confirmation shown before calling this must say so plainly,
    /// since it is destructive and irreversible.
    public func signOut() async {
        do {
            try await environment.profileRepository.deleteEverything()
            try? await environment.authentication.signOut()
            profile = nil
            dogs = []
            activities = []
            goals = []
            unlocks = []
            // Set after `profile = nil` so the `didSet` below finds nothing to
            // persist, rather than racing to write a dog ID onto a profile that
            // no longer exists.
            selectedDogID = nil
            recorder.reset()
            loadState = .loaded
        } catch {
            banner = BannerMessage(text: message(for: error), style: .warning)
        }
    }

    public func acknowledgeUnlocks(_ unlocks: [AchievementUnlock]) async {
        guard !unlocks.isEmpty else { return }
        try? await environment.achievementRepository.acknowledge(ids: unlocks.map(\.id))
        self.unlocks = (try? await environment.achievementRepository.unlocks()) ?? self.unlocks
    }

    private func message(for error: Error) -> String {
        (error as? RepositoryError)?.userMessage ?? error.localizedDescription
    }
}

/// A transient message shown at the top of a screen.
public struct BannerMessage: Identifiable, Equatable {
    public enum Style: Equatable {
        case info
        case warning
        case success
    }

    public let id = UUID()
    public let text: String
    public let style: Style

    public init(text: String, style: Style) {
        self.text = text
        self.style = style
    }

    var tint: Color {
        switch style {
        case .info: Theme.Colour.accent
        case .warning: Theme.Colour.warning
        case .success: Theme.Colour.success
        }
    }

    var symbolName: String {
        switch style {
        case .info: "info.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .success: "checkmark.circle.fill"
        }
    }
}

struct BannerView: View {
    let message: BannerMessage
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.s) {
            Image(systemName: message.symbolName)
                .foregroundStyle(message.tint)
            Text(message.text)
                .font(.footnote)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.Colour.secondaryText)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(Theme.Space.m)
        .background(message.tint.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
        .padding(.horizontal, Theme.Space.l)
        .accessibilityElement(children: .combine)
    }
}
