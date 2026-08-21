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

    /// The app is dark-theme-only: every semantic colour below resolves to the
    /// same value regardless of the system appearance. `adaptiveColor` is kept
    /// as the construction path (rather than a flat `Color(...)`) purely so a
    /// future return to light/dark parity is a values change, not a rewrite.
    public enum Colour {
        /// A warm, bright cream/khaki — the app's primary brand colour.
        /// Quiet and editorial rather than a loud app-store green, it echoes
        /// the sand and warm neutrals in the app's photography instead of
        /// competing with the greens of the walking routes themselves. Every
        /// primary CTA across the app reads from this one value.
        public static let accent = adaptiveColor(
            light: (0.93, 0.91, 0.83),
            dark: (0.93, 0.91, 0.83)
        )

        /// A vivid gold — the app's second brand colour: the tab bar,
        /// streaks, celebrations, achievement gold and every "share the
        /// story" moment all read from this one value.
        public static let secondaryAccent = adaptiveColor(
            light: (0.98, 0.72, 0.28),
            dark: (0.98, 0.72, 0.28)
        )

        /// The recorded route. Stays legible over the dark Apple Maps style.
        public static let route = adaptiveColor(
            light: (0.35, 0.71, 1.00),
            dark: (0.35, 0.71, 1.00)
        )

        public static let success = adaptiveColor(
            light: (0.38, 0.80, 0.52),
            dark: (0.38, 0.80, 0.52)
        )

        public static let warning = adaptiveColor(
            light: (0.95, 0.75, 0.30),
            dark: (0.95, 0.75, 0.30)
        )

        public static let destructive = adaptiveColor(
            light: (1.00, 0.36, 0.36),
            dark: (1.00, 0.36, 0.36)
        )

        /// Achievement tier colours, boosted for contrast against a near-black
        /// badge field — a badge is a small celebration, and small
        /// celebrations are exactly where a premium app can afford a flash of
        /// colour without stopping feeling premium.
        public enum Tier {
            public static let bronze = adaptiveColor(
                light: (0.82, 0.55, 0.33),
                dark: (0.82, 0.55, 0.33)
            )
            public static let silver = adaptiveColor(
                light: (0.78, 0.81, 0.85),
                dark: (0.78, 0.81, 0.85)
            )
            /// Shares the brand's gold rather than a generic yellow, so gold
            /// reads as "this app's gold" rather than a stock icon colour.
            public static let gold = Theme.Colour.secondaryAccent
            public static let platinum = adaptiveColor(
                light: (0.58, 0.83, 0.97),
                dark: (0.58, 0.83, 0.97)
            )
        }

        /// One colour per Explore category, so a screen with no real place
        /// photography still reads as visually varied — parks, beaches and
        /// cafés should feel like different kinds of places at a glance, not
        /// the same cream icon tile repeated with a different label.
        public enum Place {
            public static let park = adaptiveColor(light: (0.45, 0.78, 0.45), dark: (0.45, 0.78, 0.45))
            public static let beach = adaptiveColor(light: (0.40, 0.75, 0.95), dark: (0.40, 0.75, 0.95))
            public static let woodland = adaptiveColor(light: (0.42, 0.70, 0.45), dark: (0.42, 0.70, 0.45))
            public static let securedField = adaptiveColor(light: (0.60, 0.65, 0.72), dark: (0.60, 0.65, 0.72))
            public static let cafe = adaptiveColor(light: (0.80, 0.60, 0.40), dark: (0.80, 0.60, 0.40))
            public static let pub = adaptiveColor(light: (0.90, 0.55, 0.35), dark: (0.90, 0.55, 0.35))
            public static let waterPoint = adaptiveColor(light: (0.35, 0.70, 0.85), dark: (0.35, 0.70, 0.85))
        }

        /// A near-black canvas in dark appearance — deliberately darker than
        /// the system default so cards, imagery and badges have somewhere to
        /// lift off from. In light appearance, a soft off-white plays the
        /// same role: never pure white, so surfaces still read as a distinct
        /// step up rather than disappearing into the page.
        public static let background = adaptiveColor(
            light: (0.965, 0.965, 0.975),
            dark: (0.043, 0.043, 0.047)
        )
        public static let groupedBackground = adaptiveColor(
            light: (0.965, 0.965, 0.975),
            dark: (0.043, 0.043, 0.047)
        )

        /// The card surface — one deliberate step up from the background so
        /// every card reads as a distinct, slightly raised plane.
        public static let surface = adaptiveColor(
            light: (1.0, 1.0, 1.0),
            dark: (0.11, 0.11, 0.125)
        )

        /// A second, brighter elevation for content that should sit above
        /// even a card — hero panels, sheets over sheets.
        public static let surfaceElevated = adaptiveColor(
            light: (1.0, 1.0, 1.0),
            dark: (0.16, 0.16, 0.18)
        )

        public static let separator = adaptiveColor(
            light: (0.85, 0.85, 0.87),
            dark: (0.27, 0.27, 0.29)
        )
        public static let fill = adaptiveColor(
            light: (0.91, 0.91, 0.93),
            dark: (0.20, 0.20, 0.22)
        )

        public static let primaryText = adaptiveColor(
            light: (0.07, 0.07, 0.09),
            dark: (0.97, 0.97, 0.98)
        )
        public static let secondaryText = adaptiveColor(
            light: (0.44, 0.44, 0.47),
            dark: (0.62, 0.62, 0.66)
        )
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

        /// The oversized display style for hero moments — the onboarding
        /// tagline, a walk's headline distance. Rounded design keeps it
        /// friendly rather than corporate at this size; medium weight rather
        /// than bold or heavy keeps it feeling light and airy at large sizes
        /// instead of shouting.
        public static func heroTitle(_ size: Font.TextStyle = .largeTitle) -> Font {
            .system(size, design: .rounded, weight: .medium)
        }

        /// A small, wide-tracked eyebrow label — set in the accent colour
        /// above a hero title. The tracking carries the emphasis, so the
        /// weight itself stays modest rather than doubling up on boldness.
        public static let eyebrow = Font.subheadline.weight(.semibold)
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
