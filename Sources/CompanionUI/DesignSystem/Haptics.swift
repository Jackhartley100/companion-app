import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// The moments the app is allowed to vibrate.
///
/// Enumerated rather than exposing a generic "play a haptic" call, so the set of
/// moments stays small and reviewable. Haptics fire on state changes the owner
/// caused and cares about — never on scrolling, appearing or loading.
public enum HapticMoment {
    case walkStarted
    case walkPaused
    case walkResumed
    case walkCompleted
    case achievementUnlocked
    case destructiveConfirmed
    case selectionChanged
}

@MainActor
public enum Haptics {
    /// Set to false when the owner has Reduce Motion on; some people who find
    /// motion uncomfortable also find unexpected haptics uncomfortable.
    public static var isEnabled = true

    public static func play(_ moment: HapticMoment) {
        guard isEnabled else { return }
        #if os(iOS)
        switch moment {
        case .walkStarted, .walkResumed:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .walkPaused:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .walkCompleted, .achievementUnlocked:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .destructiveConfirmed:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .selectionChanged:
            UISelectionFeedbackGenerator().selectionChanged()
        }
        #endif
    }
}
