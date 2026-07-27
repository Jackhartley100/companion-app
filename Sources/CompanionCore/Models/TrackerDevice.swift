import Foundation

/// Connection state of a physical tracker.
///
/// - Note: The MVP ships no tracker connectivity. This model exists so that the
///   activity pipeline, settings screen and data model do not need reshaping when
///   a device is introduced. Nothing in the app produces a value other than
///   `.unavailable` today.
public enum TrackerConnectionState: String, Codable, Sendable {
    case unavailable
    case disconnected
    case connecting
    case connected

    public var displayName: String {
        switch self {
        case .unavailable: "Not set up"
        case .disconnected: "Disconnected"
        case .connecting: "Connecting"
        case .connected: "Connected"
        }
    }
}

/// A registered Companion Tracker.
///
// TODO: Populate and persist this model when the tracker programme reaches
// hardware bring-up. It is currently referenced only by `TrackingCapabilities`
// and the Settings integrations row, both of which present it as unavailable.
public struct TrackerDevice: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public var name: String
    public var dogID: UUID?
    public var model: String
    public var firmwareVersion: String?
    public var batteryPercentage: Int?
    public var connectionState: TrackerConnectionState
    public var lastSeenAt: Date?
    public var capabilities: TrackingCapabilities

    public init(
        id: UUID = UUID(),
        name: String,
        dogID: UUID? = nil,
        model: String,
        firmwareVersion: String? = nil,
        batteryPercentage: Int? = nil,
        connectionState: TrackerConnectionState = .unavailable,
        lastSeenAt: Date? = nil,
        capabilities: TrackingCapabilities = []
    ) {
        self.id = id
        self.name = name
        self.dogID = dogID
        self.model = model
        self.firmwareVersion = firmwareVersion
        self.batteryPercentage = batteryPercentage
        self.connectionState = connectionState
        self.lastSeenAt = lastSeenAt
        self.capabilities = capabilities
    }
}
