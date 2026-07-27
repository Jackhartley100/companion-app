import SwiftUI
import MapKit
import CompanionCore

/// The screen shown while a walk is being recorded.
///
/// Designed to be read at arm's length, outdoors, one-handed, possibly in rain,
/// while holding a lead. That drives every decision here: big type, high
/// contrast, few controls, large targets, and a finish action that cannot be
/// triggered by a pocket.
struct ActiveWalkScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.formatters) private var formatters

    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var isFollowing = true
    @State private var showsDiscardConfirmation = false

    private var recorder: WalkRecorder { model.recorder }

    var body: some View {
        ZStack(alignment: .bottom) {
            map
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 0)
                controlPanel
            }
        }
        .background(Theme.Colour.background)
        .onAppear { Platform.setIdleTimerDisabled(true) }
        .onDisappear { Platform.setIdleTimerDisabled(false) }
        .confirmationDialog(
            "Discard this walk?",
            isPresented: $showsDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("Discard Walk", role: .destructive) {
                Task {
                    Haptics.play(.destructiveConfirmed)
                    await recorder.finish(discard: true)
                }
            }
            Button("Keep Recording", role: .cancel) {}
        } message: {
            Text("The route recorded so far will not be saved. This cannot be undone.")
        }
    }

    // MARK: Map

    private var map: some View {
        RouteMapView(
            segments: routeSegments(from: recorder.routePoints.map(\.coordinate)),
            mode: isFollowing ? .following : .free,
            showsUserLocation: true,
            cameraPosition: $camera
        )
        .overlay(alignment: .topTrailing) {
            if !isFollowing {
                CircularIconButton(
                    symbolName: "location.fill",
                    accessibilityLabel: "Recentre the map on your location",
                    tint: Theme.Colour.accent
                ) {
                    isFollowing = true
                    camera = .userLocation(fallback: .automatic)
                }
                .padding(Theme.Space.l)
                .padding(.top, 90)
            }
        }
        .onMapCameraChange(frequency: .onEnd) { _ in
            // Any deliberate pan hands control to the owner. Snapping back to
            // follow while someone is looking at where they are going is
            // infuriating.
            isFollowing = false
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        VStack(spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.m) {
                if !dogsOnWalk.isEmpty {
                    DogAvatarRow(
                        dogs: dogsOnWalk,
                        size: 30,
                        imageStore: model.environment.imageStore
                    )
                }
                Text(dogsOnWalk.map(\.name).formatted(.list(type: .and)))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                Spacer(minLength: 0)

                statusPill
            }
            .padding(.horizontal, Theme.Space.l)
            .padding(.vertical, Theme.Space.m)
            .background(.regularMaterial)
            .clipShape(Capsule())
            .padding(.horizontal, Theme.Space.l)

            if recorder.isSignalInterrupted {
                interruptionBanner
            }
        }
        .padding(.top, Theme.Space.s)
    }

    private var statusPill: some View {
        HStack(spacing: Theme.Space.xs) {
            Circle()
                .fill(statusColour)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(.caption.weight(.medium))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Status")
        .accessibilityValue(statusText)
    }

    private var statusColour: Color {
        if recorder.state.isPaused { return Theme.Colour.warning }
        switch recorder.metrics.accuracy {
        case .good, .fair: return Theme.Colour.success
        case .poor: return Theme.Colour.warning
        case .unusable: return Theme.Colour.destructive
        }
    }

    private var statusText: String {
        if recorder.state.isPaused { return "Paused" }
        return recorder.metrics.accuracy.displayName
    }

    private var interruptionBanner: some View {
        Label(
            "GPS signal is weak. Recording continues and will pick up when it returns.",
            systemImage: "antenna.radiowaves.left.and.right.slash"
        )
        .font(.footnote)
        .padding(Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
        .padding(.horizontal, Theme.Space.l)
        .accessibilityElement(children: .combine)
    }

    // MARK: Controls

    private var controlPanel: some View {
        VStack(spacing: Theme.Space.l) {
            metrics

            if case .failed(let failure) = recorder.state {
                failureView(failure)
            } else {
                controls
            }
        }
        .padding(Theme.Space.l)
        .background(.regularMaterial)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: Theme.Radius.large,
                topTrailingRadius: Theme.Radius.large,
                style: .continuous
            )
        )
        .ignoresSafeArea(edges: .bottom)
    }

    private var metrics: some View {
        VStack(spacing: Theme.Space.l) {
            VStack(spacing: Theme.Space.xxs) {
                Text(formatters.duration(recorder.metrics.movingDuration))
                    .font(.system(size: 56, weight: .semibold, design: .rounded).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text("Moving time")
                    .font(.caption)
                    .foregroundStyle(Theme.Colour.secondaryText)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Moving time")
            .accessibilityValue(formatters.spelledDuration(recorder.metrics.movingDuration))

            HStack {
                MetricCard(
                    value: formatters.distanceValue(recorder.metrics.distance),
                    unit: formatters.distanceUnitLabel,
                    label: "Distance",
                    accessibleValue: formatters.accessibleDistance(recorder.metrics.distance)
                )
                MetricCard(
                    value: rateText(recorder.metrics.currentSpeed) ?? "—",
                    label: "Current",
                    accessibleValue: rateText(recorder.metrics.currentSpeed) ?? "Not enough data yet"
                )
                MetricCard(
                    value: rateText(recorder.metrics.averageSpeed) ?? "—",
                    label: "Average",
                    accessibleValue: rateText(recorder.metrics.averageSpeed) ?? "Not enough data yet"
                )
            }
        }
    }

    private func rateText(_ metresPerSecond: Double?) -> String? {
        formatters.rate(
            metresPerSecond: metresPerSecond,
            activityType: recorder.currentActivityType ?? .walk
        )
    }

    private var controls: some View {
        VStack(spacing: Theme.Space.m) {
            HStack(spacing: Theme.Space.m) {
                if recorder.state.isPaused {
                    PrimaryButton("Resume", symbolName: "play.fill") {
                        Task {
                            await recorder.resume()
                            Haptics.play(.walkResumed)
                        }
                    }
                } else {
                    SecondaryButton("Pause", symbolName: "pause.fill") {
                        Task {
                            await recorder.pause()
                            Haptics.play(.walkPaused)
                        }
                    }
                }
            }

            HoldToConfirmButton("Finish Walk", armedTitle: "Tap again to finish") {
                Task {
                    await recorder.finish()
                    await model.refreshActivities()
                }
            }

            if recorder.state.isPaused {
                Button("Discard walk", role: .destructive) {
                    showsDiscardConfirmation = true
                }
                .font(.subheadline)
                .frame(minHeight: Theme.minimumTapTarget)
            }
        }
    }

    private func failureView(_ failure: RecordingFailure) -> some View {
        VStack(spacing: Theme.Space.m) {
            Text(failure.title).font(.headline)
            Text(failure.message)
                .font(.footnote)
                .foregroundStyle(Theme.Colour.secondaryText)
                .multilineTextAlignment(.center)
            if failure.dataIsSafe {
                Text("Your route is safe.")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.Colour.success)
            }

            if case .saveFailed = failure {
                PrimaryButton("Try Saving Again") {
                    Task {
                        await recorder.retrySave()
                        await model.refreshActivities()
                    }
                }
            }
            if failure.requiresSystemSettings {
                SecondaryButton("Open Settings") { Platform.openAppSettings() }
            }
            Button("Close", role: .cancel) { recorder.reset() }
                .frame(minHeight: Theme.minimumTapTarget)
        }
    }

    // MARK: Helpers

    /// The dogs actually on this walk, from the recorder's own session — not
    /// from whichever dog Today happens to have selected.
    private var dogsOnWalk: [Dog] {
        recorder.currentDogIDs.compactMap { id in model.dogs.first { $0.id == id } }
    }
}

