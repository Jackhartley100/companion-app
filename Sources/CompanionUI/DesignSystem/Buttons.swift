import SwiftUI

/// The single most important action on a screen. At most one per screen.
public struct PrimaryButton: View {
    private let title: String
    private let symbolName: String?
    private let trailingSymbolName: String?
    private let isLoading: Bool
    private let isEnabled: Bool
    private let role: ButtonRole?
    /// Renders as frosted liquid glass instead of a solid fill — for buttons
    /// sitting directly over photography, where a flat colour block would cut
    /// across the image rather than sitting on top of it.
    private let isGlass: Bool
    /// Overrides the role-derived colour — for the rare screen (a
    /// full-bleed photograph, say) where the single global accent isn't the
    /// right call for this one button.
    private let tintOverride: Color?
    private let action: () -> Void

    public init(
        _ title: String,
        symbolName: String? = nil,
        trailingSymbolName: String? = nil,
        isLoading: Bool = false,
        isEnabled: Bool = true,
        role: ButtonRole? = nil,
        isGlass: Bool = false,
        tint: Color? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.symbolName = symbolName
        self.trailingSymbolName = trailingSymbolName
        self.isLoading = isLoading
        self.isEnabled = isEnabled
        self.role = role
        self.isGlass = isGlass
        self.tintOverride = tint
        self.action = action
    }

    private var tint: Color {
        tintOverride ?? (role == .destructive ? Theme.Colour.destructive : Theme.Colour.accent)
    }

    public var body: some View {
        Button(role: role, action: action) {
            label
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isLoading)
        // Without this, VoiceOver reads a loading button as tappable.
        .accessibilityLabel(isLoading ? "\(title), in progress" : title)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var label: some View {
        let opacity = isEnabled && !isLoading ? 1.0 : 0.35
        let content = HStack(spacing: Theme.Space.s) {
            if isLoading {
                ProgressView().controlSize(.small).tint(isGlass ? .white : .black)
            } else if let symbolName {
                Image(systemName: symbolName)
            }
            Text(title).fontWeight(.medium)
            if !isLoading, let trailingSymbolName {
                Image(systemName: trailingSymbolName)
            }
        }
        .frame(maxWidth: .infinity, minHeight: Theme.minimumTapTarget)
        .padding(.vertical, Theme.Space.xs)
        .contentShape(Capsule())

        if isGlass {
            content
                .foregroundStyle(Theme.Colour.primaryText)
                .liquidGlassCard(cornerRadius: Theme.minimumTapTarget, tint: tint.opacity(opacity))
                .shadow(color: tint.opacity(opacity * 0.3), radius: 14, x: 0, y: 6)
        } else {
            content
                // Black-on-tint rather than white — against this palette's
                // saturated green and gold, a black label carries more
                // contrast and more punch than white does.
                .foregroundStyle(.black)
                .background(tint.opacity(opacity))
                .clipShape(Capsule())
        }
    }
}

/// A supporting action. Reads as secondary through weight, not through being
/// small or low-contrast.
public struct SecondaryButton: View {
    private let title: String
    private let symbolName: String?
    private let role: ButtonRole?
    private let action: () -> Void

    public init(
        _ title: String,
        symbolName: String? = nil,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.symbolName = symbolName
        self.role = role
        self.action = action
    }

    private var tint: Color {
        role == .destructive ? Theme.Colour.destructive : Theme.Colour.accent
    }

