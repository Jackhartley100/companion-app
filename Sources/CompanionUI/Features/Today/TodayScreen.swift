import SwiftUI
import CompanionCore

/// The daily overview, and the most-used screen in the app.
///
/// It answers three questions in the first two seconds: which dog this is about,
/// what has happened today, and where to tap to start a walk.
struct TodayScreen: View {
    let startWalk: () -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.formatters) private var formatters
    @Environment(\.companionCalendar) private var calendar

    @Environment(\.scenePhase) private var scenePhase

    /// The moment "today" and the greeting are computed against.
    ///
    /// Refreshed whenever the app comes back to the foreground, so leaving
    /// Companion open overnight does not leave yesterday's totals on screen
    /// labelled "Today".
    @State private var now = Date()

    var body: some View {
        @Bindable var model = model

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.xl) {
                    header

                    if model.activeDogs.count > 1 {
                        DogSelector(
                            dogs: model.activeDogs,
                            selection: $model.selectedDogID,
                            imageStore: model.environment.imageStore
                        )
                    }

                    todayCard
                    metricsSection
                    weatherSection

                    if let dog = model.selectedDog {
                        recentSection(for: dog)
                        goalSection(for: dog)
                        insightSection(for: dog)
                        weeklySection(for: dog)
                    }
                }
                .padding(.horizontal, Theme.Space.l)
                .padding(.bottom, Theme.Space.xxl)
            }
            .background(Theme.Colour.groupedBackground)
            .navigationTitle("Today")
            .largeNavigationTitle()
            .navigationDestination(for: TodayRoute.self) { route in
                switch route {
                case .statistics:
                    StatisticsScreen(dogID: model.selectedDogID)
                case .activity(let activity):
                    ActivityDetailScreen(activity: activity)
                case .goals:
                    GoalsScreen(dogID: model.selectedDogID)
                case .achievements:
                    AchievementsScreen(dogID: model.selectedDogID)
                }
            }
        }
        .task { await model.loadWeather() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            now = Date()
            Task {
                await model.refreshActivities()
                await model.loadWeather()
            }
        }
    }

    enum TodayRoute: Hashable {
        case statistics
        case activity(WalkActivity)
        case goals
        case achievements
    }

    // MARK: Sections

    private var header: some View {
        HStack(alignment: .center, spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(greeting)
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colour.secondaryText)
                if let dog = model.selectedDog {
                    Text("You and \(dog.name)")
                        .font(.title2.weight(.bold))
                }
            }
            Spacer(minLength: 0)
            if let dog = model.selectedDog {
                DogAvatar(dog: dog, size: 52, imageStore: model.environment.imageStore)
            }
        }
        .padding(.top, Theme.Space.s)
        .accessibilityElement(children: .combine)
    }

    private var greeting: String {
        let name = model.profile?.firstName ?? ""
        let hour = calendar.component(.hour, from: now)
        let timeOfDay = switch hour {
        case 5..<12: "Good morning"
        case 12..<18: "Good afternoon"
        default: "Good evening"
        }
        return name.isEmpty ? timeOfDay : "\(timeOfDay), \(name)"
    }

    private var todayCard: some View {
        let streak = model.streak(for: model.selectedDogID, now: now)

        return Card {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                if streak.current >= 2 {
                    Label(
                        "\(streak.current) days in a row",
                        systemImage: "flame.fill"
                    )
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.Colour.accent)
                }

                PrimaryButton("Start Walk", symbolName: "figure.walk", action: startWalk)
            }
        }
    }

    /// Today's headline numbers as a horizontal strip of individually-carded
    /// widgets, rather than the single combined card `todayCard` used to show
    /// them in — each metric now reads as its own glanceable tile instead of
    /// three columns competing inside one container.
    private var metricsSection: some View {
        let totals = model.todayTotals(for: model.selectedDogID, now: now)
        let distanceGoal = model.goalProgress(for: model.selectedDogID, now: now)
            .first { $0.goal.goalType == .distance }

        return VStack(alignment: .leading, spacing: Theme.Space.m) {
            SectionHeader("Today's metrics")

            HStack(spacing: Theme.Space.m) {
                RingMetricCard(
                    value: formatters.distanceValue(totals.distance),
                    target: distanceGoal.map {
                        formatters.distanceValue($0.goal.targetValue) + formatters.distanceUnitLabel
                    },
                    label: "Distance",
                    symbolName: "figure.walk",
                    tint: Theme.Colour.accent,
                    accessibleValue: formatters.accessibleDistance(totals.distance)
                )
                RingMetricCard(
                    value: formatters.duration(totals.duration),
                    label: "Time walked",
                    symbolName: "clock.fill",
                    tint: Theme.Colour.route,
                    accessibleValue: formatters.spelledDuration(totals.duration)
                )
                RingMetricCard(
                    value: "\(totals.walkCount)",
                    label: totals.walkCount == 1 ? "Walk" : "Walks",
                    symbolName: "checkmark.circle.fill",
                    tint: Theme.Colour.secondaryAccent
                )
            }
        }
    }

    /// Current conditions where the owner is right now, plus a suggested time
    /// to walk today. Both come from `AppModel.loadWeather()`, which quietly
    /// does nothing when there's no location fix or no weather entitlement —
    /// so this section just as quietly disappears rather than showing an
    /// error or a placeholder for a feature that isn't available.
    @ViewBuilder
    private var weatherSection: some View {
        let suggestion = model.walkTimeSuggestion(for: model.selectedDogID, now: now)

        if model.currentWeather != nil || suggestion != nil {
            Card {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    if let weather = model.currentWeather {
                        HStack(spacing: Theme.Space.m) {
                            Image(systemName: weather.condition.symbolName)
                                .font(.title2)
                                .foregroundStyle(Theme.Colour.accent)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                                Text("\(Int(weather.temperatureCelsius.rounded()))°C, \(weather.condition.displayName)")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.Colour.primaryText)
                                Text("Where you are right now")
                                    .font(.caption)
                                    .foregroundStyle(Theme.Colour.secondaryText)
                            }
                        }

                        if suggestion != nil {
                            Divider().overlay(Theme.Colour.separator)
                        }
                    }

                    if let suggestion {
                        HStack(alignment: .top, spacing: Theme.Space.m) {
                            Image(systemName: suggestion.symbolName)
                                .foregroundStyle(
                                    suggestion.tone == .good ? Theme.Colour.success : Theme.Colour.warning
                                )
                                .frame(width: 28)
                            Text(suggestion.text)
                                .font(.subheadline)
                                .foregroundStyle(Theme.Colour.primaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func goalSection(for dog: Dog) -> some View {
        let progress = model.goalProgress(for: dog.id, now: now)
        if let first = progress.first {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                NavigationLink(value: TodayRoute.goals) {
                    SectionHeader("Goal")
                }
                .buttonStyle(.plain)

                Card { GoalProgressCard(progress: first, dogName: dog.name) }
            }
        } else {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                SectionHeader("Goal")
                Card {
                    VStack(alignment: .leading, spacing: Theme.Space.m) {
                        Text("No goal set for \(dog.name) yet.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.Colour.secondaryText)
                        NavigationLink(value: TodayRoute.goals) {
                            Text("Set a goal")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.Colour.accent)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func insightSection(for dog: Dog) -> some View {
        let insights = model.insights(for: dog, now: now)
        if !insights.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                SectionHeader("Worth knowing")
                Card {
                    VStack(alignment: .leading, spacing: Theme.Space.m) {
                        ForEach(insights) { insight in
                            HStack(alignment: .top, spacing: Theme.Space.m) {
                                Image(systemName: insight.symbolName)
                                    .foregroundStyle(tint(for: insight.tone))
                                    .frame(width: 22)
                                    .accessibilityHidden(true)
                                Text(insight.text)
                                    .font(.subheadline)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
        }
    }

    private func tint(for tone: Insight.Tone) -> Color {
        switch tone {
        case .observation: Theme.Colour.accent
        case .encouragement: Theme.Colour.accent
        case .celebration: Theme.Colour.accent
        }
    }

    private func weeklySection(for dog: Dog) -> some View {
        let statistics = model.statistics(for: dog.id, period: .week, now: now)
        return VStack(alignment: .leading, spacing: Theme.Space.m) {
            SectionHeader("This week")
            NavigationLink(value: TodayRoute.statistics) {
                Card { WeeklyActivityChart(statistics: statistics) }
            }
            .buttonStyle(.plain)
        }
    }

    /// The walk shown just under the metrics: the most eye-catching one from
    /// the last few days if there is a clear standout, otherwise simply the
    /// latest — so a short evening stroll doesn't bump yesterday's long
    /// weekend hike off screen the moment it's logged.
    private func featuredActivity(for dogID: UUID?) -> (activity: WalkActivity, isLatest: Bool)? {
        let recent = model.activities(for: dogID)
        guard let latest = recent.first else { return nil }

        let window = calendar.date(byAdding: .day, value: -3, to: now) ?? now
        let standout = recent
            .filter { $0.startDate >= window }
            .max { $0.distance < $1.distance }

        guard let standout, standout.id != latest.id, standout.distance > latest.distance * 1.4 else {
            return (latest, true)
        }
        return (standout, false)
    }

    @ViewBuilder
    private func recentSection(for dog: Dog) -> some View {
        let featured = featuredActivity(for: dog.id)

        VStack(alignment: .leading, spacing: Theme.Space.m) {
            SectionHeader(featured?.isLatest == false ? "Recent highlight" : "Latest walk")

            if let recent = featured?.activity {
                NavigationLink(value: TodayRoute.activity(recent)) {
                    Card {
                        VStack(alignment: .leading, spacing: Theme.Space.m) {
                            RoutePreviewCard(coordinates: recent.routePreview, height: 150)
                            ActivityRow(
                                activity: recent,
                                dogs: model.dogs(for: recent),
                                imageStore: model.environment.imageStore,
                                hasAchievement: model.hasAchievement(for: recent.id)
                            )
                        }
                    }
                }
                .buttonStyle(.plain)
            } else {
                Card {
                    EmptyStateView(
                        symbolName: "figure.walk.motion",
                        title: "No walks yet",
                        message: "Once you record a walk it will appear here, "
                            + "with the route you took and how far you went.",
                        actionTitle: "Start \(dog.name)'s first walk",
                        action: startWalk
                    )
                }
            }
        }
    }
}

struct TodayScreen_Previews: PreviewProvider {
    static var previews: some View {
        PreviewHost { TodayScreen(startWalk: {}) }
            .previewDisplayName("Populated")

        PreviewHost(
            store: InMemoryStore(
                profile: DemoDataProvider.profile(),
                dogs: [DemoDataProvider.roxy()],
                goals: DemoDataProvider.goals()
            )
        ) { TodayScreen(startWalk: {}) }
            .previewDisplayName("New owner — no walks")

        PreviewHost { TodayScreen(startWalk: {}) }
            .preferredColorScheme(.dark)
            .previewDisplayName("Dark")

        PreviewHost { TodayScreen(startWalk: {}) }
            .environment(\.sizeCategory, .accessibilityLarge)
            .previewDisplayName("Large text")
    }
}