struct ActiveWalkScreen_Previews: PreviewProvider {
    /// Drives a recorder into a given state so the screen can be previewed in
    /// each one without a real walk.
    struct Host: View {
        var paused = false
        var interrupted = false
        @State private var model = AppModel(environment: .preview())

        var body: some View {
            ActiveWalkScreen()
                .environment(model)
                .environment(\.formatters, model.formatters)
                .task {
                    await model.load()
                    await model.recorder.start(
                        dogIDs: [DemoDataProvider.roxyID],
                        ownerID: DemoDataProvider.ownerID
                    )
                    if paused { await model.recorder.pause() }
                    if interrupted,
                       let source = model.environment.trackingSource as? MockTrackingSource {
                        await source.inject(.accuracyChanged(.unusable))
                        await source.inject(.interrupted(.signalLost))
                    }
                }
        }
    }

    static var previews: some View {
        Host()
            .previewDisplayName("Recording")

        Host(paused: true)
            .previewDisplayName("Paused")

        Host(interrupted: true)
            .previewDisplayName("GPS signal lost")

        Host()
            .preferredColorScheme(.dark)
            .previewDisplayName("Dark")

        Host()
            .environment(\.sizeCategory, .accessibilityLarge)
            .previewDisplayName("Large text")
    }
}
