import SwiftUI
import CompanionCore

/// Shown once onboarding is complete but no trial or subscription is active.
///
/// There is one plan, so this is a pitch screen rather than a plan picker: the
/// feature list explains what the trial unlocks, one button starts it, and
/// Restore Purchases is always reachable — App Review rejects paywalls that
/// bury it. Dismissing this screen is not possible by design; `RootView`
/// swaps it out the moment `AppModel.requiresPaywall` goes false.
public struct PaywallScreen: View {
    @Environment(AppModel.self) private var model

    private let features: [(symbol: String, text: String)] = [
        ("figure.walk", "Unlimited walk recording and history"),
        ("chart.line.uptrend.xyaxis", "Weekly, monthly and 3-month statistics"),
        ("map", "Explore dog-friendly places nearby"),
        ("trophy", "Streaks, goals and achievements"),
    ]

    public var body: some View {
        @Bindable var model = model

        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: Theme.Space.xl) {
                    VStack(spacing: Theme.Space.s) {
                        Image(systemName: "pawprint.circle.fill")
                            .font(.system(size: 52, weight: .light))
                            .foregroundStyle(Theme.Colour.accent)
                        Text("Companion Pro")
                            .font(.title.weight(.bold))
                        Text("Every walk, every dog, every day.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.Colour.secondaryText)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, Theme.Space.xxl)

                    Card {
                        VStack(alignment: .leading, spacing: Theme.Space.l) {
                            ForEach(features, id: \.text) { feature in
                                HStack(spacing: Theme.Space.m) {
                                    Image(systemName: feature.symbol)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(Theme.Colour.accent)
                                        .frame(width: 28)
                                    Text(feature.text)
                                        .font(.subheadline)
                                    Spacer(minLength: 0)
                                }
                            }
                        }
                    }

                    if let offer = model.subscriptionOffer {
                        VStack(spacing: Theme.Space.xxs) {
                            if let trialDays = offer.trialDays, trialDays > 0 {
                                Text("\(trialDays)-day free trial, then \(offer.displayPrice) / \(offer.period)")
                                    .font(.subheadline.weight(.semibold))
                            } else {
                                Text("\(offer.displayPrice) / \(offer.period)")
                                    .font(.subheadline.weight(.semibold))
                            }
                            Text("Cancel anytime in Settings before the trial ends and you won't be charged.")
                                .font(.caption)
                                .foregroundStyle(Theme.Colour.secondaryText)
                                .multilineTextAlignment(.center)
                        }
                    }

                    if let error = model.subscriptionError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(Theme.Colour.destructive)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(Theme.Space.xl)
            }

            VStack(spacing: Theme.Space.m) {
                PrimaryButton(
                    model.subscriptionOffer?.trialDays.map { $0 > 0 } == true
                        ? "Start Free Trial"
                        : "Subscribe",
                    isLoading: model.isPurchasing,
                    isEnabled: !model.isPurchasing,
                    action: { Task { await model.purchaseSubscription() } }
                )

                Button("Restore Purchases") {
                    Task { await model.restorePurchases() }
                }
                .font(.footnote.weight(.medium))
                .disabled(model.isPurchasing)

                HStack(spacing: Theme.Space.s) {
                    Link("Terms of Use", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                    Text("·").foregroundStyle(Theme.Colour.secondaryText)
                    Link("Privacy Policy", destination: URL(string: "https://jackhartley100.github.io/companion-app/privacy-policy.html")!)
                }
                .font(.caption2)
                .foregroundStyle(Theme.Colour.secondaryText)
            }
            .padding(Theme.Space.xl)
        }
        .background(Theme.Colour.background)
        .task { await model.refreshSubscription() }
    }
}

struct PaywallScreen_Previews: PreviewProvider {
    static var previews: some View {
        PaywallScreen()
            .environment(AppModel(environment: .preview(subscription: .free)))
    }
}
