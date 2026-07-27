import SwiftUI
import Charts
import CompanionCore

/// What a daily chart plots.
public enum ChartMetric: String, CaseIterable, Identifiable, Sendable {
    case distance
    case duration
    case walks

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .distance: "Distance"
        case .duration: "Time"
        case .walks: "Walks"
        }
    }
}

/// A bar chart of daily totals.
///
/// Accessibility is not an afterthought here: every bar carries a spoken label
/// and value, and the chart as a whole has a text summary, because a chart with
/// no textual equivalent is simply missing for a VoiceOver user.
public struct DailyActivityChart: View {
    private let days: [DailyTotals]
    private let metric: ChartMetric
    private let goalValue: Double?

    @Environment(\.formatters) private var formatters
    @Environment(\.companionCalendar) private var calendar

    public init(days: [DailyTotals], metric: ChartMetric = .distance, goalValue: Double? = nil) {
        self.days = days
        self.metric = metric
        self.goalValue = goalValue
    }

    private func value(for day: DailyTotals) -> Double {
        switch metric {
        case .distance: day.distance
        case .duration: day.duration
        case .walks: Double(day.walkCount)
        }
    }

    private func formatted(_ value: Double) -> String {
        switch metric {
        case .distance: formatters.distance(value)
        case .duration: formatters.spelledDuration(value)
        case .walks: "\(Int(value)) \(value == 1 ? "walk" : "walks")"
        }
    }

    /// True when there is nothing but zeroes. Drawing an axis of flat zeroes
    /// implies data exists and is uniformly nil, which is misleading.
    private var isEmpty: Bool {
        days.allSatisfy { value(for: $0) == 0 }
    }

    public var body: some View {
        Group {
            if days.isEmpty || isEmpty {
                emptyChart
            } else {
                chart
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(metric.displayName) by day")
        .accessibilityValue(textualSummary)
    }

    private var chart: some View {
        Chart {
            ForEach(days) { day in
                BarMark(
                    x: .value("Day", day.date, unit: .day),
                    y: .value(metric.displayName, value(for: day))
                )
                .foregroundStyle(
                    day.isActive ? Theme.Colour.accent : Theme.Colour.accent.opacity(0.2)
                )
                .cornerRadius(4)
                .accessibilityLabel(day.date.formatted(.dateTime.weekday(.wide).day().month()))
                .accessibilityValue(formatted(value(for: day)))
            }

            if let goalValue, goalValue > 0, metric != .walks {
                RuleMark(y: .value("Goal", goalValue / Double(max(1, days.count))))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(Theme.Colour.secondaryAccent)
                    .annotation(position: .top, alignment: .trailing) {
                        Text("Daily pace for goal")
                            .font(.caption2)
                            .foregroundStyle(Theme.Colour.secondaryAccent)
                    }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { value in
                AxisValueLabel(format: .dateTime.weekday(.narrow))
                    .foregroundStyle(Theme.Colour.secondaryText)
                if let date = value.as(Date.self), calendar.isDateInToday(date) {
                    AxisGridLine().foregroundStyle(Theme.Colour.accent.opacity(0.4))
                }
            }
        }
        .chartYAxis {
            // The y-axis always starts at zero. A truncated axis exaggerates
            // differences and would make an ordinary week look like a collapse.
            AxisMarks(position: .leading) { value in
                AxisGridLine().foregroundStyle(Theme.Colour.separator.opacity(0.4))
                AxisValueLabel {
                    if let raw = value.as(Double.self) {
                        Text(axisLabel(raw)).foregroundStyle(Theme.Colour.secondaryText)
                    }
                }
            }
        }
        .chartYScale(domain: .automatic(includesZero: true))
    }

    private func axisLabel(_ raw: Double) -> String {
        switch metric {
        case .distance:
            return formatters.distanceValue(raw)
        case .duration:
            return "\(Int(raw / 60))m"
        case .walks:
            return "\(Int(raw))"
        }
    }

    private var emptyChart: some View {
        VStack(spacing: Theme.Space.s) {
            Image(systemName: "chart.bar")
                .font(.title3)
                .foregroundStyle(Theme.Colour.secondaryText)
            Text("No walks recorded in this period")
                .font(.footnote)
                .foregroundStyle(Theme.Colour.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Space.xl)
    }

    /// The chart in words. Also shown on screen under the chart, because a plain
    /// sentence is often what someone actually wanted from the picture.
    public var textualSummary: String {
        guard !days.isEmpty, !isEmpty else {
            return "No walks recorded in this period."
        }
        let total = days.reduce(0) { $0 + value(for: $1) }
        let activeDays = days.count(where: \.isActive)
        let best = days.max { value(for: $0) < value(for: $1) }

        var summary = "\(formatted(total)) across \(activeDays) "
            + "\(activeDays == 1 ? "day" : "days")."
        if let best, value(for: best) > 0 {
            let dayName = best.date.formatted(.dateTime.weekday(.wide))
            summary += " Busiest day was \(dayName) with \(formatted(value(for: best)))."
        }
        return summary
    }
}

/// The weekly chart shown on Today, with its own heading and summary line.
public struct WeeklyActivityChart: View {
    private let statistics: PeriodStatistics
    private let metric: ChartMetric

    @Environment(\.formatters) private var formatters

    public init(statistics: PeriodStatistics, metric: ChartMetric = .distance) {
        self.statistics = statistics
        self.metric = metric
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack {
                CompactMetric(
                    value: formatters.distance(statistics.totalDistance),
                    label: "This week",
                    accessibleValue: formatters.accessibleDistance(statistics.totalDistance)
                )
                Spacer()
                CompactMetric(
                    value: formatters.duration(statistics.totalDuration),
                    label: "Time",
                    accessibleValue: formatters.spelledDuration(statistics.totalDuration)
                )
                Spacer()
                CompactMetric(
                    value: "\(statistics.activeDayCount)/7",
                    label: "Active days",
                    accessibleValue: "\(statistics.activeDayCount) of 7 days"
                )
            }

            let chart = DailyActivityChart(days: statistics.days, metric: metric)
            chart.frame(height: 120)

            Text(chart.textualSummary)
                .font(.footnote)
                .foregroundStyle(Theme.Colour.secondaryText)
        }
    }
}

struct ActivityCharts_Previews: PreviewProvider {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        return calendar
    }

    static var populated: PeriodStatistics {
        StatisticsEngine(calendar: calendar).statistics(
            for: DemoDataProvider.activities(calendar: calendar),
            period: .week,
            containing: DemoDataProvider.referenceDate
        )
    }

    static var previews: some View {
        Card { WeeklyActivityChart(statistics: populated) }
            .padding()
            .previewDisplayName("Populated")

        Card {
            WeeklyActivityChart(
                statistics: .empty(
                    start: DemoDataProvider.referenceDate,
                    end: DemoDataProvider.referenceDate.addingTimeInterval(7 * 86_400)
                )
            )
        }
        .padding()
        .previewDisplayName("No data")

        Card { WeeklyActivityChart(statistics: populated, metric: .duration) }
            .padding()
            .preferredColorScheme(.dark)
            .previewDisplayName("Duration — dark")
    }
}
