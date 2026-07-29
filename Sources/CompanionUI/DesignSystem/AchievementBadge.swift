import SwiftUI
import CompanionCore

extension AchievementTier {
    /// The one place a tier becomes a colour — everything else works with the
    /// tier itself, so a future rebalancing of the palette touches one line.
    public var colour: Color {
        switch self {
        case .bronze: Theme.Colour.Tier.bronze
        case .silver: Theme.Colour.Tier.silver
        case .gold: Theme.Colour.Tier.gold
        case .platinum: Theme.Colour.Tier.platinum
        }
    }
}

/// One achievement, locked or unlocked.
///
/// Colour carries the tier: bronze, silver, gold and platinum badges are
/// visibly different metals when earned, so a "Walks Together" row reads as
/// a progression at a glance rather than four identical stickers with
/// different numbers on them. Locked badges stay a flat neutral grey
/// regardless of tier — showing the eventual colour before it is earned
/// would be showing off a reward that has not happened yet.
public struct AchievementBadge: View {
    private let status: AchievementStatus
    private let size: CGFloat

    @Environment(\.formatters) private var formatters

    public init(status: AchievementStatus, size: CGFloat = 64) {
        self.status = status
        self.size = size
    }

    private var tierColour: Color { status.definition.tier.colour }

    public var body: some View {
        VStack(spacing: Theme.Space.s) {
            ZStack {
                Circle()
                    .fill(status.isUnlocked ? tierColour.opacity(0.16) : Theme.Colour.fill)

                if status.isUnlocked {
                    // A thin ring in the tier colour, so a gold badge and a
                    // platinum badge are distinguishable even at a glance
                    // before anyone reads the icon or title.
                    Circle()
                        .strokeBorder(tierColour.opacity(0.55), lineWidth: 1.5)
                }

                if let progress = status.progress, !status.isUnlocked, progress > 0 {
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            Theme.Colour.secondaryText.opacity(0.4),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                }

                Image(systemName: status.definition.symbolName)
                    .font(.system(size: size * 0.4))
                    .foregroundStyle(
                        status.isUnlocked ? tierColour : Theme.Colour.secondaryText.opacity(0.55)
                    )
            }
            .frame(width: size, height: size)

            VStack(spacing: 1) {
                Text(status.definition.title)
                    .font(.caption2)
                    .fontWeight(status.isUnlocked ? .semibold : .regular)
                    .foregroundStyle(
                        status.isUnlocked ? Theme.Colour.primaryText : Theme.Colour.secondaryText
                    )
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                if status.isUnlocked {
                    Text(status.definition.tier.displayName.uppercased())
                        .font(.system(size: 8.5, weight: .bold))
                        .tracking(0.4)
                        .foregroundStyle(tierColour)
                }
            }
        }
        .frame(width: size + 24)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(status.definition.title)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(status.definition.details)
    }

    private var accessibilityValue: String {
        if let unlock = status.unlock {
            return "\(status.definition.tier.displayName) tier. Earned on \(formatters.shortDate(unlock.unlockedAt))."
        }
        if let progress = status.progress {
            return "Not yet earned. \(Int((progress * 100).rounded())) percent of the way there."
        }
        return "Not yet earned"
    }
}

/// The celebration shown when a walk earns something.
public struct AchievementUnlockCard: View {
    private let definition: AchievementDefinition
    @State private var hasAppeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(definition: AchievementDefinition) {
        self.definition = definition
    }

    private var tierColour: Color { definition.tier.colour }

    public var body: some View {
        HStack(spacing: Theme.Space.m) {
            Image(systemName: definition.symbolName)
                .font(.title2)
                .foregroundStyle(tierColour)
                .frame(width: 44, height: 44)
                .background(tierColour.opacity(0.18), in: Circle())
                .overlay(Circle().strokeBorder(tierColour.opacity(0.5), lineWidth: 1.5))
                .scaleEffect(hasAppeared || reduceMotion ? 1 : 0.6)

            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                HStack(spacing: Theme.Space.xs) {
                    Text(definition.title).font(.headline)
                    Text(definition.tier.displayName.uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.4)
                        .foregroundStyle(tierColour)
                }
                Text(definition.details)
                    .font(.footnote)
                    .foregroundStyle(Theme.Colour.secondaryText)
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Space.m)
        .background(tierColour.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
        .onAppear {
            guard !reduceMotion else { hasAppeared = true; return }
            withAnimation(.companionStandard.delay(0.1)) { hasAppeared = true }
            Haptics.play(.achievementUnlocked)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Achievement unlocked: \(definition.title), \(definition.tier.displayName) tier. \(definition.details)"
        )
    }
}

/// A goal with its progress ring and the plain-English state of play.
public struct GoalProgressCard: View {
    private let progress: GoalProgress
    private let dogName: String?

