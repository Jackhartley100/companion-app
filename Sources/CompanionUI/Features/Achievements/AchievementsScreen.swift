import SwiftUI
import CompanionCore

/// Every achievement, earned and not yet earned, grouped into families.
///
/// Grouping by `AchievementCategory` — rather than one flat grid sorted by
/// unlocked-first — is what turns this into a trophy case: "Walks Together"
/// reads as a bronze-to-platinum progression the owner can see the shape of,
/// including the platinum badge they have not earned yet, rather than a pile
/// of stickers with no relationship to each other.
struct AchievementsScreen: View {
    let dogID: UUID?

    @Environment(AppModel.self) private var model

    private var statuses: [AchievementStatus] {
        model.achievementStatuses(for: dogID)
    }

    private var unlockedCount: Int {
        statuses.count(where: \.isUnlocked)
    }

    /// Categories in a fixed, deliberate order (progression families first,
    /// one-off badges last) rather than alphabetical or declaration order,
    /// which would otherwise shuffle as the catalog grows.
    private static let categoryOrder: [AchievementCategory] = [.walks, .distance, .streaks, .goals, .timing]

    private func statuses(in category: AchievementCategory) -> [AchievementStatus] {
        statuses
            .filter { $0.definition.category == category }
            .sorted { $0.definition.tier < $1.definition.tier }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                summaryCard

                ForEach(Self.categoryOrder, id: \.self) { category in
                    let categoryStatuses = statuses(in: category)
                    if !categoryStatuses.isEmpty {
                        familySection(category, statuses: categoryStatuses)
                    }
                }
            }
            .padding(Theme.Space.l)
        }
        .background(Theme.Colour.groupedBackground)
        .navigationTitle("Achievements")
        .compactNavigationTitle()
    }

    private var summaryCard: some View {
        Card {
            HStack {
                CompactMetric(
                    value: "\(unlockedCount) of \(statuses.count)",
                    label: "Earned",
                    symbolName: "rosette"
                )
                Spacer()
                ProgressRing(
                    fraction: statuses.isEmpty
                        ? 0
                        : Double(unlockedCount) / Double(statuses.count),
                    lineWidth: 8,
                    tint: Theme.Colour.secondaryAccent,
                    label: "\(unlockedCount)"
                )
                .frame(width: 64, height: 64)
            }
        }
    }

    private func familySection(_ category: AchievementCategory, statuses: [AchievementStatus]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            SectionHeader(category.displayName)
            Card {
                // A horizontal scroller for progression families (several
                // tiers), a plain wrap for one-off categories — a single gold
                // badge does not need a scroll affordance to look intentional.
                if statuses.count > 3 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Theme.Space.l) {
                            ForEach(statuses) { AchievementBadge(status: $0) }
                        }
                        .padding(.vertical, Theme.Space.xs)
                    }
                } else {
                    HStack(spacing: Theme.Space.l) {
                        ForEach(statuses) { AchievementBadge(status: $0) }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }
}

struct AchievementsScreen_Previews: PreviewProvider {
    static var previews: some View {
        PreviewHost {
            NavigationStack { AchievementsScreen(dogID: DemoDataProvider.roxyID) }
        }
        .previewDisplayName("Populated")

        PreviewHost(store: DemoDataProvider.store(populated: false)) {
            NavigationStack { AchievementsScreen(dogID: DemoDataProvider.roxyID) }
        }
        .previewDisplayName("Nothing earned yet")

        PreviewHost {
            NavigationStack { AchievementsScreen(dogID: DemoDataProvider.roxyID) }
        }
        .preferredColorScheme(.dark)
        .previewDisplayName("Dark")
    }
}
