#if canImport(StoreKit) && !os(Linux)
import StoreKit

/// The one product Companion sells: unrestricted access to the app after a
/// free trial. There is only one tier, so `Entitlement.allCases` is granted in
/// full the moment the subscription is active — no per-feature product list to
/// keep in sync.
public enum CompanionProduct {
    public static let monthlyID = "com.jackhartley.companion.pro.monthly"
}

/// Real billing, backed by StoreKit 2.
///
/// `Transaction.currentEntitlements` is StoreKit's own source of truth, so
/// `status()` never keeps a local cache that could drift from what was
/// actually bought — it asks the store fresh every time. A background task
/// listens to `Transaction.updates` for renewals, cancellations and Ask to Buy
/// approvals that happen while the app isn't the one driving the purchase.
public final class StoreKitSubscriptionService: SubscriptionService, Sendable {
    private let productID: String

    public init(productID: String = CompanionProduct.monthlyID) {
        self.productID = productID
        Task { await Self.listenForTransactionUpdates() }
    }

    public func status() async -> SubscriptionStatus {
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.productID == productID,
                  transaction.revocationDate == nil
            else { continue }
            return SubscriptionStatus(
                isSubscribed: true,
                entitlements: Set(Entitlement.allCases),
                expiryDate: transaction.expirationDate,
                planName: "Companion Pro"
            )
        }
        return .free
    }

    public func offer() async throws -> SubscriptionOffer {
        guard let product = try await Product.products(for: [productID]).first else {
            throw SubscriptionError.productUnavailable
        }
        let trialDays = product.subscription?.introductoryOffer
            .flatMap { offer -> Int? in
                guard offer.paymentMode == .freeTrial else { return nil }
                return offer.period.days
            }
        let period = product.subscription?.subscriptionPeriod.unit.description ?? "month"
        return SubscriptionOffer(displayPrice: product.displayPrice, period: period, trialDays: trialDays)
    }

    public func purchase() async throws -> SubscriptionStatus {
        guard let product = try await Product.products(for: [productID]).first else {
            throw SubscriptionError.productUnavailable
        }
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            guard case .verified(let transaction) = verification else {
                throw SubscriptionError.notCompleted
            }
            await transaction.finish()
            return await status()
        case .userCancelled, .pending:
            throw SubscriptionError.notCompleted
        @unknown default:
            throw SubscriptionError.notCompleted
        }
    }

    public func restore() async throws -> SubscriptionStatus {
        try await AppStore.sync()
        return await status()
    }

    /// Applies renewals, cancellations and Ask to Buy approvals that arrive
    /// outside a purchase this app instance initiated.
    private static func listenForTransactionUpdates() async {
        for await result in Transaction.updates {
            guard case .verified(let transaction) = result else { continue }
            await transaction.finish()
        }
    }
}

private extension Product.SubscriptionPeriod.Unit {
    var description: String {
        switch self {
        case .day: "day"
        case .week: "week"
        case .month: "month"
        case .year: "year"
        @unknown default: "month"
        }
    }
}

private extension Product.SubscriptionPeriod {
    /// The offer's length in days, for display as "N-day free trial".
    var days: Int {
        switch unit {
        case .day: value
        case .week: value * 7
        case .month: value * 30
        case .year: value * 365
        @unknown default: value
        }
    }
}
#endif
