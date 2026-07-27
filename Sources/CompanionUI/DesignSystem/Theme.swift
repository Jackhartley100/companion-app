import SwiftUI

/// The app's design tokens.
///
/// Colours are semantic — views ask for `Theme.Colour.accent`, never for a
/// specific green — so appearance can change in one place and so that light and
/// dark are defined together rather than drifting apart.
public enum Theme {
    /// Product naming, kept in one place because "Companion" is a working name.
    public enum Brand {
        public static let name = "Companion"
        public static let tagline = "Every walk becomes part of their story."
        public static let supportingLine =
            "Track walks, build healthy routines and keep a lifetime of adventures with your dog."
    }

    public enum Colour {
        /// A deep, natural green. Restrained enough to sit under text and behind
        /// large type without shouting, and distinct from the system blue so the
        /// app does not read as unstyled.
        public static let accent = adaptiveColor(
            light: (0.18, 0.42, 0.31),
            dark: (0.44, 0.76, 0.58)
        )

        /// A warm sand, used sparingly for streaks and celebration.
        public static let secondaryAccent = adaptiveColor(
            light: (0.76, 0.55, 0.24),
            dark: (0.91, 0.73, 0.40)
        )

        /// The recorded route. Chosen to stay legible over both the light and
        /// dark Apple Maps styles, where the accent green disappears into parks.
        public static let route = adaptiveColor(
            light: (0.09, 0.47, 0.86),
            dark: (0.35, 0.71, 1.00)
        )

        public static let success = adaptiveColor(
            light: (0.13, 0.52, 0.29),
            dark: (0.38, 0.78, 0.51)
        )

        public static let warning = adaptiveColor(
            light: (0.70, 0.48, 0.09),
            dark: (0.95, 0.75, 0.30)
        )

        public static let destructive = Color.red

        #if canImport(UIKit)
        public static let background = Color(uiColor: .systemBackground)
        public static let groupedBackground = Color(uiColor: .systemGroupedBackground)
        public static let surface = Color(uiColor: .secondarySystemGroupedBackground)
        public static let separator = Color(uiColor: .separator)
        public static let fill = Color(uiColor: .tertiarySystemFill)
        #else
        public static let background = Color(nsColor: .windowBackgroundColor)
        public static let groupedBackground = Color(nsColor: .underPageBackgroundColor)
        public static let surface = Color(nsColor: .controlBackgroundColor)
        public static let separator = Color(nsColor: .separatorColor)
        public static let fill = Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
        #endif

        public static let primaryText = Color.primary
        public static let secondaryText = Color.secondary
    }

    /// A 4-point spacing scale. Named rather than numeric so layouts stay
    /// consistent and a "slightly bigger gap" is a deliberate step.
    public enum Space {
        public static let xxs: CGFloat = 2
        public static let xs: CGFloat = 4
        public static let s: CGFloat = 8
        public static let m: CGFloat = 12
        public static let l: CGFloat = 16
        public static let xl: CGFloat = 24
        public static let xxl: CGFloat = 32
        public static let xxxl: CGFloat = 48
    }

    public enum Radius {
        public static let small: CGFloat = 8
        public static let medium: CGFloat = 14
        public static let large: CGFloat = 20
        public static let card: CGFloat = 18
    }

    /// Minimum interactive size. 44 pt is Apple's guidance and the practical
    /// floor for tapping anything while holding a lead in the other hand.
    public static let minimumTapTarget: CGFloat = 44

    /// Type roles. Everything resolves to a Dynamic Type text style so the app
    /// scales with the owner's chosen text size; only the tabular-figures
    /// treatment on live metrics is hand-specified, because digits that change
    /// width make a running timer jitter.
    public enum Typeface {
        public static func metricValue(_ size: Font.TextStyle = .largeTitle) -> Font {
            .system(size, design: .rounded, weight: .semibold).monospacedDigit()
        }

        public static let metricLabel = Font.subheadline.weight(.medium)
        public static let sectionTitle = Font.title3.weight(.semibold)
        public static let cardTitle = Font.headline
        public static let body = Font.body
        public static let caption = Font.caption
        public static let screenTitle = Font.largeTitle.weight(.bold)
    }
}

// MARK: - Motion

public extension Animation {
    /// The app's standard transition. Short enough not to delay a tap, soft
    /// enough not to feel mechanical.
    static let companionStandard = Animation.smooth(duration: 0.32)
    /// For values counting up, such as goal rings on appearance.
    static let companionMetric = Animation.smooth(duration: 0.6)
}

public extension View {
    /// Applies an animation unless the owner has asked for reduced motion.
    func respectingReduceMotion(_ animation: Animation, value: some Equatable) -> some View {
        modifier(ReduceMotionAnimation(animation: animation, value: value))
    }
}

private struct ReduceMotionAnimation<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: V

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}
