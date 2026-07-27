import SwiftUI
import CompanionCore

/// Account, dogs, preferences, permissions, privacy and support.
struct ProfileScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.formatters) private var formatters

    @State private var isAddingDog = false
    @State private var showsDeleteHistoryConfirmation = false
    @State private var subscription: SubscriptionStatus = .free
    @State private var locationStatus: LocationAuthorizationStatus = .notDetermined

    var body: some View {
        @Bindable var model = model

        NavigationStack {
            List {
                accountSection
                dogsSection
                preferencesSection(model: model)
                permissionsSection
                privacySection
                integrationsSection
                supportSection
            }
            .navigationTitle("Profile")
            .largeNavigationTitle()
            .navigationDestination(for: Dog.self) { DogProfileScreen(dog: $0) }
            .navigationDestination(for: ProfileRoute.self) { route in
                switch route {
                case .achievements: AchievementsScreen(dogID: model.selectedDogID)
                case .goals: GoalsScreen(dogID: model.selectedDogID)
                case .statistics: StatisticsScreen(dogID: model.selectedDogID)
                }
            }
            .sheet(isPresented: $isAddingDog) {
                NavigationStack {
                    DogEditorScreen(mode: .create) { dog in
                        await model.saveDog(dog)
                        isAddingDog = false
                    }
                }
                .environment(model)
                .environment(\.formatters, formatters)
            }
            .confirmationDialog(
                "Delete all activity history?",
                isPresented: $showsDeleteHistoryConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete Everything", role: .destructive) {
                    Task {
                        Haptics.play(.destructiveConfirmed)
                        await model.deleteAllActivities()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Every walk and route will be permanently removed from this iPhone. "
                     + "Your dogs and settings are kept. This cannot be undone.")
            }
            .task {
                subscription = await model.environment.subscriptions.status()
                locationStatus = await model.environment.locationPermissions.currentStatus()
            }
        }
    }

    enum ProfileRoute: Hashable {
        case achievements, goals, statistics
    }

    // MARK: Sections

    private var accountSection: some View {
        Section {
            HStack(spacing: Theme.Space.m) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Theme.Colour.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.profile?.firstName.isEmpty == false
                         ? model.profile!.firstName
                         : "Your profile")
                        .font(.headline)
                    Text(AuthenticationProvider.localDevice.displayName)
                        .font(.caption)
                        .foregroundStyle(Theme.Colour.secondaryText)
                }
            }
            .padding(.vertical, Theme.Space.xs)
            .accessibilityElement(children: .combine)

            LabeledContent("Plan", value: subscription.planName)
        } footer: {
            Text(
                "Your data is stored on this iPhone. Accounts that sync between devices "
                + "are planned for a future update."
            )
        }
    }

    private var dogsSection: some View {
        Section("Dogs") {
            ForEach(model.activeDogs) { dog in
                NavigationLink(value: dog) {
                    HStack(spacing: Theme.Space.m) {
                        DogAvatar(dog: dog, size: 36, imageStore: model.environment.imageStore)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(dog.name)
                            Text(dog.breedDescription)
                                .font(.caption)
                                .foregroundStyle(Theme.Colour.secondaryText)
                        }
                        Spacer()
                        if model.selectedDogID == dog.id {
                            Text("Default")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(Theme.Colour.accent)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }

            Button("Add another dog", systemImage: "plus") { isAddingDog = true }
        }
    }

    private func preferencesSection(model: AppModel) -> some View {
        Section("Units and appearance") {
            Picker("Distance", selection: distanceBinding) {
                ForEach(DistanceUnit.allCases) { Text($0.displayName).tag($0) }
            }
            Picker("Weight", selection: weightBinding) {
                ForEach(WeightUnit.allCases) { Text($0.displayName).tag($0) }
            }
            Picker("Week starts on", selection: weekStartBinding) {
                ForEach(WeekStart.allCases) { Text($0.displayName).tag($0) }
            }
            Picker("Appearance", selection: appearanceBinding) {
                ForEach(AppearancePreference.allCases) { Text($0.displayName).tag($0) }
            }
        }
    }

    private var permissionsSection: some View {
        Section {
            permissionRow(
                title: "Location",
                detail: locationDetail,
                isGranted: locationStatus.isUsable,
                showsSettingsLink: !locationStatus.isUsable && locationStatus != .notDetermined
            )
            permissionRow(
                title: "Notifications",
                detail: "Reminders are not enabled in this version.",
                isGranted: false,
                showsSettingsLink: false
            )
            permissionRow(
                title: "Photos",
                detail: "Asked for when you add a photo to a dog or a walk.",
                isGranted: true,
                showsSettingsLink: false
            )
        } header: {
            Text("Permissions")
        } footer: {
            Text("Location is used only while a walk is being recorded.")
        }
    }

    private func permissionRow(
        title: String,
        detail: String,
        isGranted: Bool,
        showsSettingsLink: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack {
                Text(title)
                Spacer()
                Image(systemName: isGranted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isGranted ? Theme.Colour.success : Theme.Colour.secondaryText)
            }
            Text(detail)
                .font(.caption)
                .foregroundStyle(Theme.Colour.secondaryText)
            if showsSettingsLink {
                Button("Open Settings") { Platform.openAppSettings() }
                    .font(.caption.weight(.medium))
            }
        }
        .padding(.vertical, Theme.Space.xxs)
        .accessibilityElement(children: .combine)
        .accessibilityValue(isGranted ? "Allowed" : "Not allowed")
    }

    private var locationDetail: String {
        switch locationStatus {
        case .always, .whenInUse: "Allowed while you are recording a walk."
        case .denied: "Not allowed. Walks cannot be recorded without it."
        case .restricted: "Restricted on this device."
        case .notDetermined: "Asked for the first time you start a walk."
        }
    }

    private var privacySection: some View {
        Section {
            Picker("Default visibility for new walks", selection: visibilityBinding) {
                ForEach(ActivityVisibility.allCases) {
                    Label($0.displayName, systemImage: $0.symbolName).tag($0)
                }
            }
            Toggle("Hide the start and end of shared routes", isOn: hideEndpointsBinding)

            Button("Delete all activity history", systemImage: "trash", role: .destructive) {
                showsDeleteHistoryConfirmation = true
            }
        } header: {
            Text("Privacy")
        } footer: {
            Text(
                "Walks start private. Hiding route ends keeps the area around your home "
                + "out of anything you share later."
            )
        }
    }

    private var integrationsSection: some View {
        Section {
            integrationRow("Apple Health", detail: "Not available in this version.", symbol: "heart")
            integrationRow("Apple Watch", detail: "Planned for a future update.", symbol: "applewatch")
            integrationRow(
                "Companion Tracker",
                detail: "The dog tracker is in development. Not available yet.",
                symbol: "location.circle"
            )
            integrationRow(
                "Export your data",
                detail: "Exporting walks as a file is planned for a future update.",
                symbol: "square.and.arrow.up"
            )
        } header: {
            Text("Integrations")
        } footer: {
            Text("These are listed so you know what is coming. None of them are connected yet.")
        }
    }

    private func integrationRow(_ title: String, detail: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.m) {
            Image(systemName: symbol)
                .foregroundStyle(Theme.Colour.secondaryText)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Theme.Colour.secondaryText)
            }
            Spacer()
        }
        .padding(.vertical, Theme.Space.xxs)
        .accessibilityElement(children: .combine)
    }

    private var supportSection: some View {
        Section {
            NavigationLink(value: ProfileRoute.achievements) {
                Label("Achievements", systemImage: "rosette")
            }
            NavigationLink(value: ProfileRoute.goals) {
                Label("Goals", systemImage: "target")
            }
            NavigationLink(value: ProfileRoute.statistics) {
                Label("Statistics", systemImage: "chart.bar")
            }
        } header: {
            Text("Your activity")
        } footer: {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text("\(Theme.Brand.name) — development build")
                VeterinaryDisclaimer()
            }
        }
    }

    // MARK: Preference bindings

    /// Each preference writes straight through to the stored profile, so a
    /// change is durable the moment it is made rather than on some later save.
    private func profileBinding<Value>(
        _ keyPath: WritableKeyPath<UserProfile, Value>,
        default defaultValue: Value
    ) -> Binding<Value> {
        Binding(
            get: { model.profile?[keyPath: keyPath] ?? defaultValue },
            set: { newValue in
                guard var profile = model.profile else { return }
                profile[keyPath: keyPath] = newValue
                Task { await model.saveProfile(profile) }
            }
        )
    }

    private var distanceBinding: Binding<DistanceUnit> {
        profileBinding(\.preferredDistanceUnit, default: .default())
    }
    private var weightBinding: Binding<WeightUnit> {
        profileBinding(\.preferredWeightUnit, default: .default())
    }
    private var weekStartBinding: Binding<WeekStart> {
        profileBinding(\.weekStart, default: .system)
    }
    private var appearanceBinding: Binding<AppearancePreference> {
        profileBinding(\.appearance, default: .system)
    }
    private var visibilityBinding: Binding<ActivityVisibility> {
        profileBinding(\.defaultVisibility, default: .privateOnly)
    }
    private var hideEndpointsBinding: Binding<Bool> {
        profileBinding(\.hidesRouteEndpointsWhenSharing, default: true)
    }
}

struct ProfileScreen_Previews: PreviewProvider {
    static var previews: some View {
        PreviewHost { ProfileScreen() }
            .previewDisplayName("Profile")

        PreviewHost { ProfileScreen() }
            .preferredColorScheme(.dark)
            .previewDisplayName("Dark")

        PreviewHost { ProfileScreen() }
            .environment(\.sizeCategory, .accessibilityLarge)
            .previewDisplayName("Large text")
    }
}
