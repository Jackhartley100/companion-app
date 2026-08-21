import SwiftUI
import CompanionCore

/// Trends over a chosen period.
struct StatisticsScreen: View {
    let dogID: UUID?

    @Environment(AppModel.self) private var model
    @Environment(\.formatters) private var formatters

    @State private var period: StatisticsPeriod = .week
    @State private var metric: ChartMetric = .distance

    private var statistics: PeriodStatistics {
        model.statistics(for: dogID, period: period)
    }

    private var streak: Streak {
        model.streak(for: dogID)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                periodPicker
                chartCard
                totalsCard
                averagesCard
                streakCard
                if period == .threeMonths {
                    PremiumFeatureLock(
                        entitlement: .advancedTrends,
                        message: "Year-on-year comparisons and custom date ranges are planned "
                            + "for a future update."
                    )
                }
            }
            .padding(Theme.Space.l)
        }
        .background(Theme.Colour.groupedBackground)
        .navigationTitle("Statistics")
        .compactNavigationTitle()
    }

    private var periodPicker: some View {
        Picker("Period", selection: $period) {
            ForEach(StatisticsPeriod.allCases) { Text($0.displayName).tag($0) }
        }
        .pickerStyle(.segmented)
    }

    private var chartCard: some View {
        let chart = DailyActivityChart(days: statistics.days, metric: metric)
        return VStack(alignment: .leading, spacing: Theme.Space.m) {
            SectionHeader(metric.displayName)
            Card {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    Picker("Metric", selection: $metric) {
                        ForEach(ChartMetric.allCases) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    chart.frame(height: 180)

                    // The chart in words, for anyone who cannot see it and for
                    // anyone who just wanted the answer.
                    Text(chart.textualSummary)
                        .font(.footnote)
                        .foregroundStyle(Theme.Colour.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var totalsCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            SectionHeader("Totals")
            Card {
                VStack(spacing: Theme.Space.l) {
                    HStack {
                        MetricCard(
                            value: formatters.distanceValue(statistics.totalDistance),
                            unit: formatters.distanceUnitLabel,
                            label: "Distance",
                            symbolName: "point.topleft.down.to.point.bottomright.curvepath",
                            accessibleValue: formatters.accessibleDistance(statistics.totalDistance)
                        )
                        MetricCard(
                            value: formatters.duration(statistics.totalDuration),
                            label: "Time",
                            symbolName: "clock",
                            accessibleValue: formatters.spelledDuration(statistics.totalDuration)
                        )
                    }
                    HStack {
                        MetricCard(
                            value: "\(statistics.walkCount)",
                            label: statistics.walkCount == 1 ? "Walk" : "Walks",
                            symbolName: "figure.walk"
                        )
                        MetricCard(
                            value: "\(statistics.activeDayCount)",
                            label: "Active days",
                            symbolName: "calendar"
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var averagesCard: some View {
        if statistics.hasData {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                SectionHeader("Averages")
                Card {
                    VStack(spacing: Theme.Space.m) {
                        if let average = statistics.averageDistancePerWalk {
                            labelledRow(
                                "Average walk",
                                value: formatters.distance(average),
                                accessible: formatters.accessibleDistance(average)
                            )
                        }
                        if let average = statistics.averageDurationPerWalk {
                            Divider()
                            labelledRow(
                                "Average time",
                                value: formatters.duration(average),
                                accessible: formatters.spelledDuration(average)
                            )
                        }
                        if let longest = statistics.longestWalk {
                            Divider()
                            labelledRow(
                                "Longest walk",
                                value: formatters.distance(longest.distance),
                                accessible: formatters.accessibleDistance(longest.distance)
                            )
                        }
                    }
                }
            }
        }
    }

    private func labelledRow(_ label: String, value: String, accessible: String) -> some View {
        HStack {
            Text(label).font(.subheadline)
            Spacer()
            Text(value).font(.subheadline.weight(.semibold).monospacedDigit())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(accessible)
    }

    private var streakCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            SectionHeader("Consistency")
            Card {
                HStack {
                    MetricCard(
                        value: "\(streak.current)",
                        label: streak.current == 1 ? "Day streak" : "Day streak",
                        symbolName: "flame.fill",
                        tint: Theme.Colour.accent,
                        accessibleValue: "\(streak.current) \(streak.current == 1 ? "day" : "days") in a row"
                    )
                    MetricCard(
                        value: "\(streak.best)",
                        label: "Best streak",
                        symbolName: "crown.fill",
                        tint: Theme.Colour.accent,
                        accessibleValue: "\(streak.best) \(streak.best == 1 ? "day" : "days")"
                    )
                }
            }
        }
    }
}

struct StatisticsScreen_Previews: PreviewProvider {
    static var previews: some View {
        PreviewHost {
            NavigationStack { StatisticsScreen(dogID: DemoDataProvider.roxyID) }
        }
        .previewDisplayName("Populated")

        PreviewHost(store: DemoDataProvider.store(populated: false)) {
            NavigationStack { StatisticsScreen(dogID: nil) }
        }
        .previewDisplayName("No data")

        PreviewHost {
            NavigationStack { StatisticsScreen(dogID: DemoDataProvider.roxyID) }
        }
        .preferredColorScheme(.dark)
        .previewDisplayName("Dark")
    }
}
