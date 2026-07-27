import Foundation

/// A capability that may be gated behind a subscription.
///
/// Kept as an enum so that a feature check is a compile-time decision rather
/// than a string scattered through views.
public enum Entitlement: String, Codable, Sendable, CaseIterable, Identifiable {
    case unlimitedHistory
    case advancedTrends
    case multipleGoals
    case routeDiscovery
    case personalisedInsights
    case dataExport
    case trackerFeatures

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .unlimitedHistory: "Full activity history"
        case .advancedTrends: "Advanced trends"
        case .multipleGoals: "Multiple goals"
        case .routeDiscovery: "Route discovery"
        case .personalisedInsights: "Personalised insights"
        case .dataExport: "Data export"
        case .trackerFeatures: "Companion Tracker features"
        }
    }
}

public struct SubscriptionStatus: Sendable, Hashable {
    public let isSubscribed: Bool
    public let entitlements: Set<Entitlement>
    public let expiryDate: Date?
    /// What to call the plan in Settings.
    public let planName: String

    public init(
        isSubscribed: Bool,
        entitlements: Set<Entitlement>,
        expiryDate: Date? = nil,
        planName: String
    ) {
        self.isSubscribed = isSubscribed
        self.entitlements = entitlements
        self.expiryDate = expiryDate
        self.planName = planName
    }

    /// What every owner gets. The MVP ships this to everyone.
    public static let free = SubscriptionStatus(
        isSubscribed: false,
        entitlements: [],
        planName: "Companion"
    )

    public static let premium = SubscriptionStatus(
        isSubscribed: true,
        entitlements: Set(Entitlement.allCases),
        planName: "Companion Premium"
    )

    public func has(_ entitlement: Entitlement) -> Bool {
        entitlements.contains(entitlement)
    }
}

public protocol SubscriptionService: Sendable {
    func status() async -> SubscriptionStatus
    /// Restores purchases made on another device.
    func restore() async throws -> SubscriptionStatus
}

/// The subscription service the MVP ships with.
///
/// Everything the app can currently do is free. No paywall is presented and no
/// feature is withheld, because billing is not implemented and gating a feature
/// that cannot be bought would be a dead end for the owner.
///
// TODO: Replace with a StoreKit 2 implementation once products are configured in
// App Store Connect and Phase 2 entitlement storage exists. The `Entitlement`
// checks scattered through the UI already work; only this type changes.
public struct FreeTierSubscriptionService: SubscriptionService {
    /// Set to `.premium` in a debug build to preview the gated states.
    private let fixed: SubscriptionStatus

    public init(status: SubscriptionStatus = .free) {
        self.fixed = status
    }

    public func status() async -> SubscriptionStatus { fixed }
    public func restore() async throws -> SubscriptionStatus { fixed }
}
