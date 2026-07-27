import Foundation

/// Apple Health integration, behind a protocol so the app builds and runs with
/// no HealthKit entitlement.
///
/// Only the *owner's* walk is ever written to Health. Nothing about the dog goes
/// into the owner's health record, and no health data is inferred about the dog
/// from it.
public protocol HealthService: Sendable {
    var isAvailable: Bool { get }
    func authorizationStatus() async -> Bool
    func requestAuthorization() async throws -> Bool
    /// Writes a finished walk as a workout on the owner's behalf.
    func saveWorkout(for activity: WalkActivity) async throws
}

public enum HealthServiceError: Error, Sendable, Equatable {
    case unavailable
    case notAuthorised

    public var userMessage: String {
        switch self {
        case .unavailable:
            "Apple Health is not available on this device."
        case .notAuthorised:
            "Companion does not have permission to add workouts to Apple Health. "
            + "You can grant it in the Health app under Sharing › Apps."
        }
    }
}

/// The Health service the MVP ships with: reports unavailable and writes nothing.
///
// TODO: Replace with a HealthKit implementation once the HealthKit capability
// and the Health usage descriptions are added to the app target. Deliberately
// not a hard launch requirement: it needs an entitlement, an App Review
// justification and its own privacy copy.
public struct UnavailableHealthService: HealthService {
    public init() {}
    public var isAvailable: Bool { false }
    public func authorizationStatus() async -> Bool { false }
    public func requestAuthorization() async throws -> Bool { throw HealthServiceError.unavailable }
    public func saveWorkout(for activity: WalkActivity) async throws {
        throw HealthServiceError.unavailable
    }
}
