import Foundation

/// The person using the app. One profile exists per installation in the MVP.
public struct UserProfile: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public var firstName: String
    /// Filename of the owner's photo inside the app's image store. See `ImageStore`.
    public var imageReference: String?
    public var preferredDistanceUnit: DistanceUnit
    public var preferredWeightUnit: WeightUnit
    public var weekStart: WeekStart
    public var appearance: AppearancePreference
    /// The dog shown by default on Today and preselected when starting a walk.
    public var defaultDogID: UUID?
    /// Visibility applied to newly recorded walks unless the owner changes it.
    public var defaultVisibility: ActivityVisibility
    /// When true, shared route images omit a radius around the start and finish.
    public var hidesRouteEndpointsWhenSharing: Bool
    public var onboardingCompleted: Bool
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        firstName: String = "",
        imageReference: String? = nil,
        preferredDistanceUnit: DistanceUnit = .default(),
        preferredWeightUnit: WeightUnit = .default(),
        weekStart: WeekStart = .system,
        appearance: AppearancePreference = .system,
        defaultDogID: UUID? = nil,
        defaultVisibility: ActivityVisibility = .privateOnly,
        hidesRouteEndpointsWhenSharing: Bool = true,
        onboardingCompleted: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.firstName = firstName
        self.imageReference = imageReference
        self.preferredDistanceUnit = preferredDistanceUnit
        self.preferredWeightUnit = preferredWeightUnit
        self.weekStart = weekStart
        self.appearance = appearance
        self.defaultDogID = defaultDogID
        self.defaultVisibility = defaultVisibility
        self.hidesRouteEndpointsWhenSharing = hidesRouteEndpointsWhenSharing
        self.onboardingCompleted = onboardingCompleted
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
