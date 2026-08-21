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

/// What the paywall shows before anyone has bought anything: a price, a
/// billing period, and the free-trial length, all pre-formatted by StoreKit so
/// the UI never assembles currency strings itself.
public struct SubscriptionOffer: Sendable, Hashable {
    public let displayPrice: String
    public let period: String
    public let trialDays: Int?

    public init(displayPrice: String, period: String, trialDays: Int?) {
        self.displayPrice = displayPrice
        self.period = period
        self.trialDays = trialDays
    }
}

public enum SubscriptionError: Error, Sendable {
    /// The purchase sheet was dismissed, or Ask to Buy is pending, or the
    /// account is otherwise not immediately entitled. Not a failure worth a
    /// banner — the owner simply isn't subscribed yet.
    case notCompleted
    case productUnavailable
}

public protocol SubscriptionService: Sendable {
    func status() async -> SubscriptionStatus
    /// The current price and trial terms, fetched fresh from the store.
    func offer() async throws -> SubscriptionOffer
    /// Starts the purchase (or trial) flow and returns the resulting status.
    func purchase() async throws -> SubscriptionStatus
    /// Restores purchases made on another device.
    func restore() async throws -> SubscriptionStatus
}

/// A fixed-answer subscription service for demo mode, previews and tests.
///
/// No store is contacted; `status` is whatever it was constructed with, and
/// `purchase`/`restore` immediately "succeed" into `.premium` so screens that
/// simulate the happy path don't need a real StoreKit transaction.
public struct FreeTierSubscriptionService: SubscriptionService {
    private let fixed: SubscriptionStatus

    public init(status: SubscriptionStatus = .free) {
        self.fixed = status
    }

    public func status() async -> SubscriptionStatus { fixed }

    public func offer() async throws -> SubscriptionOffer {
        SubscriptionOffer(displayPrice: "£4.99", period: "month", trialDays: 7)
    }

    public func purchase() async throws -> SubscriptionStatus { .premium }
    public func restore() async throws -> SubscriptionStatus { fixed }
}
