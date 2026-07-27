import SwiftUI
import CompanionCore

/// A screen with nothing in it yet.
///
/// Empty states explain what will appear and offer the action that fills them,
/// so a new owner's first screen is useful rather than blank.
public struct EmptyStateView: View {
    private let symbolName: String
    private let title: String
    private let message: String
    private let actionTitle: String?
    private let action: (() -> Void)?

    public init(
        symbolName: String,
        title: String,
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.symbolName = symbolName
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        VStack(spacing: Theme.Space.l) {
            Image(systemName: symbolName)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Theme.Colour.accent.opacity(0.7))
                .accessibilityHidden(true)

            VStack(spacing: Theme.Space.s) {
                Text(title)
                    .font(Theme.Typeface.cardTitle)
                    .foregroundStyle(Theme.Colour.primaryText)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colour.secondaryText)
                    .multilineTextAlignment(.center)
            }

            if let actionTitle, let action {
                PrimaryButton(actionTitle, action: action)
                    .frame(maxWidth: 280)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Space.xl)
    }
}

/// Something went wrong, explained in terms of what happened, whether the
/// owner's data is safe, and what they can do next.
public struct ErrorStateView: View {
    private let title: String
    private let message: String
    private let reassurance: String?
    private let retryTitle: String?
    private let retry: (() -> Void)?
    private let secondaryTitle: String?
    private let secondaryAction: (() -> Void)?

    public init(
        title: String,
        message: String,
        reassurance: String? = nil,
        retryTitle: String? = "Try Again",
        retry: (() -> Void)? = nil,
        secondaryTitle: String? = nil,
        secondaryAction: (() -> Void)? = nil
    ) {
        self.title = title
        self.message = message
        self.reassurance = reassurance
        self.retryTitle = retryTitle
        self.retry = retry
        self.secondaryTitle = secondaryTitle
        self.secondaryAction = secondaryAction
    }

    /// Builds the view straight from a recording failure so the wording lives
    /// with the error type rather than being restated in each screen.
    public init(
        failure: RecordingFailure,
        retry: (() -> Void)? = nil,
        openSettings: (() -> Void)? = nil
    ) {
        self.init(
            title: failure.title,
            message: failure.message,
            reassurance: failure.dataIsSafe ? "Nothing you have recorded has been lost." : nil,
            retryTitle: retry == nil ? nil : "Try Again",
            retry: retry,
            secondaryTitle: failure.requiresSystemSettings ? "Open Settings" : nil,
            secondaryAction: failure.requiresSystemSettings
                ? (openSettings ?? { Platform.openAppSettings() })
                : nil
        )
    }

    public var body: some View {
        VStack(spacing: Theme.Space.l) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Theme.Colour.warning)
                .accessibilityHidden(true)

            VStack(spacing: Theme.Space.s) {
                Text(title)
                    .font(Theme.Typeface.cardTitle)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colour.secondaryText)
                    .multilineTextAlignment(.center)
                if let reassurance {
                    Text(reassurance)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Theme.Colour.success)
                        .multilineTextAlignment(.center)
                }
            }

            VStack(spacing: Theme.Space.s) {
                if let retryTitle, let retry {
                    PrimaryButton(retryTitle, action: retry)
                }
                if let secondaryTitle, let secondaryAction {
                    SecondaryButton(secondaryTitle, action: secondaryAction)
                }
            }
            .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Space.xl)
    }
}

public struct LoadingStateView: View {
    private let message: String

    public init(message: String = "Loading") {
        self.message = message
    }

    public var body: some View {
        VStack(spacing: Theme.Space.m) {
            ProgressView()
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.Colour.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.Space.xl)
        .accessibilityElement(children: .combine)
    }
}

/// Explains why a permission is needed *before* the system prompt appears.
///
/// The system alert allows one sentence and one chance. This screen is where the
/// owner actually decides, so it says what the data is used for, when it is
/// collected, and what stays private.
public struct PermissionExplanationView: View {
    public struct Point: Identifiable {
        public let id = UUID()
        public let symbolName: String
        public let title: String
        public let detail: String

        public init(symbolName: String, title: String, detail: String) {
            self.symbolName = symbolName
            self.title = title
            self.detail = detail
        }
    }

    private let symbolName: String
    private let title: String
    private let summary: String
    private let points: [Point]
    private let allowTitle: String
    private let onAllow: () -> Void
    private let onSkip: (() -> Void)?

    public init(
        symbolName: String,
        title: String,
        summary: String,
        points: [Point],
        allowTitle: String,
        onAllow: @escaping () -> Void,
        onSkip: (() -> Void)? = nil
    ) {
        self.symbolName = symbolName
        self.title = title
        self.summary = summary
        self.points = points
        self.allowTitle = allowTitle
        self.onAllow = onAllow
        self.onSkip = onSkip
    }

