import Foundation

/// How much exercise the dog is used to. Used only to tailor suggested goals and
/// wording — never presented as veterinary guidance.
public enum ActivityLevel: String, Codable, Sendable, CaseIterable, Identifiable {
    case relaxed
    case moderate
    case active
    case veryActive

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .relaxed: "Relaxed"
        case .moderate: "Moderate"
        case .active: "Active"
        case .veryActive: "Very active"
        }
    }

    public var summary: String {
        switch self {
        case .relaxed: "Short, gentle walks"
        case .moderate: "A steady walk once or twice a day"
        case .active: "Long walks and plenty of running"
        case .veryActive: "Needs a lot of exercise every day"
        }
    }
}

public enum DogSex: String, Codable, Sendable, CaseIterable, Identifiable {
    case female
    case male
    case unspecified

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .female: "Female"
        case .male: "Male"
        case .unspecified: "Prefer not to say"
        }
    }
}

/// How much the owner knows about the dog's age.
///
/// Rescue dogs frequently have no known birthday, so an estimate must be a
/// first-class option rather than a missing value.
public enum DogAge: Codable, Sendable, Hashable {
    case dateOfBirth(Date)
    /// An approximate age in whole months, e.g. "about 3 years old" == 36.
    case estimatedMonths(Int)
    case unknown

    /// Age in months at `date`, when it can be determined.
    public func months(asOf date: Date = Date(), calendar: Calendar = .current) -> Int? {
        switch self {
        case .dateOfBirth(let birth):
            guard birth <= date else { return 0 }
            return calendar.dateComponents([.month], from: birth, to: date).month
        case .estimatedMonths(let months):
            return months
        case .unknown:
            return nil
        }
    }

    public var isEstimate: Bool {
        if case .estimatedMonths = self { return true }
        return false
    }
}

/// A dog belonging to the owner. Activities reference dogs by identifier so that
/// a single walk can include more than one dog.
public struct Dog: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public var name: String
    /// Filename inside the app's image store, not an absolute path — absolute
    /// paths break when the app container is relocated between launches.
    public var imageReference: String?
    public var breedName: String?
    public var isMixedBreed: Bool
    public var age: DogAge
    public var sex: DogSex
    /// Always stored in kilograms; `UserProfile.preferredWeightUnit` controls display.
    public var weightKilograms: Double?
    public var activityLevel: ActivityLevel
    /// Ordering on the dog selector and Today screen.
    public var sortIndex: Int
    /// Archived dogs are hidden from selection but keep their activity history.
    public var isArchived: Bool
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        imageReference: String? = nil,
        breedName: String? = nil,
        isMixedBreed: Bool = false,
        age: DogAge = .unknown,
        sex: DogSex = .unspecified,
        weightKilograms: Double? = nil,
        activityLevel: ActivityLevel = .moderate,
        sortIndex: Int = 0,
        isArchived: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.imageReference = imageReference
        self.breedName = breedName
        self.isMixedBreed = isMixedBreed
        self.age = age
        self.sex = sex
        self.weightKilograms = weightKilograms
        self.activityLevel = activityLevel
        self.sortIndex = sortIndex
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// First letter of the name, used by `DogAvatar` when no photo exists.
    public var initial: String {
        String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)).uppercased()
    }

    /// A human description of the breed that copes with unknown and mixed breeds.
    public var breedDescription: String {
        switch (breedName, isMixedBreed) {
        case (let breed?, true) where !breed.isEmpty: "\(breed) mix"
        case (let breed?, false) where !breed.isEmpty: breed
        case (_, true): "Mixed breed"
        default: "Breed not set"
        }
    }
}
