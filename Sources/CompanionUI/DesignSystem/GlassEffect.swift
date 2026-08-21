import SwiftUI

/// Apple's frosted "liquid glass" material language, hand-built so it renders
/// identically on this app's iOS 17 minimum deployment target rather than
/// gating on the real system material (iOS 26's `glassEffect`), which would
/// need an `#available` fallback anyway. Three layers make the difference
/// between "grey" and "glass": a system material blur, a faint light source
/// in the top-leading corner, and a bright-to-dim rim on the border.
public struct LiquidGlassBackground<GlassShape: InsettableShape>: ViewModifier {
    let shape: GlassShape
    let tint: Color?

    public func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    if let tint {
                        shape.fill(tint.opacity(0.30))
                    }
                    shape.fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.30),
                                Color.white.opacity(0.05),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                }
            )
            .overlay(
                shape.strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.55), Color.white.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
            )
            .clipShape(shape)
    }
}

public extension View {
    /// A frosted glass card in a rounded-rectangle shape — buttons, badges,
    /// small floating controls.
    func liquidGlassCard(cornerRadius: CGFloat, tint: Color? = nil) -> some View {
        modifier(
            LiquidGlassBackground(
                shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
                tint: tint
            )
        )
    }

    /// The same treatment in an arbitrary shape — used where the corner
    /// radius isn't uniform, such as a bottom sheet's top-only rounding.
    func liquidGlass(in shape: some InsettableShape, tint: Color? = nil) -> some View {
        modifier(LiquidGlassBackground(shape: shape, tint: tint))
    }
}
