import SwiftUI

/// A titled group heading with an optional trailing action.
public struct SectionHeader: View {
    private let title: String
    private let actionTitle: String?
    private let action: (() -> Void)?

    public init(_ title: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(Theme.Typeface.sectionTitle)
                .foregroundStyle(Theme.Colour.primaryText)
            Spacer(minLength: Theme.Space.s)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.Colour.accent)
            }
        }
        .accessibilityAddTraits(.isHeader)
    }
}

/// The container every content card uses.
///
/// One level only: cards are never nested inside other cards, which is what
/// turns a dashboard into visual soup.
public struct Card<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .padding(Theme.Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Colour.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }
}

/// A large, scannable number with its label. The primary way metrics are shown.
public struct MetricCard: View {
    private let value: String
    private let unit: String?
    private let label: String
    private let symbolName: String?
    private let tint: Color
    /// Spoken instead of `value` + `unit`, which VoiceOver reads poorly
    /// ("3.4 km" becomes "three point four kay em").
    private let accessibleValue: String?

    public init(
        value: String,
        unit: String? = nil,
        label: String,
        symbolName: String? = nil,
        tint: Color = Theme.Colour.primaryText,
        accessibleValue: String? = nil
    ) {
        self.value = value
        self.unit = unit
        self.label = label
        self.symbolName = symbolName
        self.tint = tint
        self.accessibleValue = accessibleValue
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            if let symbolName {
                Image(systemName: symbolName)
                    .font(.subheadline)
                    .foregroundStyle(tint)
            }
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.xxs) {
                Text(value)
                    .font(Theme.Typeface.metricValue(.title))
                    .foregroundStyle(Theme.Colour.primaryText)
                if let unit {
                    Text(unit)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.Colour.secondaryText)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)

            Text(label)
                .font(Theme.Typeface.metricLabel)
                .foregroundStyle(Theme.Colour.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(accessibleValue ?? [value, unit].compactMap { $0 }.joined(separator: " "))
    }
}

/// A metric shown inline, for rows and detail screens.
public struct CompactMetric: View {
    private let value: String
    private let label: String
    private let symbolName: String?
    private let accessibleValue: String?

    public init(
        value: String,
        label: String,
        symbolName: String? = nil,
        accessibleValue: String? = nil
    ) {
        self.value = value
        self.label = label
        self.symbolName = symbolName
        self.accessibleValue = accessibleValue
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            HStack(spacing: Theme.Space.xs) {
                if let symbolName {
                    Image(systemName: symbolName)
                        .font(.caption)
                        .foregroundStyle(Theme.Colour.secondaryText)
                }
                Text(value)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(Theme.Colour.primaryText)
            }
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.Colour.secondaryText)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(accessibleValue ?? value)
    }
}

/// A circular progress indicator for goals.
public struct ProgressRing: View {
    private let fraction: Double
    private let lineWidth: CGFloat
    private let tint: Color
    private let label: String
    private let caption: String?

    @State private var animatedFraction: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        fraction: Double,
        lineWidth: CGFloat = 12,
        tint: Color = Theme.Colour.accent,
        label: String,
        caption: String? = nil
    ) {
        self.fraction = fraction
        self.lineWidth = lineWidth
        self.tint = tint
        self.label = label
        self.caption = caption
    }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, animatedFraction))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))

            VStack(spacing: 0) {
                Text(label)
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Theme.Colour.primaryText)
                if let caption {
                    Text(caption)
                        .font(.caption2)
                        .foregroundStyle(Theme.Colour.secondaryText)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(lineWidth * 1.6)
        }
        .onAppear {
            if reduceMotion {
                animatedFraction = fraction
            } else {
                withAnimation(.companionMetric) { animatedFraction = fraction }
            }
        }
        .onChange(of: fraction) { _, newValue in
            if reduceMotion {
                animatedFraction = newValue
            } else {
                withAnimation(.companionMetric) { animatedFraction = newValue }
            }
        }
        // The ring is decorative; the label and caption already carry the value.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int((fraction * 100).rounded())) percent. \(label). \(caption ?? "")")
    }
}

struct Cards_Previews: PreviewProvider {
    static var previews: some View {
        ScrollView {
            VStack(spacing: Theme.Space.l) {
                SectionHeader("This week", actionTitle: "See all") {}
                Card {
                    HStack {
                        MetricCard(
                            value: "3.42",
                            unit: "km",
                            label: "Distance",
                            symbolName: "figure.walk",
                            accessibleValue: "3.42 kilometres"
                        )
                        MetricCard(value: "48:12", label: "Time", symbolName: "clock")
                    }
                }
                Card {
                    HStack(spacing: Theme.Space.xl) {
                        ProgressRing(fraction: 0.62, label: "62%", caption: "of 30 km")
                            .frame(width: 110, height: 110)
                        VStack(alignment: .leading, spacing: Theme.Space.m) {
                            CompactMetric(value: "18.6 km", label: "So far", symbolName: "location")
                            CompactMetric(value: "3 days", label: "Left", symbolName: "calendar")
                        }
                    }
                }
            }
            .padding()
        }
        .background(Theme.Colour.groupedBackground)
        .previewDisplayName("Light")

        Card {
            HStack {
                MetricCard(value: "3.42", unit: "km", label: "Distance")
                MetricCard(value: "48:12", label: "Time")
            }
        }
        .padding()
        .background(Theme.Colour.groupedBackground)
        .preferredColorScheme(.dark)
        .previewDisplayName("Dark")

        Card {
            VStack {
                MetricCard(value: "3.42", unit: "km", label: "Distance")
                CompactMetric(value: "18.6 km", label: "So far")
            }
        }
        .padding()
        .environment(\.sizeCategory, .accessibilityExtraExtraLarge)
        .previewDisplayName("Large text")
    }
}
