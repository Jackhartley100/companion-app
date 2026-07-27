import SwiftUI
import CompanionCore

/// The short step between tapping Start Walk and recording.
///
/// It exists to confirm who is coming and to get location sorted before the
/// owner is out of the door — not to collect information. A returning owner with
/// one dog and permission already granted taps once more and is walking.
struct WalkPreparationSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var selectedDogIDs: Set<UUID> = []
    @State private var activityType: ActivityType = .walk
    @State private var isRequestingPermission = false
    @State private var showsPermissionExplanation = false
    @State private var didPrepare = false
    /// The real authorisation status. The recorder reaching `.ready` only means
    /// nothing is blocking a start — with `.notDetermined` the system prompt is
    /// still to come, and saying "Location is ready" then would be untrue.
    @State private var permissionStatus: LocationAuthorizationStatus = .notDetermined

    var body: some View {
        NavigationStack {
            Group {
                if showsPermissionExplanation {
                    PermissionExplanationView.location(
                        onAllow: { Task { await requestPermission() } },
                        onSkip: { showsPermissionExplanation = false }
                    )
                } else {
                    form
                }
            }
            .navigationTitle(showsPermissionExplanation ? "" : "Ready to go")
            .compactNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .sheetDetents([.large])
        .task {
            guard !didPrepare else { return }
            didPrepare = true
            model.environment.analytics.track(.walkPreparationOpened)
            selectedDogIDs = Set([model.selectedDogID].compactMap { $0 })
            await model.recorder.prepare()
            permissionStatus = await model.environment.locationPermissions.currentStatus()
        }
    }

    private var form: some View {
        Form {
            // A single-dog owner is never asked to choose — there is nothing to
            // decide, and showing a one-row picker just to confirm the obvious
            // is friction the "fast interaction" principle rules out.
            if model.activeDogs.count > 1 {
                multiDogSection
            } else if let onlyDog = model.activeDogs.first {
                Section {
                    HStack(spacing: Theme.Space.m) {
                        DogAvatar(dog: onlyDog, size: 40, imageStore: model.environment.imageStore)
                        Text("Walking with \(onlyDog.name)")
                            .font(.body)
                    }
                    .accessibilityElement(children: .combine)
                }
            }

            Section("Type") {
                Picker("Activity", selection: $activityType) {
                    ForEach(ActivityType.allCases) { type in
                        Label(type.displayName, systemImage: type.symbolName).tag(type)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section {
                gpsStatusRow
            } header: {
                Text("Location")
            } footer: {
                Text(locationFooter)
            }

            Section {
                PrimaryButton(
                    "Start \(activityType.displayName)",
                    symbolName: activityType.symbolName,
                    isEnabled: !selectedDogIDs.isEmpty
                ) {
                    Task { await start() }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            } footer: {
                if selectedDogIDs.isEmpty {
                    Text("Choose at least one dog to record a walk with.")
                        .foregroundStyle(Theme.Colour.warning)
                }
            }
        }
    }

    /// The picker shown when there is a genuine choice to make.
    ///
    /// Uses square, checkbox-style marks rather than the circular ones used
    /// elsewhere for single selection (the dog switcher on Today, for
    /// instance) — a circle reads as "pick one" by a well-worn convention, and
    /// that mismatch was the actual reason multi-dog selection went unnoticed
    /// even though the underlying toggle already supported it.
    private var multiDogSection: some View {
        Section {
            ForEach(model.activeDogs) { dog in
                Button {
                    toggle(dog)
                } label: {
                    HStack(spacing: Theme.Space.m) {
                        DogAvatar(
                            dog: dog,
                            size: 40,
                            imageStore: model.environment.imageStore,
                            isSelected: selectedDogIDs.contains(dog.id)
                        )
                        VStack(alignment: .leading, spacing: 1) {
                            Text(dog.name).font(.body)
                            Text(dog.breedDescription)
                                .font(.caption)
                                .foregroundStyle(Theme.Colour.secondaryText)
                        }
                        Spacer()
                        Image(
                            systemName: selectedDogIDs.contains(dog.id)
                                ? "checkmark.square.fill"
                                : "square"
                        )
                        .foregroundStyle(
                            selectedDogIDs.contains(dog.id)
                                ? Theme.Colour.accent
                                : Theme.Colour.secondaryText
                        )
                    }
                    .frame(minHeight: Theme.minimumTapTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(
                    selectedDogIDs.contains(dog.id) ? [.isButton, .isSelected] : .isButton
                )
            }
        } header: {
            Text("Who's coming?")
        } footer: {
            Text(
                "Choose one or more dogs. A walk with more than one counts towards "
                + "each of their goals."
            )
        }
    }

    @ViewBuilder
    private var gpsStatusRow: some View {
        switch model.recorder.state {
        case .ready, .recording:
            if permissionStatus.isUsable {
                Label("Location is ready", systemImage: "location.fill")
                    .foregroundStyle(Theme.Colour.success)
            } else {
                Label("Location access will be requested", systemImage: "location")
                    .foregroundStyle(Theme.Colour.secondaryText)
            }
        case .preparing:
            HStack(spacing: Theme.Space.s) {
                ProgressView().controlSize(.small)
                Text("Checking location")
            }
        case .failed(let failure):
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Label(failure.title, systemImage: "location.slash")
                    .foregroundStyle(Theme.Colour.warning)
                Text(failure.message)
                    .font(.footnote)
                    .foregroundStyle(Theme.Colour.secondaryText)
                if failure.requiresSystemSettings {
                    Button("Open Settings") { Platform.openAppSettings() }
                        .font(.subheadline.weight(.medium))
                }
            }
        default:
            Button {
                showsPermissionExplanation = true
            } label: {
                Label("Allow location access", systemImage: "location.circle")
            }
            .disabled(isRequestingPermission)
        }
    }

    private var locationFooter: String {
        "Companion records where your iPhone goes so it can draw your route and "
        + "measure the distance. It is not a measurement of your dog's own movement."
    }

    private func toggle(_ dog: Dog) {
        if selectedDogIDs.contains(dog.id) {
            // Never leave zero dogs selected by tapping the only one.
            guard selectedDogIDs.count > 1 else { return }
            selectedDogIDs.remove(dog.id)
        } else {
            selectedDogIDs.insert(dog.id)
        }
        Haptics.play(.selectionChanged)
    }

    private func requestPermission() async {
        isRequestingPermission = true
        defer { isRequestingPermission = false }
        _ = await model.recorder.requestLocationPermission()
        showsPermissionExplanation = false
    }

    private func start() async {
        guard let ownerID = model.profile?.id else { return }
        // Ordered so the walk always reflects the selector's order rather than
        // the arbitrary order of a Set.
        let ordered = model.activeDogs.map(\.id).filter { selectedDogIDs.contains($0) }

        await model.recorder.start(
            dogIDs: ordered,
            ownerID: ownerID,
            activityType: activityType,
            visibility: model.profile?.defaultVisibility ?? .privateOnly
        )
        if model.recorder.state.isRecording {
            Haptics.play(.walkStarted)
            dismiss()
        }
    }
}

struct WalkPreparationSheet_Previews: PreviewProvider {
    static var previews: some View {
        PreviewHost { WalkPreparationSheet() }
            .previewDisplayName("Two dogs, ready")

        PreviewHost(
            store: InMemoryStore(profile: DemoDataProvider.profile(), dogs: [DemoDataProvider.roxy()])
        ) { WalkPreparationSheet() }
            .previewDisplayName("One dog")

        PreviewHost(locationStatus: .notDetermined) { WalkPreparationSheet() }
            .previewDisplayName("Permission not yet asked")

        PreviewHost(locationStatus: .denied) { WalkPreparationSheet() }
            .previewDisplayName("Permission denied")

        PreviewHost { WalkPreparationSheet() }
            .preferredColorScheme(.dark)
            .previewDisplayName("Dark")
    }
}
