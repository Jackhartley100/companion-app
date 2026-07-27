import Foundation
import CoreLocation

/// The app's own view of location permission, independent of CoreLocation's enum.
public enum LocationAuthorizationStatus: String, Sendable, Hashable {
    case notDetermined
    case denied
    case restricted
    /// Granted only while the app is in the foreground.
    case whenInUse
    /// Granted including background use.
    case always

    public var isUsable: Bool {
        self == .whenInUse || self == .always
    }

    /// The failure to show when a recording cannot start with this status.
    public var failure: RecordingFailure? {
        switch self {
        case .denied: .locationPermissionDenied
        case .restricted: .locationPermissionRestricted
        case .notDetermined, .whenInUse, .always: nil
        }
    }

    init(_ status: CLAuthorizationStatus) {
        switch status {
        case .notDetermined: self = .notDetermined
        case .restricted: self = .restricted
        case .denied: self = .denied
        case .authorizedAlways: self = .always
        #if os(iOS)
        case .authorizedWhenInUse: self = .whenInUse
        #else
        case .authorized: self = .whenInUse
        #endif
        @unknown default: self = .notDetermined
        }
    }
}

/// Reports and requests location permission.
///
/// Separated from the tracking source so that the permission explanation screen
/// and the Settings screen can read and request authorisation without spinning
/// up a recording session.
public protocol LocationPermissionProviding: Sendable {
    func currentStatus() async -> LocationAuthorizationStatus
    /// Whether Location Services are enabled for the whole device.
    func servicesEnabled() async -> Bool
    /// Requests "when in use". Returns the resulting status.
    ///
    /// - Note: Companion asks for "when in use" only. Recording continues with
    ///   the screen locked via the background location mode plus
    ///   `allowsBackgroundLocationUpdates`, which "when in use" permits while a
    ///   session is active. Asking for "always" would grant the app more than it
    ///   needs and is harder to justify to the owner.
    func requestWhenInUseAuthorization() async -> LocationAuthorizationStatus
}

/// A permission provider that returns a fixed answer. For previews and tests.
public struct StubLocationPermissionProvider: LocationPermissionProviding {
    public let status: LocationAuthorizationStatus
    public let enabled: Bool

    public init(status: LocationAuthorizationStatus = .whenInUse, enabled: Bool = true) {
        self.status = status
        self.enabled = enabled
    }

    public func currentStatus() async -> LocationAuthorizationStatus { status }
    public func servicesEnabled() async -> Bool { enabled }
    public func requestWhenInUseAuthorization() async -> LocationAuthorizationStatus { status }
}
