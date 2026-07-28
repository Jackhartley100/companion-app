import SwiftUI
import CompanionCore

/// A dog's own page: who they are, and everything they have done.
struct DogProfileScreen: View {
    let dog: Dog

    @Environment(AppModel.self) private var model
    @Environment(\.formatters) private var formatters
    @Environment(\.dismiss) private var dismiss

    @State private var isEditing = false
    @State private var showsArchiveConfirmation = false

    /// Re-read from the model so edits appear without going back and in again.
    private var current: Dog {
        model.dogs.first { $0.id == dog.id } ?? dog
    }

    private var activities: [WalkActivity] {
        model.activities(for: current.id)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                header
                lifetimeCard
                timelineLink
                goalSection
                trendSection
                achievementSection
                recentSection
                actions
            }
            .padding(Theme.Space.l)
        }
        .background(Theme.Colour.groupedBackground)
        .navigationTitle(current.name)
        .compactNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { isEditing = true }
            }
        }
        .sheet(isPresented: $isEditing) {
            NavigationStack {
                DogEditorScreen(mode: .edit(current)) { updated in
                    await model.saveDog(updated)
                    isEditing = false
                }
            }
            .environment(model)
            .environment(\.formatters, formatters)
        }
        .confirmationDialog(
            "Archive \(current.name)?",
            isPresented: $showsArchiveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Archive", role: .destructive) {
                Task {
                    await model.archiveDog(current)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(current.name) will be hidden from the dog selector. "
                 + "Every walk you recorded together is kept.")
        }
    }

    private var header: some View {
        HStack(spacing: Theme.Space.l) {
            DogAvatar(dog: current, size: 84, imageStore: model.environment.imageStore)
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text(current.name).font(.title2.weight(.bold))
                Text(current.breedDescription)
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colour.secondaryText)
                HStack(spacing: Theme.Space.m) {
                    if let age = formatters.age(current.age) {
                        Label(age, systemImage: "birthday.cake")
                    }
                    if let weight = current.weightKilograms {
                        Label(formatters.weight(kilograms: weight), systemImage: "scalemass")
                    }
                }
                .font(.caption)
                .foregroundStyle(Theme.Colour.secondaryText)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var lifetimeCard: some View {
        let totalDistance = activities.reduce(0) { $0 + $1.distance }
        let totalDuration = activities.reduce(0) { $0 + $1.movingDuration }
        let longest = activities.max { $0.distance < $1.distance }
        let streak = model.streak(for: current.id)

        return VStack(alignment: .leading, spacing: Theme.Space.m) {
            SectionHeader("Together so far")
            Card {
                VStack(spacing: Theme.Space.l) {
                    HStack {
                        MetricCard(
                            value: "\(activities.count)",
                            label: activities.count == 1 ? "Walk" : "Walks",
                            symbolName: "figure.walk"
                        )
                        MetricCard(
                            value: formatters.distanceValue(totalDistance),
                            unit: formatters.distanceUnitLabel,
                            label: "Distance",
                            symbolName: "point.topleft.down.to.point.bottomright.curvepath",
                            accessibleValue: formatters.accessibleDistance(totalDistance)
                        )
                    }
                    Divider()
                    HStack {
                        CompactMetric(
                            value: formatters.duration(totalDuration),
                            label: "Total time",
                            symbolName: "clock",
                            accessibleValue: formatters.spelledDuration(totalDuration)
                        )
                        Spacer()
                        CompactMetric(
                            value: longest.map { formatters.distance($0.distance) } ?? "—",
                            label: "Longest walk",
                            symbolName: "arrow.up.right"
                        )
                        Spacer()
                        CompactMetric(
                            value: "\(streak.current)",
                            label: "Day streak",
                            symbolName: "flame.fill",
                            accessibleValue: "\(streak.current) \(streak.current == 1 ? "day" : "days")"
                        )
                    }
                }
            }
        }
    }

    private var timelineLink: some View {
        NavigationLink {
            DogHealthTimelineScreen(dog: current)
        } label: {
            Card {
                HStack(spacing: Theme.Space.m) {
                    Image(systemName: "heart.text.square.fill")
                        .font(.title3)
                        .foregroundStyle(Theme.Colour.accent)
                        .frame(width: 36, height: 36)
                        .background(Theme.Colour.accent.opacity(0.12), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text("What walking has added up to")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.Colour.primaryText)
                        Text("See \(current.name)'s activity timeline")
                            .font(.caption)
                            .foregroundStyle(Theme.Colour.secondaryText)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.Colour.secondaryText)
                }
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var goalSection: some View {
        if let progress = model.goalProgress(for: current.id).first {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                SectionHeader("Goal")
                Card { GoalProgressCard(progress: progress, dogName: current.name) }
            }
        }
    }

    private var trendSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            SectionHeader("This week")
            Card {
                WeeklyActivityChart(statistics: model.statistics(for: current.id, period: .week))
            }
        }
    }

    @ViewBuilder
    private var achievementSection: some View {
        let earned = model.achievementStatuses(for: current.id).filter(\.isUnlocked)
        if !earned.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                SectionHeader("Achievements")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Space.m) {
                        ForEach(earned) { AchievementBadge(status: $0, size: 56) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var recentSection: some View {
        let recent = Array(activities.prefix(5))
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            SectionHeader("Recent walks")
            if recent.isEmpty {
                Card {
                    Text("No walks recorded with \(current.name) yet.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.Colour.secondaryText)
                }
            } else {
                Card {
                    VStack(spacing: Theme.Space.m) {
                        ForEach(Array(recent.enumerated()), id: \.element.id) { index, activity in
                            if index > 0 { Divider() }
                            ActivityRow(
                                activity: activity,
                                dogs: model.dogs(for: activity),
                                imageStore: model.environment.imageStore,
                                hasAchievement: model.hasAchievement(for: activity.id)
                            )
                        }
                    }
                }
            }
        }
    }

    private var actions: some View {
        VStack(spacing: Theme.Space.s) {
            SecondaryButton("Edit \(current.name)", symbolName: "pencil") { isEditing = true }
            SecondaryButton("Archive \(current.name)", symbolName: "archivebox", role: .destructive) {
                showsArchiveConfirmation = true
            }
        }
    }
}

struct DogProfileScreen_Previews: PreviewProvider {
    static var previews: some View {
        PreviewHost {
            NavigationStack { DogProfileScreen(dog: DemoDataProvider.roxy()) }
        }
        .previewDisplayName("Roxy")

        PreviewHost(store: DemoDataProvider.store(populated: false)) {
            NavigationStack { DogProfileScreen(dog: DemoDataProvider.bailey()) }
        }
        .previewDisplayName("No walks yet")

        PreviewHost {
            NavigationStack { DogProfileScreen(dog: DemoDataProvider.roxy()) }
        }
        .preferredColorScheme(.dark)
        .previewDisplayName("Dark")
    }
}
