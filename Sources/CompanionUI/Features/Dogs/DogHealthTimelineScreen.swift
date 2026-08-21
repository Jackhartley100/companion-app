import SwiftUI
import Charts
import CompanionCore

/// What walking has added up to for one dog, and when it happened.
///
/// This is deliberately a picture of *activity over time*, not a health
/// assessment. Companion has no vet data and no hardware on the dog itself —
/// see `RecordingSource.measuresDogDirectly` — so nothing here diagnoses or
/// scores anything. It shows what the owner's own history says: how much
/// walking there has been, whether it is trending up or down, and the
/// moments — records, streaks, achievements — worth remembering along the
/// way. That is a true and motivating story to tell without ever implying a
/// clinical one.
struct DogHealthTimelineScreen: View {
    let dog: Dog

    @Environment(AppModel.self) private var model
    @Environment(\.formatters) private var formatters
    @Environment(\.companionCalendar) private var calendar

    private var activities: [WalkActivity] {
        model.activities(for: dog.id).sorted { $0.startDate < $1.startDate }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                intro
                if activities.isEmpty {
                    EmptyStateView(
                        symbolName: "heart.text.square",
                        title: "Nothing to show yet",
                        message: "Once you've recorded a few walks with \(dog.name), "
                            + "this page fills in with their activity over time."
                    )
                } else {
                    lifetimeCard
                    monthlyChart
                    timeline
                }
            }
            .padding(Theme.Space.l)
        }
        .background(Theme.Colour.groupedBackground)
        .navigationTitle("\(dog.name)'s Timeline")
        .compactNavigationTitle()
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text("What walking has added up to")
                .font(.title3.weight(.semibold))
            Text(
                "Built from the walks you've recorded together — not a health score, "
                + "just the real shape of an active life outdoors."
            )
            .font(.subheadline)
            .foregroundStyle(Theme.Colour.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Lifetime card

    private var lifetimeCard: some View {
        let totalDistance = activities.reduce(0) { $0 + $1.distance }
        let totalDuration = activities.reduce(0) { $0 + $1.movingDuration }
        let streak = model.streak(for: dog.id)
        let monthsActive = Set(activities.map { calendar.startOfMonth(for: $0.startDate) }).count

        return VStack(alignment: .leading, spacing: Theme.Space.m) {
            SectionHeader("Lifetime")
            Card {
                VStack(spacing: Theme.Space.l) {
                    HStack {
                        MetricCard(
                            value: formatters.distanceValue(totalDistance),
                            unit: formatters.distanceUnitLabel,
                            label: "Walked together",
                            symbolName: "point.topleft.down.to.point.bottomright.curvepath",
                            accessibleValue: formatters.accessibleDistance(totalDistance)
                        )
                        MetricCard(
                            value: formatters.duration(totalDuration),
                            label: "Time outdoors",
                            symbolName: "clock",
                            accessibleValue: formatters.spelledDuration(totalDuration)
                        )
                    }
                    Divider()
                    HStack {
                        CompactMetric(
                            value: "\(streak.best)",
                            label: streak.best == 1 ? "Best streak (day)" : "Best streak (days)",
                            symbolName: "flame.fill"
                        )
                        Spacer()
                        CompactMetric(
                            value: "\(monthsActive)",
                            label: monthsActive == 1 ? "Active month" : "Active months",
                            symbolName: "calendar"
                        )
                    }
                }
            }
        }
    }

    // MARK: - Monthly trend

    private var monthlyBuckets: [MonthlyBucket] {
        var byMonth: [Date: MonthlyBucket] = [:]
        for activity in activities {
            let month = calendar.startOfMonth(for: activity.startDate)
            byMonth[month, default: MonthlyBucket(month: month, distance: 0, walkCount: 0)]
                .add(activity)
        }
        return byMonth.values.sorted { $0.month < $1.month }
    }

    @ViewBuilder
    private var monthlyChart: some View {
        // A trend only means something with more than one data point — one bar
        // is just this month's total again, already shown above.
        if monthlyBuckets.count > 1 {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                SectionHeader("Distance by month")
                Card {
                    Chart(monthlyBuckets) { bucket in
                        BarMark(
                            x: .value("Month", bucket.month, unit: .month),
                            y: .value("Distance", distanceInPreferredUnit(bucket.distance))
                        )
                        .foregroundStyle(Theme.Colour.accent)
                        .cornerRadius(3)
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .month, count: max(1, monthlyBuckets.count / 6))) { value in
                            AxisValueLabel(format: .dateTime.month(.abbreviated))
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading)
                    }
                    .frame(height: 160)
                    .accessibilityLabel("Distance walked per month")
                    .accessibilityValue(monthlyAccessibilitySummary)
                }
            }
        }
    }

    private func distanceInPreferredUnit(_ metres: Double) -> Double {
        Measurement(value: metres, unit: UnitLength.meters)
            .converted(to: formatters.distanceUnit.unit)
            .value
    }

    private var monthlyAccessibilitySummary: String {
        monthlyBuckets
            .map { "\(formatters.monthAndYear($0.month)): \(formatters.distance($0.distance))" }
            .joined(separator: ". ")
    }

    // MARK: - Timeline

    private var timelineEntries: [TimelineEntry] {
        var entries: [TimelineEntry] = []

        entries.append(TimelineEntry(
            date: dog.createdAt,
            symbolName: "pawprint.circle.fill",
            tint: Theme.Colour.accent,
            title: "\(dog.name) joined Companion",
            detail: nil
        ))

        for unlock in model.unlocks where unlock.dogID == dog.id {
            guard let definition = AchievementCatalog.definition(id: unlock.achievementID) else { continue }
            entries.append(TimelineEntry(
                date: unlock.unlockedAt,
                symbolName: definition.symbolName,
                tint: Theme.Colour.accent,
                title: definition.title,
                detail: definition.details
            ))
        }

        // Each month that beats every month before it becomes a milestone —
        // "most active month yet" the first time it's true, not every month
        // after, which would just be noise.
        var bestSoFar = 0.0
        for bucket in monthlyBuckets {
            if bucket.distance > bestSoFar {
                bestSoFar = bucket.distance
                // Skip the very first month: being a "new best" is meaningless
                // when there is nothing before it to have beaten.
                if bucket.month != monthlyBuckets.first?.month {
                    entries.append(TimelineEntry(
                        date: bucket.month,
                        symbolName: "chart.line.uptrend.xyaxis",
                        tint: Theme.Colour.success,
                        title: "Most active month yet",
                        detail: "\(formatters.distance(bucket.distance)) across "
                            + "\(bucket.walkCount) \(bucket.walkCount == 1 ? "walk" : "walks") "
                            + "in \(formatters.monthAndYear(bucket.month))"
                    ))
                }
            }
        }

        return entries.sorted { $0.date > $1.date }
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            SectionHeader("Timeline")
            Card {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(timelineEntries.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 {
                            Divider().padding(.leading, 44)
                        }
                        timelineRow(entry)
                    }
                }
            }
        }
    }

    private func timelineRow(_ entry: TimelineEntry) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.m) {
            Image(systemName: entry.symbolName)
                .font(.body)
                .foregroundStyle(entry.tint)
                .frame(width: 28, height: 28)
                .background(entry.tint.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title).font(.subheadline.weight(.medium))
                if let detail = entry.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Theme.Colour.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(formatters.dateTime(entry.date))
                    .font(.caption2)
                    .foregroundStyle(Theme.Colour.secondaryText)
            }
        }
        .padding(.vertical, Theme.Space.s)
        .accessibilityElement(children: .combine)
    }
}

private struct MonthlyBucket: Identifiable {
    let month: Date
    var distance: Double
    var walkCount: Int

    var id: Date { month }

    mutating func add(_ activity: WalkActivity) {
        distance += activity.distance
        walkCount += 1
    }
}

private struct TimelineEntry: Identifiable {
    let id = UUID()
    let date: Date
    let symbolName: String
    let tint: Color
    let title: String
    let detail: String?
}

struct DogHealthTimelineScreen_Previews: PreviewProvider {
    static var previews: some View {
        PreviewHost {
            NavigationStack { DogHealthTimelineScreen(dog: DemoDataProvider.roxy()) }
        }
        .previewDisplayName("Roxy")

        PreviewHost(store: DemoDataProvider.store(populated: false)) {
            NavigationStack { DogHealthTimelineScreen(dog: DemoDataProvider.bailey()) }
        }
        .previewDisplayName("No walks yet")

        PreviewHost {
            NavigationStack { DogHealthTimelineScreen(dog: DemoDataProvider.roxy()) }
        }
        .preferredColorScheme(.dark)
        .previewDisplayName("Dark")
    }
}
