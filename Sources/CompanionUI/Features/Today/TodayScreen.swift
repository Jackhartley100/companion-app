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

                    if let dog = model.selectedDog {
                        goalSection(for: dog)
                        insightSection(for: dog)
                        weeklySection(for: dog)
                        recentSection(for: dog)
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
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            now = Date()
            Task { await model.refreshActivities() }
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
        let totals = model.todayTotals(for: model.selectedDogID, now: now)
        let streak = model.streak(for: model.selectedDogID, now: now)

        return Card {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                HStack(alignment: .top) {
                    MetricCard(
                        value: formatters.distanceValue(totals.distance),
                        unit: formatters.distanceUnitLabel,
                        label: "Today",
                        symbolName: "figure.walk",
                        accessibleValue: formatters.accessibleDistance(totals.distance)
                    )
                    MetricCard(
                        value: formatters.duration(totals.duration),
                        label: "Time",
                        symbolName: "clock",
                        accessibleValue: formatters.spelledDuration(totals.duration)
                    )
                    MetricCard(
                        value: "\(totals.walkCount)",
                        label: totals.walkCount == 1 ? "Walk" : "Walks",
                        symbolName: "checkmark.circle"
                    )
                }

                if streak.current >= 2 {
                    Label(
                        "\(streak.current) days in a row",
                        systemImage: "flame.fill"
                    )
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.Colour.secondaryAccent)
                }

                PrimaryButton("Start Walk", symbolName: "figure.walk", action: startWalk)
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
        case .celebration: Theme.Colour.secondaryAccent
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

    @ViewBuilder
    private func recentSection(for dog: Dog) -> some View {
        let recent = model.activities(for: dog.id).first

        VStack(alignment: .leading, spacing: Theme.Space.m) {
            SectionHeader("Latest walk")

            if let recent {
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
