import SwiftUI
import CompanionCore

/// Set and review goals.
///
/// Goals are chosen by the owner. Suggested values are offered as starting
/// points, labelled as such, and never presented as veterinary guidance.
struct GoalsScreen: View {
    let dogID: UUID?

    @Environment(AppModel.self) private var model
    @Environment(\.formatters) private var formatters
    @State private var isAddingGoal = false

    private var progress: [GoalProgress] {
        model.goalProgress(for: dogID)
    }

    private var dog: Dog? {
        model.activeDogs.first { $0.id == dogID }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                if progress.isEmpty {
                    EmptyStateView(
                        symbolName: "target",
                        title: "No goals set",
                        message: "A goal gives the week a shape. "
                            + "Pick something comfortably achievable to begin with.",
                        actionTitle: "Set a goal",
                        action: { isAddingGoal = true }
                    )
                } else {
                    ForEach(progress) { item in
                        Card { GoalProgressCard(progress: item, dogName: dog?.name) }
                            .contextMenu {
                                Button("Delete goal", systemImage: "trash", role: .destructive) {
                                    Task { await model.deleteGoal(item.goal) }
                                }
                            }
                    }

                    if progress.count >= 1 {
                        SecondaryButton("Add another goal", symbolName: "plus") {
                            isAddingGoal = true
                        }
                    }
                }

                VeterinaryDisclaimer()
            }
            .padding(Theme.Space.l)
        }
        .background(Theme.Colour.groupedBackground)
        .navigationTitle("Goals")
        .compactNavigationTitle()
        .sheet(isPresented: $isAddingGoal) {
            GoalEditorSheet(dogID: dogID)
                .environment(model)
                .environment(\.formatters, formatters)
        }
    }
}

struct GoalEditorSheet: View {
    let dogID: UUID?

    @Environment(AppModel.self) private var model
    @Environment(\.formatters) private var formatters
    @Environment(\.dismiss) private var dismiss

    @State private var goalType: GoalType = .distance
    @State private var period: GoalPeriod = .weekly
    @State private var value: Double = 20_000
    @State private var didPopulate = false

    private var dog: Dog? {
        model.activeDogs.first { $0.id == dogID }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("What to track") {
                    Picker("Goal", selection: $goalType) {
                        ForEach(GoalType.allCases) {
                            Label($0.displayName, systemImage: $0.symbolName).tag($0)
                        }
                    }
                    Picker("Period", selection: $period) {
                        ForEach(GoalPeriod.allCases) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    VStack(alignment: .leading, spacing: Theme.Space.m) {
                        Text(formattedValue)
                            .font(Theme.Typeface.metricValue(.title2))
                            .frame(maxWidth: .infinity, alignment: .center)

                        Slider(value: $value, in: range, step: step) {
                            Text("Target")
                        } minimumValueLabel: {
                            Text(shortFormatted(range.lowerBound)).font(.caption2)
                        } maximumValueLabel: {
                            Text(shortFormatted(range.upperBound)).font(.caption2)
                        }
                        .accessibilityValue(formattedValue)

                        Button("Use suggested starting point") {
                            value = suggested
                        }
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                } header: {
                    Text("Target")
                } footer: {
                    Text(
                        "Suggested starting points are based on the activity level you set for "
                        + "\(dog?.name ?? "your dog"). They are a place to begin, not health advice — "
                        + "choose whatever suits you both."
                    )
                }

                Section {
                    PrimaryButton("Save Goal") { Task { await save() } }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("New goal")
            .compactNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                guard !didPopulate else { return }
                didPopulate = true
                value = suggested
            }
            .onChange(of: goalType) { _, _ in value = suggested }
            .onChange(of: period) { _, _ in value = suggested }
        }
    }

    private var suggested: Double {
        Goal.suggestedTarget(
            for: goalType,
            activityLevel: dog?.activityLevel ?? .moderate,
            period: period
        )
    }

    private var range: ClosedRange<Double> {
        switch goalType {
        case .distance: period == .daily ? 500...20_000 : 2_000...100_000
        case .duration: period == .daily ? 300...14_400 : 1_800...72_000
        case .activeDays: period == .daily ? 1...1 : 1...7
        case .walkCount: period == .daily ? 1...6 : 1...30
        }
    }

    private var step: Double {
        switch goalType {
        case .distance: 500
        case .duration: 300
        case .activeDays, .walkCount: 1
        }
    }

    private var formattedValue: String {
        switch goalType {
        case .distance: formatters.distance(value)
        case .duration: formatters.spelledDuration(value)
        case .activeDays: "\(Int(value)) \(Int(value) == 1 ? "day" : "days")"
        case .walkCount: "\(Int(value)) \(Int(value) == 1 ? "walk" : "walks")"
        }
    }

    private func shortFormatted(_ raw: Double) -> String {
        switch goalType {
        case .distance: formatters.distance(raw)
        case .duration: "\(Int(raw / 60))m"
        case .activeDays, .walkCount: "\(Int(raw))"
        }
    }

    private func save() async {
        await model.saveGoal(
            Goal(dogID: dogID, goalType: goalType, targetValue: value, period: period)
        )
        dismiss()
    }
}

struct GoalsScreen_Previews: PreviewProvider {
    static var previews: some View {
        PreviewHost {
            NavigationStack { GoalsScreen(dogID: DemoDataProvider.roxyID) }
        }
        .previewDisplayName("With a goal")

        PreviewHost(store: DemoDataProvider.store(populated: false)) {
            NavigationStack { GoalsScreen(dogID: DemoDataProvider.roxyID) }
        }
        .previewDisplayName("No goals")

        PreviewHost { GoalEditorSheet(dogID: DemoDataProvider.roxyID) }
            .previewDisplayName("Goal editor")

        PreviewHost { GoalEditorSheet(dogID: DemoDataProvider.roxyID) }
            .preferredColorScheme(.dark)
            .previewDisplayName("Goal editor — dark")
    }
}
