import SwiftUI
import PhotosUI
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
    @State private var photoItem: PhotosPickerItem?
    @State private var photoReference: String?
    @State private var photoData: Data?
    @State private var isSaving = false
    @State private var didPopulate = false

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
        Form {
            photoSection
            detailsSection
            ageSection
            aboutSection
            saveSection
        }
        .navigationTitle(mode.existingDog == nil ? "Add your dog" : "Edit \(trimmedName)")
        .compactNavigationTitle()
        .onAppear(perform: populateIfNeeded)
        .task(id: photoItem) { await loadSelectedPhoto() }
    }

    private var photoSection: some View {
        Section {
            HStack {
                Spacer()
                VStack(spacing: Theme.Space.m) {
                    ZStack {
                        if let photoData, let image = Image(data: photoData) {
                            image.resizable().scaledToFill()
                        } else {
                            Circle().fill(Theme.Colour.accent.opacity(0.14))
                            Image(systemName: "camera")
                                .font(.title2)
                                .foregroundStyle(Theme.Colour.accent)
                        }
                    }
                    .frame(width: 108, height: 108)
                    .clipShape(Circle())

                    PhotosPicker(
                        photoData == nil ? "Add a photo" : "Change photo",
                        selection: $photoItem,
                        matching: .images
                    )
                    .font(.subheadline)
                }
                Spacer()
            }
            .listRowBackground(Color.clear)
        } footer: {
            Text("Optional. A photo makes it easier to tell your dogs apart at a glance.")
        }
    }

    private var detailsSection: some View {
        Section("Name") {
            TextField("Name", text: $name)
                .textContentType(.name)
        }
    }

    private var ageSection: some View {
        Section {
            Picker("Age", selection: $ageKind) {
                ForEach(AgeKind.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)

            switch ageKind {
            case .dateOfBirth:
                DatePicker(
                    "Date of birth",
                    selection: $dateOfBirth,
                    in: ...Date(),
                    displayedComponents: .date
                )
            case .estimate:
                Stepper("About \(estimatedYears) \(estimatedYears == 1 ? "year" : "years")",
                        value: $estimatedYears, in: 0...25)
                Stepper("and \(estimatedMonths) \(estimatedMonths == 1 ? "month" : "months")",
                        value: $estimatedMonths, in: 0...11)
            case .unknown:
                EmptyView()
            }
        } header: {
            Text("Age")
        } footer: {
            Text("If you adopted your dog and their birthday is not known, an estimate is fine.")
        }
    }

    private var aboutSection: some View {
        Section("About") {
            TextField("Breed", text: $breedName)
            Toggle("Mixed breed", isOn: $isMixedBreed)

            Picker("Sex", selection: $sex) {
                ForEach(DogSex.allCases) { Text($0.displayName).tag($0) }
            }

            HStack {
                Text("Weight")
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

            Picker("Usual activity", selection: $activityLevel) {
                ForEach(ActivityLevel.allCases) { level in
                    VStack(alignment: .leading) {
                        Text(level.displayName)
                        Text(level.summary).font(.caption)
                    }
                    .tag(level)
                }
            }
        }
    }

    private var saveSection: some View {
        Section {
            PrimaryButton(
                mode.existingDog == nil ? "Add \(trimmedName.isEmpty ? "Dog" : trimmedName)" : "Save",
                isLoading: isSaving,
                isEnabled: !trimmedName.isEmpty
            ) {
                Task { await save() }
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        } footer: {
            Text("Everything except the name can be added or changed later.")
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

    private func loadSelectedPhoto() async {
        guard let photoItem else { return }
        guard let data = try? await photoItem.loadTransferable(type: Data.self) else { return }
        photoData = data
        photoReference = try? await model.environment.imageStore.store(data)
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