    public var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: Theme.Space.s) {
                if let symbolName { Image(systemName: symbolName) }
                Text(title).fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity, minHeight: Theme.minimumTapTarget)
            .foregroundStyle(tint)
            .background(Theme.Colour.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                    .strokeBorder(tint.opacity(0.4), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A circular icon button, used on the map where labels would cover the route.
public struct CircularIconButton: View {
    private let symbolName: String
    /// Always supplied: an icon-only control is unusable with VoiceOver without it.
    private let accessibilityLabel: String
    private let tint: Color
    private let size: CGFloat
    private let action: () -> Void

    public init(
        symbolName: String,
        accessibilityLabel: String,
        tint: Color = Theme.Colour.primaryText,
        size: CGFloat = 48,
        action: @escaping () -> Void
    ) {
        self.symbolName = symbolName
        self.accessibilityLabel = accessibilityLabel
        self.tint = tint
        self.size = size
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: symbolName)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .background(.regularMaterial, in: Circle())
                .overlay(Circle().stroke(Theme.Colour.separator.opacity(0.5), lineWidth: 0.5))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

/// A control that must not be triggered by accident.
///
/// Used for finishing a walk: a tap arms it, and a second tap within a few
/// seconds confirms. A plain button here means a pocket tap ends a two-hour
/// hike; a confirmation dialog means fumbling with a modal in the rain.
public struct HoldToConfirmButton: View {
    private let title: String
    private let armedTitle: String
    private let symbolName: String
    private let action: () -> Void

    @State private var isArmed = false
    @State private var disarmTask: Task<Void, Never>?

    public init(
        _ title: String,
        armedTitle: String,
        symbolName: String = "flag.checkered",
        action: @escaping () -> Void
    ) {
        self.title = title
        self.armedTitle = armedTitle
        self.symbolName = symbolName
        self.action = action
    }

    public var body: some View {
        Button {
            if isArmed {
                disarmTask?.cancel()
                isArmed = false
                Haptics.play(.walkCompleted)
                action()
            } else {
                isArmed = true
                Haptics.play(.selectionChanged)
                disarmTask?.cancel()
                disarmTask = Task {
                    try? await Task.sleep(for: .seconds(4))
                    guard !Task.isCancelled else { return }
                    isArmed = false
                }
            }
        } label: {
            HStack(spacing: Theme.Space.s) {
                Image(systemName: isArmed ? "checkmark.circle.fill" : symbolName)
                Text(isArmed ? armedTitle : title).fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity, minHeight: 54)
            .foregroundStyle(isArmed ? .white : .black)
            .background(isArmed ? Theme.Colour.destructive : Theme.Colour.accent)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .respectingReduceMotion(.companionStandard, value: isArmed)
        .accessibilityLabel(title)
        .accessibilityHint(isArmed ? "Tap again to confirm" : "Tap twice to finish this walk")
        .onDisappear { disarmTask?.cancel() }
    }
}

struct Buttons_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: Theme.Space.l) {
            PrimaryButton("Start Walk", symbolName: "figure.walk") {}
            PrimaryButton("Saving", isLoading: true) {}
            PrimaryButton("Unavailable", isEnabled: false) {}
            SecondaryButton("Add another dog", symbolName: "plus") {}
            SecondaryButton("Delete", symbolName: "trash", role: .destructive) {}
            HoldToConfirmButton("Finish Walk", armedTitle: "Tap again to finish") {}
            HStack(spacing: Theme.Space.m) {
                CircularIconButton(symbolName: "location.fill", accessibilityLabel: "Recentre map") {}
                CircularIconButton(symbolName: "pause.fill", accessibilityLabel: "Pause walk") {}
            }
        }
        .padding()
        .previewDisplayName("Light")

        VStack(spacing: Theme.Space.l) {
            PrimaryButton("Start Walk", symbolName: "figure.walk") {}
            HoldToConfirmButton("Finish Walk", armedTitle: "Tap again to finish") {}
        }
        .padding()
        .preferredColorScheme(.dark)
        .previewDisplayName("Dark")

        VStack(spacing: Theme.Space.l) {
            PrimaryButton("Start Walk", symbolName: "figure.walk") {}
            SecondaryButton("Add another dog", symbolName: "plus") {}
        }
        .padding()
        .environment(\.sizeCategory, .accessibilityExtraLarge)
        .previewDisplayName("Large text")
    }
}
