import SwiftUI
import CompanionCore

/// Shown the moment a walk is saved.
///
/// The walk is already stored by the time this appears — nothing here can lose
/// it. Editing the title, notes and visibility updates the saved record, so
/// closing the sheet without touching anything is a perfectly good outcome.
struct WalkSummaryScreen: View {
    let activity: WalkActivity

    @Environment(AppModel.self) private var model
    @Environment(\.formatters) private var formatters
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var notes: String = ""
    @State private var visibility: ActivityVisibility = .privateOnly
    @State private var route: [Coordinate] = []
    @State private var didPopulate = false
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.xl) {
                    celebration
                    RoutePreviewCard(coordinates: route, height: 220)
                    metricsCard
                    unlockedAchievements
                    goalContribution
                    detailsCard
                    provenance
                }
                .padding(Theme.Space.l)
            }
            .background(Theme.Colour.groupedBackground)
            .navigationTitle("Walk saved")
            .compactNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { Task { await saveAndClose() } }
                        .fontWeight(.semibold)
                        .disabled(isSaving)
                }
            }
        }
        .task {
            guard !didPopulate else { return }
            didPopulate = true
            title = activity.title
            notes = activity.notes ?? ""
            visibility = activity.visibility
            route = await model.route(for: activity).map(\.coordinate)
            await model.acknowledgeUnlocks(model.recorder.pendingUnlocks)
        }
    }

    private var celebration: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(headline)
                .font(.title2.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
            Text(
                "\(formatters.dateTime(activity.startDate)) — "
                + "\(formatters.time(activity.endDate))"
            )
            .font(.subheadline)
            .foregroundStyle(Theme.Colour.secondaryText)
        }
        .accessibilityElement(children: .combine)
    }

    private var headline: String {
        let dogs = model.dogs(for: activity)
        guard !dogs.isEmpty else { return "Walk complete" }
        let names = dogs.map(\.name).formatted(.list(type: .and))
        return dogs.count == 1
            ? "\(names) completed a \(formatters.distance(activity.distance)) walk."
            : "\(names) completed a \(formatters.distance(activity.distance)) walk together."
    }

    private var metricsCard: some View {
        Card {
            VStack(spacing: Theme.Space.l) {
                HStack {
                    MetricCard(
                        value: formatters.distanceValue(activity.distance),
                        unit: formatters.distanceUnitLabel,
                        label: "Distance",
                        symbolName: activity.activityType.symbolName,
                        accessibleValue: formatters.accessibleDistance(activity.distance)
                    )
                    MetricCard(
                        value: formatters.duration(activity.movingDuration),
                        label: "Moving time",
                        symbolName: "clock",
                        accessibleValue: formatters.spelledDuration(activity.movingDuration)
                    )
                }
                HStack {
                    CompactMetric(
                        value: formatters.rate(
                            metresPerSecond: activity.averageSpeed,
                            activityType: activity.activityType
                        ) ?? "—",
                        label: "Average",
                        symbolName: "speedometer"
                    )
                    Spacer()
                    if activity.pausedDuration > 0 {
                        CompactMetric(
                            value: formatters.duration(activity.pausedDuration),
                            label: "Paused",
                            symbolName: "pause.circle",
                            accessibleValue: formatters.spelledDuration(activity.pausedDuration)
                        )
                        Spacer()
                    }
                    if let gain = activity.elevationGain, gain > 5 {
                        CompactMetric(
                            value: formatters.distance(gain),
                            label: "Climb",
                            symbolName: "mountain.2"
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var unlockedAchievements: some View {
        let unlocks = model.recorder.pendingUnlocks
        if !unlocks.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                SectionHeader("Earned on this walk")
                ForEach(unlocks) { unlock in
                    if let definition = AchievementCatalog.definition(id: unlock.achievementID) {
                        AchievementUnlockCard(definition: definition)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var goalContribution: some View {
        let dogID = activity.dogIDs.first
        let progress = model.goalProgress(for: dogID)
        if let first = progress.first {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                SectionHeader("Goal")
                Card {
                    GoalProgressCard(
                        progress: first,
                        dogName: model.dogs(for: activity).first?.name
                    )
                }
            }
        }
    }

    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            SectionHeader("Details")
            Card {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        Text("Title").font(.caption).foregroundStyle(Theme.Colour.secondaryText)
                        TextField("Walk title", text: $title)
                            .textFieldStyle(.plain)
                            .font(.body)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        Text("Notes").font(.caption).foregroundStyle(Theme.Colour.secondaryText)
                        TextField("Anything worth remembering?", text: $notes, axis: .vertical)
                            .textFieldStyle(.plain)
                            .lineLimit(2...5)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        Picker("Visibility", selection: $visibility) {
                            ForEach(ActivityVisibility.allCases) { option in
                                Label(option.displayName, systemImage: option.symbolName)
                                    .tag(option)
                            }
                        }
                        // Sharing has no audience yet, so the control records a
                        // preference and the footnote says exactly that rather
                        // than implying the walk was published somewhere.
                        Text(visibilityExplanation)
                            .font(.caption)
                            .foregroundStyle(Theme.Colour.secondaryText)
                    }
                }
            }
        }
    }

    private var visibilityExplanation: String {
        switch visibility {
        case .privateOnly:
            "Only you can see this walk."
        case .followers, .publicFeed:
            "Saved as your preference. Companion has no shared feed yet, "
            + "so this walk stays on your iPhone until one exists."
        }
    }

    private var provenance: some View {
        Label(activity.recordingSource.displayName, systemImage: "iphone")
            .font(.footnote)
            .foregroundStyle(Theme.Colour.secondaryText)
    }

    private func saveAndClose() async {
        isSaving = true
        var updated = activity
        updated.title = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? activity.title
            : title.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil
            : notes.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.visibility = visibility

        await model.updateActivity(updated)
        isSaving = false
        model.recorder.reset()
        dismiss()
    }
}

struct WalkSummaryScreen_Previews: PreviewProvider {
    static var previews: some View {
        PreviewHost { WalkSummaryScreen(activity: DemoDataProvider.sampleActivity()) }
            .previewDisplayName("Summary")

        PreviewHost { WalkSummaryScreen(activity: DemoDataProvider.sampleActivity()) }
            .preferredColorScheme(.dark)
            .previewDisplayName("Dark")

        PreviewHost {
            WalkSummaryScreen(
                activity: {
                    var activity = DemoDataProvider.sampleActivity()
                    activity.dogIDs = [DemoDataProvider.roxyID, DemoDataProvider.baileyID]
                    return activity
                }()
            )
        }
        .previewDisplayName("Two dogs")
    }
}