    /// The location explanation, which every walk depends on.
    public static func location(
        onAllow: @escaping () -> Void,
        onSkip: (() -> Void)? = nil
    ) -> PermissionExplanationView {
        PermissionExplanationView(
            symbolName: "location.circle.fill",
            title: "Companion needs your location",
            summary: "It is what draws your route on the map and measures how far you walked.",
            points: [
                Point(
                    symbolName: "map",
                    title: "Only while you are recording",
                    detail: "Location is collected when a walk is running and stops when you finish."
                ),
                Point(
                    symbolName: "iphone",
                    title: "Stored on your iPhone",
                    detail: "Your routes stay on this device. Nothing is uploaded anywhere."
                ),
                Point(
                    symbolName: "lock",
                    title: "Private by default",
                    detail: "New walks are private, and you can delete any of them at any time."
                )
            ],
            allowTitle: "Continue",
            onAllow: onAllow,
            onSkip: onSkip
        )
    }

    public var body: some View {
        VStack(spacing: Theme.Space.xl) {
            VStack(spacing: Theme.Space.m) {
                Image(systemName: symbolName)
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(Theme.Colour.accent)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colour.secondaryText)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: Theme.Space.l) {
                ForEach(points) { point in
                    HStack(alignment: .top, spacing: Theme.Space.m) {
                        Image(systemName: point.symbolName)
                            .font(.body)
                            .foregroundStyle(Theme.Colour.accent)
                            .frame(width: 26)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                            Text(point.title).font(.subheadline.weight(.semibold))
                            Text(point.detail)
                                .font(.footnote)
                                .foregroundStyle(Theme.Colour.secondaryText)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }

            Spacer(minLength: 0)

            VStack(spacing: Theme.Space.s) {
                PrimaryButton(allowTitle, action: onAllow)
                if let onSkip {
                    Button("Not now", action: onSkip)
                        .font(.subheadline)
                        .foregroundStyle(Theme.Colour.secondaryText)
                        .frame(minHeight: Theme.minimumTapTarget)
                }
            }
        }
        .padding(Theme.Space.xl)
    }
}

/// Marks a capability that a future subscription would unlock.
///
/// Nothing in the MVP is actually withheld, so this is used only where a feature
/// is genuinely not built yet, and it says so rather than dangling a purchase
/// that cannot be made.
public struct PremiumFeatureLock: View {
    private let entitlement: Entitlement
    private let message: String

    public init(entitlement: Entitlement, message: String) {
        self.entitlement = entitlement
        self.message = message
    }

    public var body: some View {
        HStack(spacing: Theme.Space.m) {
            Image(systemName: "sparkles")
                .foregroundStyle(Theme.Colour.secondaryAccent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(entitlement.displayName).font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(Theme.Colour.secondaryText)
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Space.m)
        .background(Theme.Colour.secondaryAccent.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// The wording used wherever the app comes close to sounding like health advice.
public struct VeterinaryDisclaimer: View {
    public init() {}

    public var body: some View {
        Text(
            "Activity needs vary by breed, age, health and individual circumstances. "
            + "Consult a veterinary professional about your dog's specific needs."
        )
        .font(.footnote)
        .foregroundStyle(Theme.Colour.secondaryText)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct StateViews_Previews: PreviewProvider {
    static var previews: some View {
        EmptyStateView(
            symbolName: "figure.walk.motion",
            title: "No walks yet",
            message: "Your walks will appear here, with the route, distance and time for each one.",
            actionTitle: "Start your first walk"
        ) {}
        .previewDisplayName("Empty")

        ErrorStateView(failure: .locationPermissionDenied) {}
            .previewDisplayName("Error — permission")

        ErrorStateView(failure: .saveFailed(reason: "there was not enough space on this iPhone")) {}
            .previewDisplayName("Error — save failed")

        PermissionExplanationView.location(onAllow: {}, onSkip: {})
            .previewDisplayName("Permission explanation")

        PermissionExplanationView.location(onAllow: {}, onSkip: {})
            .preferredColorScheme(.dark)
            .previewDisplayName("Permission — dark")

        VStack(spacing: Theme.Space.l) {
            LoadingStateView(message: "Loading your walks")
            PremiumFeatureLock(
                entitlement: .advancedTrends,
                message: "Longer comparisons are coming in a future update."
            )
            VeterinaryDisclaimer()
        }
        .padding()
        .previewDisplayName("Loading, lock and disclaimer")
    }
}
