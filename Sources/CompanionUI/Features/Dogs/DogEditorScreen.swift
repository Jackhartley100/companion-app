import SwiftUI
import CompanionCore

/// Creates or edits a dog.
///
/// Only the name is required. Rescue dogs have no known birthday, mixed breeds
/// have no single breed, and plenty of owners do not know a current weight — so
/// "unknown" is a first-class answer everywhere rather than a blocked field.
struct DogEditorScreen: View {
    enum Mode: Equatable {
        case create
        case edit(Dog)

        var existingDog: Dog? {
            if case .edit(let dog) = self { return dog }
            return nil
        }
    }

    let mode: Mode
    let onSave: (Dog) async -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var breedName: String = ""
    @State private var isMixedBreed = false
    @State private var ageKind: AgeKind = .unknown
    @State private var dateOfBirth = Date()
    @State private var estimatedYears = 2
    @State private var estimatedMonths = 0
    @State private var sex: DogSex = .unspecified
    @State private var weightText: String = ""
    @State private var activityLevel: ActivityLevel = .moderate
    @State private var photoReference: String?
    @State private var photoData: Data?
    @State private var isSaving = false
    @State private var didPopulate = false
    @FocusState private var isFieldFocused: Bool

    enum AgeKind: String, CaseIterable, Identifiable {
        case dateOfBirth
        case estimate
        case unknown

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .dateOfBirth: "Known birthday"
            case .estimate: "Approximate"
            case .unknown: "Not sure"
            }
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xxl) {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Text(mode.existingDog == nil ? "Add your dog" : "Edit \(trimmedName)")
                        .font(Theme.Typeface.heroTitle(.title))
                        .foregroundStyle(Theme.Colour.primaryText)
                    Text("Everything except the name can be added or changed later.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.Colour.secondaryText)
                }

                photoSection

                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    SectionHeader("What's their name?")
                    TextField("Name", text: $name)
                        .textContentType(.name)
                        .focused($isFieldFocused)
                        .submitLabel(.done)
                        .onSubmit { isFieldFocused = false }
                        .foregroundStyle(Theme.Colour.primaryText)
                        .padding(Theme.Space.m)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.Colour.surface)
                        .clipShape(Capsule())
                }

                ageSection
                aboutSection

                PrimaryButton(
                    mode.existingDog == nil ? "Add \(trimmedName.isEmpty ? "Dog" : trimmedName)" : "Save",
                    trailingSymbolName: "checkmark",
                    isLoading: isSaving,
                    isEnabled: !trimmedName.isEmpty
                ) {
                    Task { await save() }
                }
            }
            .padding(Theme.Space.xl)
            // `TextField`, `Menu` and `Toggle` labels don't reliably pick up
            // `.fontDesign` from the environment the way plain `Text` does —
            // see the same note on `OwnerDetailsScreen`.
            .fontDesign(.rounded)
        }
        .background(Theme.Colour.background)
        .compactNavigationTitle()
        // Typing the name brings up the keyboard, which covers the save button
        // at the bottom of the screen. Swiping down dismisses it — the only
        // way out now that there's no keyboard toolbar button.
        .scrollDismissesKeyboardInteractively()
        .onAppear(perform: populateIfNeeded)
        .tint(Theme.Colour.accent)
    }

    private var photoSection: some View {
        VStack(spacing: Theme.Space.m) {
            ZStack {
                if let photoData, let image = Image(data: photoData) {
                    image.resizable().scaledToFill()
                } else {
                    Circle().fill(Theme.Colour.surface)
                    Image(systemName: "pawprint.fill")
                        .font(.system(size: 44, weight: .regular))
                        .foregroundStyle(Theme.Colour.secondaryText)
                }
            }
            .frame(width: 140, height: 140)
            .clipShape(Circle())
            .overlay(alignment: .bottomTrailing) {
                Circle()
                    .fill(Theme.Colour.accent)
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: "camera.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.black)
                    )
                    .overlay(Circle().strokeBorder(Theme.Colour.background, lineWidth: 3))
                    .allowsHitTesting(false)
            }

            AddWalkPhotoButton(
                label: photoData == nil ? "Add a Photo" : "Change Photo",
                symbolName: "camera.fill"
            ) { data in
                photoData = data
                photoReference = try? await model.environment.imageStore.store(data)
            }
            .font(.subheadline.weight(.medium))
        }
        .frame(maxWidth: .infinity)
    }

    private var ageSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            SectionHeader("How old are they?")

            Picker("Age", selection: $ageKind) {
                ForEach(AgeKind.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)

            switch ageKind {
            case .dateOfBirth:
                HStack {
                    Text("Date of birth")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.Colour.primaryText)
                    Spacer(minLength: 0)
                    DatePicker(
                        "",
                        selection: $dateOfBirth,
                        in: ...Date(),
                        displayedComponents: .date
                    )
                    .labelsHidden()
                }
                .padding(Theme.Space.m)
                .frame(maxWidth: .infinity)
                .background(Theme.Colour.surface)
                .clipShape(Capsule())
            case .estimate:
                VStack(spacing: Theme.Space.s) {
                    Stepper(value: $estimatedYears, in: 0...25) {
                        Text("About \(estimatedYears) \(estimatedYears == 1 ? "year" : "years")")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.Colour.primaryText)
                    }
                    .padding(Theme.Space.m)
                    .background(Theme.Colour.surface)
                    .clipShape(Capsule())

                    Stepper(value: $estimatedMonths, in: 0...11) {
                        Text("and \(estimatedMonths) \(estimatedMonths == 1 ? "month" : "months")")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.Colour.primaryText)
                    }
                    .padding(Theme.Space.m)
                    .background(Theme.Colour.surface)
                    .clipShape(Capsule())
                }
            case .unknown:
                EmptyView()
            }

            Text("If you adopted your dog and their birthday is not known, an estimate is fine.")
                .font(.caption)
                .foregroundStyle(Theme.Colour.secondaryText)
        }
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            SectionHeader("Tell us more")

            TextField("Breed", text: $breedName)
                .foregroundStyle(Theme.Colour.primaryText)
                .padding(Theme.Space.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.Colour.surface)
                .clipShape(Capsule())

            Toggle("Mixed breed", isOn: $isMixedBreed)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.Colour.primaryText)
                .padding(Theme.Space.m)
                .background(Theme.Colour.surface)
                .clipShape(Capsule())

            PillPickerRow(title: "Sex", selection: $sex, displayName: \.displayName)

            HStack {
                Text("Weight")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.Colour.primaryText)
                Spacer()
                TextField("Optional", text: $weightText)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 90)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                Text(model.formatters.weightUnit == .kilograms ? "kg" : "lb")
                    .foregroundStyle(Theme.Colour.secondaryText)
            }
            .padding(Theme.Space.m)
            .background(Theme.Colour.surface)
            .clipShape(Capsule())

            PillPickerRow(title: "Usual activity", selection: $activityLevel, displayName: \.displayName)
        }
    }

    private func populateIfNeeded() {
        guard !didPopulate else { return }
        didPopulate = true
        guard let dog = mode.existingDog else { return }

        name = dog.name
        breedName = dog.breedName ?? ""
        isMixedBreed = dog.isMixedBreed
        sex = dog.sex
        activityLevel = dog.activityLevel
        photoReference = dog.imageReference
        if let weight = dog.weightKilograms {
            let converted = Measurement(value: weight, unit: UnitMass.kilograms)
                .converted(to: model.formatters.weightUnit.unit).value
            weightText = String(format: "%.1f", converted)
        }
        switch dog.age {
        case .dateOfBirth(let date):
            ageKind = .dateOfBirth
            dateOfBirth = date
        case .estimatedMonths(let months):
            ageKind = .estimate
            estimatedYears = months / 12
            estimatedMonths = months % 12
        case .unknown:
            ageKind = .unknown
        }

        if let reference = dog.imageReference {
            Task { photoData = try? await model.environment.imageStore.data(for: reference) }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        let age: DogAge = switch ageKind {
        case .dateOfBirth: .dateOfBirth(dateOfBirth)
        case .estimate: .estimatedMonths(estimatedYears * 12 + estimatedMonths)
        case .unknown: .unknown
        }

        // Entered in the owner's preferred unit; stored in kilograms.
        let weightKilograms: Double? = {
            guard let entered = Double(weightText.replacingOccurrences(of: ",", with: ".")),
                  entered > 0 else { return nil }
            return Measurement(value: entered, unit: model.formatters.weightUnit.unit)
                .converted(to: .kilograms).value
        }()

        var dog = mode.existingDog ?? Dog(name: trimmedName, sortIndex: model.dogs.count)
        dog.name = trimmedName
        dog.imageReference = photoReference
        dog.breedName = breedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil
            : breedName.trimmingCharacters(in: .whitespacesAndNewlines)
        dog.isMixedBreed = isMixedBreed
        dog.age = age
        dog.sex = sex
        dog.weightKilograms = weightKilograms
        dog.activityLevel = activityLevel

        await onSave(dog)
    }
}

struct DogEditorScreen_Previews: PreviewProvider {
    static var previews: some View {
        PreviewHost {
            NavigationStack { DogEditorScreen(mode: .create) { _ in } }
        }
        .previewDisplayName("Add a dog")

        PreviewHost {
            NavigationStack {
                DogEditorScreen(mode: .edit(DemoDataProvider.roxy())) { _ in }
            }
        }
        .previewDisplayName("Edit Roxy")

        PreviewHost {
            NavigationStack {
                DogEditorScreen(mode: .edit(DemoDataProvider.bailey())) { _ in }
            }
        }
        .preferredColorScheme(.dark)
        .previewDisplayName("Edit Bailey — dark")
    }
}
