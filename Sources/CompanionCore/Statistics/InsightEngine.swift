import Foundation

/// A short, factual observation shown on Today.
public struct Insight: Sendable, Hashable, Identifiable {
    public enum Tone: Sendable, Hashable {
        /// A neutral fact about what has happened.
        case observation
        /// A reachable next step. Never framed as a shortfall.
        case encouragement
        /// Something worth celebrating.
        case celebration
    }

    public let id: String
    public let text: String
    public let symbolName: String
    public let tone: Tone

    public init(id: String, text: String, symbolName: String, tone: Tone) {
        self.id = id
        self.text = text
        self.symbolName = symbolName
        self.tone = tone
    }
}

/// Generates insights from the owner's own saved activities.
///
/// Every insight restates something the stored data actually shows. Nothing here
/// infers anything about the dog's health, and nothing is generated when the
/// underlying sample is too small for the statement to be true in a useful sense
/// — an empty list is a better outcome than a confident claim from two walks.
public struct InsightEngine: Sendable {
    public let calendar: Calendar
    public let formatters: Formatters

    public init(calendar: Calendar = .current, formatters: Formatters = Formatters()) {
        self.calendar = calendar
        self.formatters = formatters
    }

    /// - Parameters:
    ///   - dogName: Used to keep the wording about the dog rather than the user.
    ///   - activities: Every activity for this dog, any period.
    ///   - goalProgress: Progress on the dog's active goals.
    public func insights(
        dogName: String,
        activities: [WalkActivity],
        goalProgress: [GoalProgress],
        streak: Streak,
        now: Date = Date(),
        limit: Int = 3
    ) -> [Insight] {
        guard !activities.isEmpty else { return [] }
        var results: [Insight] = []

        // Closest-to-completion goal first: it is the most actionable thing here.
        if let nearest = goalProgress
            .filter({ !$0.isComplete && $0.fraction > 0.05 })
            .max(by: { $0.fraction < $1.fraction }) {
            results.append(goalInsight(nearest, dogName: dogName))
        }

        if let completed = goalProgress.first(where: \.isComplete) {
            results.append(
                Insight(
                    id: "goal_complete_\(completed.goal.id)",
                    text: "\(dogName) reached this \(completed.goal.period == .weekly ? "week" : "day")'s "
                        + "\(completed.goal.goalType.displayName.lowercased()) goal.",
                    symbolName: "checkmark.seal.fill",
                    tone: .celebration
                )
            )
        }

        if streak.current >= 2 {
            results.append(
                Insight(
                    id: "streak",
                    text: "\(streak.current) days in a row with a walk.",
                    symbolName: "flame.fill",
                    tone: .celebration
                )
            )
        }

        // Consistency over the last five days, stated as a count rather than a
        // percentage or a judgement.
        let recentWindow = calendar.date(byAdding: .day, value: -5, to: calendar.startOfDay(for: now))
        if let recentWindow {
            let recentDays = Set(
                activities
                    .filter { $0.startDate >= recentWindow }
                    .map { calendar.startOfDay(for: $0.startDate) }
            ).count
            if recentDays >= 3 {
                results.append(
                    Insight(
                        id: "recent_consistency",
                        text: "\(dogName) has been out on \(recentDays) of the last 5 days.",
                        symbolName: "calendar.badge.checkmark",
                        tone: .observation
                    )
                )
            }
        }

        // Longest walk this month, once there is a month worth looking at.
        let monthStart = calendar.startOfMonth(for: now)
        let monthActivities = activities.filter { $0.startDate >= monthStart }
        if monthActivities.count >= 3,
           let longest = monthActivities.max(by: { $0.distance < $1.distance }),
           longest.distance > 0 {
            results.append(
                Insight(
                    id: "longest_month",
                    text: "Your longest walk this month was \(formatters.distance(longest.distance)).",
                    symbolName: "arrow.up.right",
                    tone: .observation
                )
            )
        }

        // Most active weekday, only once the claim rests on enough walks.
        let engine = StatisticsEngine(calendar: calendar)
        if let best = engine.mostActiveWeekday(for: activities, minimumWalks: 8) {
            let symbols = calendar.weekdaySymbols
            let index = best.weekday - 1
            if symbols.indices.contains(index) {
                results.append(
                    Insight(
                        id: "best_weekday",
                        text: "\(symbols[index]) is usually your most active day.",
                        symbolName: "chart.bar.fill",
                        tone: .observation
                    )
                )
            }
        }

        return Array(results.prefix(limit))
    }

    private func goalInsight(_ progress: GoalProgress, dogName: String) -> Insight {
        let remainingText: String = switch progress.goal.goalType {
        case .distance:
            formatters.distance(progress.remaining)
        case .duration:
            formatters.spelledDuration(progress.remaining)
        case .activeDays:
            "\(Int(progress.remaining.rounded())) more \(progress.remaining <= 1 ? "day" : "days")"
        case .walkCount:
            "\(Int(progress.remaining.rounded())) more \(progress.remaining <= 1 ? "walk" : "walks")"
        }

        let period = progress.goal.period == .weekly ? "this week's" : "today's"
        return Insight(
            id: "goal_progress_\(progress.goal.id)",
            text: "\(remainingText) to go for \(dogName)'s \(period) goal.",
            symbolName: "target",
            tone: .encouragement
        )
    }
}
