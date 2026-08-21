import SwiftUI
import CompanionCore

/// The walk history.
struct ActivitiesScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.formatters) private var formatters
    @Environment(\.companionCalendar) private var calendar

    @State private var searchText = ""
    @State private var dogFilter: UUID?
    @State private var typeFilter: ActivityType?

    var body: some View {
        NavigationStack {
            Group {
                switch model.loadState {
                case .loading:
                    LoadingStateView(message: "Loading your walks")
                case .failed(let message):
                    ErrorStateView(
                        title: "Your walks could not be loaded",
                        message: message,
                        reassurance: "Nothing has been deleted.",
                        retry: { Task { await model.load() } }
                    )
                case .loaded:
                    content
                }
            }
            .navigationTitle("Activities")
            .largeNavigationTitle()
            .searchable(text: $searchText, prompt: "Search walks")
            .toolbar { photosButton; filterMenu }
            .navigationDestination(for: WalkActivity.self) { ActivityDetailScreen(activity: $0) }
            .navigationDestination(for: StatisticsRoute.self) { _ in
                StatisticsScreen(dogID: dogFilter)
            }
            .navigationDestination(for: PhotosRoute.self) { _ in
                WalkPhotosGalleryScreen()
            }
        }
    }

    struct StatisticsRoute: Hashable {}
    struct PhotosRoute: Hashable {}

    private var photosButton: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            NavigationLink(value: PhotosRoute()) {
                Label("Walk Photos", systemImage: "photo.on.rectangle.angled")
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.activities.isEmpty {
            EmptyStateView(
                symbolName: "list.bullet.rectangle",
                title: "No walks yet",
                message: "Every walk you record will be kept here, "
                    + "with its route, distance and time."
            )
        } else if filtered.isEmpty {
            EmptyStateView(
                symbolName: "magnifyingglass",
                title: "Nothing matches",
                message: "Try a different search, or clear the filters.",
                actionTitle: "Clear filters",
                action: clearFilters
            )
        } else {
            List {
                Section {
                    NavigationLink(value: StatisticsRoute()) {
                        summaryRow
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                ForEach(months, id: \.self) { month in
                    Section(formatters.monthAndYear(month)) {
                        ForEach(activities(in: month)) { activity in
                            NavigationLink(value: activity) {
                                ActivityRow(
                                    activity: activity,
                                    dogs: model.dogs(for: activity),
                                    imageStore: model.environment.imageStore,
                                    hasAchievement: model.hasAchievement(for: activity.id)
                                )
                            }
                        }
                        .onDelete { offsets in
                            delete(offsets, in: month)
                        }
                    }
                }
            }
            .groupedListStyle()
        }
    }

    /// The same per-metric ring-card treatment as Today's metric strip, so the
    /// two most-visited screens read as one family rather than the list
    /// falling back to a plainer, pre-redesign row style.
    private var summaryRow: some View {
        let total = filtered.reduce(0) { $0 + $1.distance }
        let duration = filtered.reduce(0) { $0 + $1.movingDuration }
        return HStack(spacing: Theme.Space.m) {
            RingMetricCard(
                value: formatters.distanceValue(total),
                target: nil,
                label: "Distance",
                symbolName: "figure.walk",
                tint: Theme.Colour.accent,
                accessibleValue: formatters.accessibleDistance(total)
            )
            RingMetricCard(
                value: formatters.duration(duration),
                label: "Time",
                symbolName: "clock.fill",
                tint: Theme.Colour.route,
                accessibleValue: formatters.spelledDuration(duration)
            )
            RingMetricCard(
                value: "\(filtered.count)",
                label: filtered.count == 1 ? "Walk" : "Walks",
                symbolName: "checkmark.circle.fill",
                tint: Theme.Colour.secondaryAccent
            )
        }
        .padding(.vertical, Theme.Space.xs)
    }

    private var filterMenu: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Picker("Dog", selection: $dogFilter) {
                    Text("All dogs").tag(UUID?.none)
                    ForEach(model.activeDogs) { Text($0.name).tag(UUID?.some($0.id)) }
                }
                Picker("Type", selection: $typeFilter) {
                    Text("All types").tag(ActivityType?.none)
                    ForEach(ActivityType.allCases) {
                        Text($0.displayName).tag(ActivityType?.some($0))
                    }
                }
                if hasActiveFilters {
                    Button("Clear filters", systemImage: "xmark.circle", action: clearFilters)
                }
            } label: {
                Label(
                    "Filter",
                    systemImage: hasActiveFilters
                        ? "line.3.horizontal.decrease.circle.fill"
                        : "line.3.horizontal.decrease.circle"
                )
            }
        }
    }

    private var hasActiveFilters: Bool {
        dogFilter != nil || typeFilter != nil
    }

    private func clearFilters() {
        dogFilter = nil
        typeFilter = nil
        searchText = ""
    }

    /// Filtering goes through the same `ActivityQuery` the repositories use, so
    /// on-screen results cannot diverge from what a fetch would return.
    private var filtered: [WalkActivity] {
        let query = ActivityQuery(
            dogID: dogFilter,
            activityType: typeFilter,
            searchText: searchText.isEmpty ? nil : searchText
        )
        return model.activities.filter(query.matches)
    }

    private var months: [Date] {
        var seen: [Date] = []
        for activity in filtered {
            let month = calendar.startOfMonth(for: activity.startDate)
            if !seen.contains(month) { seen.append(month) }
        }
        return seen
    }

    private func activities(in month: Date) -> [WalkActivity] {
        filtered.filter { calendar.startOfMonth(for: $0.startDate) == month }
    }

    private func delete(_ offsets: IndexSet, in month: Date) {
        let monthActivities = activities(in: month)
        let toDelete = offsets.map { monthActivities[$0] }
        Task {
            for activity in toDelete {
                await model.deleteActivity(activity)
            }
        }
    }
}

struct ActivitiesScreen_Previews: PreviewProvider {
    static var previews: some View {
        PreviewHost { ActivitiesScreen() }
            .previewDisplayName("Populated")

        PreviewHost(store: DemoDataProvider.store(populated: false)) { ActivitiesScreen() }
            .previewDisplayName("Empty")

        PreviewHost { ActivitiesScreen() }
            .preferredColorScheme(.dark)
            .previewDisplayName("Dark")

        PreviewHost { ActivitiesScreen() }
            .environment(\.sizeCategory, .accessibilityLarge)
            .previewDisplayName("Large text")
    }
}
