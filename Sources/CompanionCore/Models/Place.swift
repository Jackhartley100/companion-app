import Foundation

public enum PlaceCategory: String, Codable, Sendable, CaseIterable, Identifiable {
    case park
    case beach
    case woodland
    case securedField
    case cafe
    case pub
    case waterPoint

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .park: "Park"
        case .beach: "Beach"
        case .woodland: "Woodland"
        case .securedField: "Secure field"
        case .cafe: "Café"
        case .pub: "Pub"
        case .waterPoint: "Water point"
        }
    }

    public var symbolName: String {
        switch self {
        case .park: "tree.fill"
        case .beach: "beach.umbrella.fill"
        case .woodland: "leaf.fill"
        case .securedField: "shield.lefthalf.filled"
        case .cafe: "cup.and.saucer.fill"
        case .pub: "fork.knife"
        case .waterPoint: "drop.fill"
        }
    }
}

/// Where the information about a place came from.
public enum PlaceSource: String, Codable, Sendable {
    /// Bundled sample content used to build and demonstrate the Explore screen.
    /// The UI must label these as examples, never as verified live listings.
    case sample
    /// Added by the owner.
    case userSaved
    /// Reserved for a future places provider.
    case remoteProvider

    public var isDemonstrationContent: Bool { self == .sample }
}

/// A dog-friendly destination.
public struct Place: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public var name: String
    public var category: PlaceCategory
    public var coordinate: Coordinate
    public var summary: String
    /// Free-text notes about dog access, e.g. seasonal restrictions.
    public var accessNotes: String?
    /// Whether dogs must be kept on a lead, when it is known.
    public var leadRequired: Bool?
    public var facilities: [String]
    /// Only ever true for information that has actually been checked. Sample
    /// content is never marked verified.
    public var isVerified: Bool
    public var source: PlaceSource
    public var lastVerifiedAt: Date?

    public init(
        id: UUID = UUID(),
        name: String,
        category: PlaceCategory,
        coordinate: Coordinate,
        summary: String,
        accessNotes: String? = nil,
        leadRequired: Bool? = nil,
        facilities: [String] = [],
        isVerified: Bool = false,
        source: PlaceSource = .sample,
        lastVerifiedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.coordinate = coordinate
        self.summary = summary
        self.accessNotes = accessNotes
        self.leadRequired = leadRequired
        self.facilities = facilities
        self.isVerified = isVerified
        self.source = source
        self.lastVerifiedAt = lastVerifiedAt
    }
}
