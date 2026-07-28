import SwiftUI
import CompanionCore

/// One walk in full.
struct ActivityDetailScreen: View {
    let activity: WalkActivity

    @Environment(AppModel.self) private var model
    @Environment(\.formatters) private var formatters
    @Environment(\.dismiss) private var dismiss

    @State private var route: [RoutePoint] = []
    @State private var isLoadingRoute = true
    @State private var isEditing = false
    @State private var showsDeleteConfirmation = false
    @State private var viewingPhoto: PhotoViewerTarget?

    /// The current record, so edits made on this screen show immediately.
    private var current: WalkActivity {
        model.activities.first { $0.id == activity.id } ?? activity
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                mapSection
                headerSection
                metricsSection
                photosSection
                if let notes = current.notes, !notes.isEmpty {
                    notesSection(notes)
                }
                achievementsSection
                provenanceSection
                dangerSection
            }
            .padding(Theme.Space.l)
        }
        .background(Theme.Colour.groupedBackground)
        .navigationTitle(current.title)
        .compactNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Edit", systemImage: "pencil") { isEditing = true }
                    // Text only, deliberately. Sharing an image of the route
                    // would publish where the walk started and finished — usually
                    // the owner's home. `RoutePrivacy` exists to trim those ends;
                    // until the shared image is actually rendered through it,
                    // there is no map to share.
                    ShareLink(item: shareText) {
                        Label("Share summary", systemImage: "square.and.arrow.up")
                    }
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        showsDeleteConfirmation = true
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $isEditing) {
            ActivityEditSheet(activity: current)
                .environment(model)
                .environment(\.formatters, formatters)
        }
        .confirmationDialog(
            "Delete this walk?",
            isPresented: $showsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Walk", role: .destructive) {
                Task {
                    Haptics.play(.destructiveConfirmed)
                    await model.deleteActivity(current)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The route and everything recorded with it will be removed from this iPhone. "
                 + "This cannot be undone.")
        }
        .task {
            route = await model.route(for: activity)
            isLoadingRoute = false
        }
        .sheet(item: $viewingPhoto) { target in
            WalkPhotoViewerScreen(
                references: current.imageReferences,
                startingAt: target.id,
                imageStore: model.environment.imageStore,
                fixedCaption: current.title
            )
        }
    }

    private var photosSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            SectionHeader("Photos")
            WalkPhotoStrip(
                references: current.imageReferences,
                imageStore: model.environment.imageStore,
                canRemove: true,
                onAdd: { data in
                    guard let reference = try? await model.environment.imageStore.store(data) else { return }
                    var updated = current
                    updated.imageReferences.append(reference)
                    await model.updateActivity(updated)
                },
                onRemove: { reference in
                    Task {
                        var updated = current
                        updated.imageReferences.removeAll { $0 == reference }
                        await model.updateActivity(updated)
                        try? await model.environment.imageStore.delete(reference: reference)
                    }
                },
                onTap: { reference in viewingPhoto = PhotoViewerTarget(reference) }
            )
        }
    }

    private var mapSection: some View {
        Group {
            if isLoadingRoute {
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(Theme.Colour.fill)
                    .frame(height: 260)
                    .overlay { ProgressView() }
            } else {
                RoutePreviewCard(coordinates: route.map(\.coordinate), height: 260)
            }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text(formatters.dateTime(current.startDate))
                .font(.subheadline)
                .foregroundStyle(Theme.Colour.secondaryText)

            let dogs = model.dogs(for: current)
            if !dogs.isEmpty {
                HStack(spacing: Theme.Space.s) {
                    DogAvatarRow(dogs: dogs, size: 28, imageStore: model.environment.imageStore)
                    Text("With \(dogs.map(\.name).formatted(.list(type: .and)))")
                        .font(.subheadline.weight(.medium))
                }
                .accessibilityElement(children: .combine)
            }

            Label(current.visibility.displayName, systemImage: current.visibility.symbolName)
                .font(.caption)
                .foregroundStyle(Theme.Colour.secondaryText)
        }
    }

    private var metricsSection: some View {
        Card {
            VStack(spacing: Theme.Space.l) {
                HStack {
                    MetricCard(
                        value: formatters.distanceValue(current.distance),
                        unit: formatters.distanceUnitLabel,
                        label: "Distance",
                        symbolName: current.activityType.symbolName,
                        accessibleValue: formatters.accessibleDistance(current.distance)
                    )
                    MetricCard(
                        value: formatters.duration(current.movingDuration),
                        label: "Moving time",
                        symbolName: "clock",
                        accessibleValue: formatters.spelledDuration(current.movingDuration)
                    )
                }
                Divider()
                HStack {
                    CompactMetric(
                        value: formatters.rate(
                            metresPerSecond: current.averageSpeed,
                            activityType: current.activityType
                        ) ?? "—",
                        label: "Average",
                        symbolName: "speedometer"
                    )
                    Spacer()
                    CompactMetric(
                        value: formatters.duration(current.elapsedDuration),
                        label: "Elapsed",
                        symbolName: "timer",
                        accessibleValue: formatters.spelledDuration(current.elapsedDuration)
                    )
                    Spacer()
                    if let gain = current.elevationGain, gain > 5 {
                        CompactMetric(
                            value: formatters.distance(gain),
                            label: "Climb",
                            symbolName: "mountain.2"
                        )
                    } else {
                        CompactMetric(
                            value: "\(current.routePointCount)",
                            label: "GPS points",
                            symbolName: "point.3.connected.trianglepath.dotted"
                        )
                    }
                }
            }
        }
    }

    private func notesSection(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            SectionHeader("Notes")
            Card {
                Text(notes)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var achievementsSection: some View {
        let earned = model.unlocks
            .filter { $0.walkID == current.id }
            .compactMap { AchievementCatalog.definition(id: $0.achievementID) }
        if !earned.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                SectionHeader("Earned on this walk")
                ForEach(earned) { AchievementUnlockCard(definition: $0) }
            }
        }
    }

    private var provenanceSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Label(current.recordingSource.displayName, systemImage: "iphone")
                .font(.footnote)
                .foregroundStyle(Theme.Colour.secondaryText)

            // The honesty line. The route is where the phone went, which is not
            // the same as where the dog went — an off-lead dog covers a good deal
            // more ground than the person holding the lead.
            if !current.recordingSource.measuresDogDirectly {
                Text(
                    "This route was recorded by your iPhone. It shows the distance you "
                    + "covered on this walk, not your dog's own movement."
                )
                .font(.footnote)
                .foregroundStyle(Theme.Colour.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var dangerSection: some View {
        VStack(spacing: Theme.Space.s) {
            SecondaryButton("Edit walk", symbolName: "pencil") { isEditing = true }
            SecondaryButton("Delete walk", symbolName: "trash", role: .destructive) {
                showsDeleteConfirmation = true
            }
        }
    }

    private var shareText: String {
        let dogs = model.dogs(for: current).map(\.name).formatted(.list(type: .and))
        let distance = formatters.distance(current.distance)
        let duration = formatters.spelledDuration(current.movingDuration)
        let subject = dogs.isEmpty ? "We" : dogs
        return "\(subject) walked \(distance) in \(duration). — \(Theme.Brand.name)"
    }
}

/// Editing an already-saved walk.
struct ActivityEditSheet: View {
    let activity: WalkActivity

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var notes: String = ""
    @State private var visibility: ActivityVisibility = .privateOnly
    @State private var selectedDogIDs: Set<UUID> = []
    @State private var didPopulate = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Walk title", text: $title)
                }
                Section("Notes") {
                    TextField("Anything worth remembering?", text: $notes, axis: .vertical)
                        .lineLimit(3...8)
                }
                Section("Dogs") {
                    ForEach(model.activeDogs) { dog in
                        Button {
                            if selectedDogIDs.contains(dog.id) {
                                selectedDogIDs.remove(dog.id)
                            } else {
                                selectedDogIDs.insert(dog.id)
                            }
                        } label: {
                            HStack {
                                Text(dog.name)
                                Spacer()
                                if selectedDogIDs.contains(dog.id) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Theme.Colour.accent)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                Section("Visibility") {
                    Picker("Visibility", selection: $visibility) {
                        ForEach(ActivityVisibility.allCases) {
                            Label($0.displayName, systemImage: $0.symbolName).tag($0)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
            }
            .navigationTitle("Edit walk")
            .compactNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }.fontWeight(.semibold)
                }
            }
            .onAppear {
                guard !didPopulate else { return }
                didPopulate = true
                title = activity.title
                notes = activity.notes ?? ""
                visibility = activity.visibility
                selectedDogIDs = Set(activity.dogIDs)
            }
        }
    }

    private func save() async {
        var updated = activity
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.title = trimmedTitle.isEmpty ? activity.title : trimmedTitle
        updated.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil
            : notes.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.visibility = visibility
        updated.dogIDs = model.activeDogs.map(\.id).filter { selectedDogIDs.contains($0) }
        await model.updateActivity(updated)
        dismiss()
    }
}

struct ActivityDetailScreen_Previews: PreviewProvider {
    static var previews: some View {
        PreviewHost {
            NavigationStack {
                ActivityDetailScreen(activity: DemoDataProvider.sampleActivity())
            }
        }
        .previewDisplayName("Detail")

        PreviewHost {
            NavigationStack {
                ActivityDetailScreen(activity: DemoDataProvider.sampleActivity())
            }
        }
        .preferredColorScheme(.dark)
        .previewDisplayName("Dark")

        PreviewHost { ActivityEditSheet(activity: DemoDataProvider.sampleActivity()) }
            .previewDisplayName("Edit")
    }
}
