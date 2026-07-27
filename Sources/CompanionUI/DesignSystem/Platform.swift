import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Thin platform shims.
///
/// The app targets iPhone. The package also builds for macOS purely so the whole
/// codebase — including every view — can be compiled and tested from the command
/// line without a full Xcode installation. These shims keep the `#if` noise in
/// one file instead of scattering it through feature code.
/// `UIApplication` is main-actor-isolated, so both of these are too. The macOS
/// build cannot catch that — `UIApplication` does not exist there, leaving the
/// bodies empty — so it only surfaced on the first real iOS compile. Every caller
/// is already a SwiftUI view body or action, which is main-actor anyway.
@MainActor
enum Platform {
    /// Opens the app's own page in the system Settings app.
    static func openAppSettings() {
        #if os(iOS)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
        #endif
    }

    /// Prevents the screen sleeping while a walk is being recorded and the
    /// active-walk screen is visible.
    static func setIdleTimerDisabled(_ disabled: Bool) {
        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = disabled
        #endif
    }
}

/// Builds a colour that resolves differently in light and dark appearance.
///
/// SwiftUI has no cross-platform literal for this, and an asset catalogue would
/// mean the package could not be compiled without Xcode's asset compiler.
func adaptiveColor(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
    #if canImport(UIKit)
    return Color(
        UIColor { traits in
            let components = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: components.0, green: components.1, blue: components.2, alpha: 1
            )
        }
    )
    #elseif canImport(AppKit)
    return Color(
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let components = isDark ? dark : light
            return NSColor(
                srgbRed: components.0, green: components.1, blue: components.2, alpha: 1
            )
        }
    )
    #else
    return Color(red: light.0, green: light.1, blue: light.2)
    #endif
}

extension View {
    /// `navigationBarTitleDisplayMode` where it exists, and nothing where it
    /// does not, so feature code can state the intent unconditionally.
    @ViewBuilder
    func compactNavigationTitle() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    @ViewBuilder
    func largeNavigationTitle() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.large)
        #else
        self
        #endif
    }

    /// Sheet sizing on platforms that support detents.
    @ViewBuilder
    func sheetDetents(_ detents: Set<PresentationDetent>) -> some View {
        #if os(iOS)
        self.presentationDetents(detents)
        #else
        self
        #endif
    }

    /// The grouped list appearance the app uses. `.insetGrouped` is iOS-only.
    @ViewBuilder
    func groupedListStyle() -> some View {
        #if os(iOS)
        self.listStyle(.insetGrouped)
        #else
        self.listStyle(.inset)
        #endif
    }

    /// Lets a downward swipe dismiss the keyboard. iOS-only.
    @ViewBuilder
    func scrollDismissesKeyboardInteractively() -> some View {
        #if os(iOS)
        self.scrollDismissesKeyboard(.interactively)
        #else
        self
        #endif
    }

    /// Adds a "Done" button above the keyboard while a field is focused.
    ///
    /// Without it, a form whose primary action sits below the keyboard has no
    /// obvious way out for someone who does not think to swipe.
    @ViewBuilder
    func keyboardDoneButton(isFocused: Bool, dismiss: @escaping () -> Void) -> some View {
        #if os(iOS)
        self.toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done", action: dismiss)
                    .fontWeight(.semibold)
            }
        }
        #else
        self
        #endif
    }
}
