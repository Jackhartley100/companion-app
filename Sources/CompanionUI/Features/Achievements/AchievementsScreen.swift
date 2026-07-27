import SwiftUI
import CompanionCore

/// Every achievement, earned and not yet earned.
struct AchievementsScreen: View {
    let dogID: UUID?

    @Environment(AppModel.self) private var model
    @Environment(\.formatters) private var formatters

    private var statuses: [AchievementStatus] {
        // Earned first, so the screen opens on what has been achieved rather
        // than on a wall of things that have not.
        model.achievementStatuses(for: dogID).sorted { first, second in
            if first.isUnlocked != second.isUnlocked { return first.isUnlocked }
            return (first.progress ?? 0) > (second.progress ?? 0)
        }
    }

    private var unlockedCount: Int {
        statuses.count(where: \.isUnlocked)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
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

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 92), spacing: Theme.Space.m)],
                    spacing: Theme.Space.l
                ) {
                    ForEach(statuses) { AchievementBadge(status: $0) }
                }
            }
            .padding(Theme.Space.l)
        }
        .background(Theme.Colour.groupedBackground)
        .navigationTitle("Achievements")
        .compactNavigationTitle()
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
