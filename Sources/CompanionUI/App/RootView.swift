import SwiftUI
import CompanionCore

/// Decides what the app shows at launch: onboarding, or the app itself.
///
/// Loading state is explicit and brief. There is no splash animation — a launch
/// screen that outlasts the work it covers is a delay dressed as a feature.
public struct RootView: View {
    @State private var model: AppModel
    @State private var didLoad = false

    public init(environment: AppEnvironment) {
        _model = State(initialValue: AppModel(environment: environment))
    }

    public var body: some View {
        Group {
            switch model.loadState {
            case .loading:
                LaunchView()
            case .failed(let message):
                ErrorStateView(
                    title: "Companion could not open your data",
                    message: message,
                    reassurance: "Your walks are still stored on this iPhone.",
                    retry: { Task { await model.load() } }
                )
            case .loaded:
                if model.hasCompletedOnboarding {
                    MainTabView()
                        .transition(.opacity)
                } else {
                    OnboardingFlow()
                        .transition(.opacity)
                }
            }
        }
        .environment(model)
        .environment(\.formatters, model.formatters)
        .environment(\.companionCalendar, model.calendar)
        .preferredColorScheme(colorScheme)
        .respectingReduceMotion(.companionStandard, value: model.hasCompletedOnboarding)
        .task {
            guard !didLoad else { return }
            didLoad = true
            await model.load()
        }
        .sheet(item: recoverableSessionBinding) { recoverable in
            RecoveredWalkSheet(session: recoverable.session)
                .environment(model)
                .environment(\.formatters, model.formatters)
        }
    }

    private var colorScheme: ColorScheme? {
        switch model.profile?.appearance ?? .system {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    /// Wraps the recovered session so it can drive a `sheet(item:)`.
    private var recoverableSessionBinding: Binding<RecoverableSession?> {
        Binding(
            get: { model.recorder.recoverableSession.map(RecoverableSession.init) },
            set: { newValue in
                guard newValue == nil else { return }
                Task { await model.recorder.discardRecoveredSession() }
            }
        )
    }
}

struct RecoverableSession: Identifiable {
    let session: WalkSession
    var id: UUID { session.id }

    init(_ session: WalkSession) { self.session = session }
}

struct LaunchView: View {
    var body: some View {
        VStack(spacing: Theme.Space.l) {
            Image(systemName: "pawprint.circle.fill")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(Theme.Colour.accent)
            Text(Theme.Brand.name)
                .font(.title2.weight(.semibold))
                .foregroundStyle(Theme.Colour.primaryText)
            ProgressView()
                .padding(.top, Theme.Space.s)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colour.background)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(Theme.Brand.name) is starting")
    }
}

/// Offers a walk that was interrupted by a crash or a force-quit.
///
/// The owner decides. Silently resurrecting the walk would put a half-finished
/// recording on screen with no explanation; silently deleting it would throw
/// away an hour of their afternoon.
struct RecoveredWalkSheet: View {
    let session: WalkSession

    @Environment(AppModel.self) private var model
    @Environment(\.formatters) private var formatters
    @Environment(\.dismiss) private var dismiss
    @State private var isSaving = false

    var body: some View {
        VStack(spacing: Theme.Space.xl) {
            VStack(spacing: Theme.Space.m) {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(Theme.Colour.accent)
                Text("An unfinished walk was found")
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text(
                    "Companion stopped before this walk was saved. "
                    + "The route recorded up to that point is still here."
                )
                .font(.subheadline)
                .foregroundStyle(Theme.Colour.secondaryText)
                .multilineTextAlignment(.center)
            }

            Card {
                HStack {
                    CompactMetric(
                        value: formatters.distance(session.distance),
                        label: "Distance",
                        symbolName: "figure.walk"
                    )
                    Spacer()
                    CompactMetric(
                        value: formatters.duration(session.movingDuration(asOf: Date())),
                        label: "Recorded",
                        symbolName: "clock"
                    )
                    Spacer()
                    CompactMetric(
                        value: formatters.shortDate(session.startDate),
                        label: "Started",
                        symbolName: "calendar"
                    )
                }
            }

            Spacer(minLength: 0)

            VStack(spacing: Theme.Space.s) {
                PrimaryButton("Save This Walk", isLoading: isSaving) {
                    Task {
                        isSaving = true
                        guard let ownerID = model.profile?.id else { return }
                        await model.recorder.saveRecoveredSession(ownerID: ownerID)
                        await model.refreshActivities()
                        model.recorder.reset()
                        isSaving = false
                        dismiss()
                    }
                }
                SecondaryButton("Discard", role: .destructive) {
                    Task {
                        await model.recorder.discardRecoveredSession()
                        dismiss()
                    }
                }
            }
        }
        .padding(Theme.Space.xl)
        .sheetDetents([.medium, .large])
        .interactiveDismissDisabled()
    }
}

struct RootView_Previews: PreviewProvider {
    static var previews: some View {
        RootView(environment: .preview())
            .previewDisplayName("Returning owner")

        RootView(environment: .preview(store: InMemoryStore()))
            .previewDisplayName("New owner")

        LaunchView().previewDisplayName("Launch")

        RecoveredWalkSheet(
            session: {
                var session = WalkSession(
                    startDate: DemoDataProvider.referenceDate.addingTimeInterval(-2_400),
                    dogIDs: [DemoDataProvider.roxyID]
                )
                for point in DemoDataProvider.sampleRoute() { session.append(point) }
                return session
            }()
        )
        .environment(AppModel(environment: .preview()))
        .previewDisplayName("Recovered walk")
    }
}
