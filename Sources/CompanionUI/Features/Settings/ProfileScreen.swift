import SwiftUI
import CompanionCore

/// Account, dogs, preferences, permissions, privacy and support.
struct ProfileScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.formatters) private var formatters

    @State private var isAddingDog = false
    @State private var showsDeleteHistoryConfirmation = false
    @State private var showsSignOutConfirmation = false
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
                supportSection
                signOutSection
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
            .confirmationDialog(
                "Sign out of Companion?",
                isPresented: $showsSignOutConfirmation,
                titleVisibility: .visible
            ) {
                Button("Sign Out", role: .destructive) {
                    Task {
                        Haptics.play(.destructiveConfirmed)
                        await model.signOut()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "Companion doesn't have accounts that sync between devices yet, so signing "
                    + "out removes your profile, dogs and activity history from this iPhone. "
                    + "This cannot be undone."
                )
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
                StoredImage(
                    reference: model.profile?.imageReference,
                    imageStore: model.environment.imageStore
                ) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(Theme.Colour.accent)
                }
                .frame(width: 52, height: 52)
                .clipShape(Circle())
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
            Text("Your data is stored on this iPhone and does not sync to other devices.")
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
            // The whole row opens Settings, regardless of the current status —
            // that is the only lever the app actually has. Previously this only
            // appeared once permission had been denied, so a row already showing
            // "Allowed" had nothing tappable in it at all.
            permissionRow(
                title: "Location",
                detail: locationDetail,
                isGranted: locationStatus.isUsable,
                action: { Platform.openAppSettings() }
            )
            permissionRow(
                title: "Photos",
                detail: "Asked for when you add a photo to a dog or a walk.",
                isGranted: nil,
                action: nil
            )
        } header: {
            Text("Permissions")
        } footer: {
            Text("Location is used only while a walk is being recorded. Tap it to review or change the setting.")
        }
    }

    /// - Parameter isGranted: `nil` when granted/not-granted does not apply —
    ///   Photos uses the modern picker, which needs no system permission the
    ///   app can check, so a checkmark there would just be a hardcoded guess.
    /// - Parameter action: `nil` for a row with nothing to do when tapped.
    private func permissionRow(
        title: String,
        detail: String,
        isGranted: Bool?,
        action: (() -> Void)?
    ) -> some View {
        Group {
            if let action {
                Button(action: action) {
                    permissionRowContent(title: title, detail: detail, isGranted: isGranted, showsChevron: true)
                }
                .buttonStyle(.plain)
            } else {
                permissionRowContent(title: title, detail: detail, isGranted: isGranted, showsChevron: false)
            }
        }
    }

    private func permissionRowContent(
        title: String,
        detail: String,
        isGranted: Bool?,
        showsChevron: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.s) {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                HStack {
                    Text(title)
                    Spacer()
                    if let isGranted {
                        Image(systemName: isGranted ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isGranted ? Theme.Colour.success : Theme.Colour.secondaryText)
                    }
                }
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Theme.Colour.secondaryText)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.Colour.secondaryText.opacity(0.6))
            }
        }
        .padding(.vertical, Theme.Space.xxs)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(isGranted == true ? "Allowed" : (isGranted == false ? "Not allowed" : ""))
        .accessibilityHint(showsChevron ? "Opens Settings" : "")
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

    private var signOutSection: some View {
        Section {
            Button(
                "Sign Out",
                systemImage: "rectangle.portrait.and.arrow.right",
                role: .destructive
            ) {
                showsSignOutConfirmation = true
            }
        } footer: {
            Text(
                "Companion doesn't have accounts that sync yet, so signing out removes "
                + "your profile, dogs and activity history from this iPhone."
            )
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
