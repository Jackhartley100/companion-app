import SwiftUI
import CompanionCore
import CompanionUI

/// The iOS application target.
///
/// Deliberately tiny. Everything the app does lives in `CompanionCore` and
/// `CompanionUI`, which are multi-platform Swift packages and can therefore be
/// built and unit-tested from the command line. This file is the only part of
/// the codebase that needs Xcode to compile.
@main
struct CompanionApp: App {
    @State private var environment: AppEnvironment?
    @State private var startupError: String?

    var body: some Scene {
        WindowGroup {
            if let environment {
                RootView(environment: environment)
            } else if let startupError {
                // A failure to open local storage is rare but not impossible —
                // a full disk, or a container the app cannot write to. Showing
                // the reason beats a blank screen or a crash on launch.
                ErrorStateView(
                    title: "Companion could not start",
                    message: startupError,
                    reassurance: "Any walks you have recorded are still on this iPhone.",
                    retry: { makeEnvironment() }
                )
            } else {
                LaunchPlaceholder()
                    .task { makeEnvironment() }
            }
        }
    }

    private func makeEnvironment() {
        do {
            startupError = nil
            let environment = try AppEnvironment.live()
            // UI tests need a clean install every run, and reinstalling the app
            // between each one is far slower than clearing the store.
            if ProcessInfo.processInfo.arguments.contains("-companion.resetStateOnLaunch") {
                Task {
                    try? await environment.profileRepository.deleteEverything()
                    self.environment = environment
                }
            } else {
                self.environment = environment
            }
        } catch {
            startupError = error.localizedDescription
        }
    }
}

/// Shown for the moment it takes to open local storage.
private struct LaunchPlaceholder: View {
    var body: some View {
        ProgressView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .systemBackground))
    }
}