    @Environment(\.formatters) private var formatters

    public init(progress: GoalProgress, dogName: String? = nil) {
        self.progress = progress
        self.dogName = dogName
    }

    public var body: some View {
        HStack(spacing: Theme.Space.l) {
            ProgressRing(
                fraction: progress.fraction,
                tint: progress.isComplete ? Theme.Colour.success : Theme.Colour.accent,
                label: "\(Int((progress.fraction * 100).rounded()))%",
                caption: progress.goal.period.displayName
            )
            .frame(width: 96, height: 96)

            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text(headline)
                    .font(.headline)
                    .foregroundStyle(Theme.Colour.primaryText)

                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colour.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                if !progress.isComplete {
                    Text(timeRemainingText)
                        .font(.caption)
                        .foregroundStyle(Theme.Colour.secondaryText)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(headline)
        .accessibilityValue("\(detail). \(progress.isComplete ? "" : timeRemainingText)")
    }

    private var headline: String {
        let subject = dogName.map { "\($0)'s" } ?? "Your"
        let period = progress.goal.period == .weekly ? "weekly" : "daily"
        return "\(subject) \(period) \(progress.goal.goalType.displayName.lowercased()) goal"
    }

    private var detail: String {
        if progress.isComplete {
            return "Complete — \(formattedValue(progress.currentValue)) of \(formattedValue(progress.goal.targetValue))"
        }
        return "\(formattedValue(progress.currentValue)) of \(formattedValue(progress.goal.targetValue))"
    }

    private var timeRemainingText: String {
        let remaining = progress.timeRemaining()
        let days = Int(remaining / 86_400)
        if days >= 1 {
            return "\(days) \(days == 1 ? "day" : "days") left"
        }
        let hours = max(1, Int(remaining / 3_600))
        return "\(hours) \(hours == 1 ? "hour" : "hours") left"
    }

    private func formattedValue(_ value: Double) -> String {
        switch progress.goal.goalType {
        case .distance: formatters.distance(value)
        case .duration: formatters.spelledDuration(value)
        case .activeDays: "\(Int(value.rounded())) days"
        case .walkCount: "\(Int(value.rounded())) walks"
        }
    }
}

struct AchievementBadge_Previews: PreviewProvider {
    static var statuses: [AchievementStatus] {
        AchievementEngine().statuses(
            context: AchievementContext(
                activities: Array(DemoDataProvider.activities().prefix(12)),
                streak: Streak(current: 3, best: 5, lastActiveDay: DemoDataProvider.referenceDate),
                dogID: DemoDataProvider.roxyID
            ),
            existing: [
                AchievementUnlock(achievementID: "first_walk"),
                AchievementUnlock(achievementID: "ten_activities"),
                AchievementUnlock(achievementID: "streak_three")
            ]
        )
    }

    static var previews: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 88))], spacing: Theme.Space.l) {
                ForEach(statuses) { AchievementBadge(status: $0) }
            }
            .padding()
        }
        .previewDisplayName("Badges")

        VStack(spacing: Theme.Space.l) {
            AchievementUnlockCard(definition: AchievementCatalog.all[0])
            Card {
                GoalProgressCard(
                    progress: GoalProgress(
                        goal: Goal(dogID: nil, goalType: .distance, targetValue: 30_000),
                        currentValue: 18_600,
                        periodStart: DemoDataProvider.referenceDate,
                        periodEnd: DemoDataProvider.referenceDate.addingTimeInterval(3 * 86_400)
                    ),
                    dogName: "Roxy"
                )
            }
            Card {
                GoalProgressCard(
                    progress: GoalProgress(
                        goal: Goal(dogID: nil, goalType: .activeDays, targetValue: 5),
                        currentValue: 5,
                        periodStart: DemoDataProvider.referenceDate,
                        periodEnd: DemoDataProvider.referenceDate.addingTimeInterval(86_400)
                    ),
                    dogName: "Bailey"
                )
            }
        }
        .padding()
        .background(Theme.Colour.groupedBackground)
        .previewDisplayName("Unlock and goals")
    }
}
