import SwiftUI
import CompanionCore

/// The app's four destinations.
///
/// A native `TabView`. A custom tab bar was considered for a centre Start Walk
/// button and rejected: it would have to reimplement selection, accessibility
/// focus order, safe-area behaviour and the system's own tab-bar semantics, all
/// to place one button that sits perfectly well at the top of Today, where it is
/// also visible on launch without a tap.
public struct MainTabView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: Destination = .today
    @State private var isPresentingWalkPreparation = false

    public init() {}

    enum Destination: Hashable {
        case today, activities, explore, profile
    }

    public var body: some View {
        @Bindable var model = model

        TabView(selection: $selection) {
            TodayScreen(startWalk: { isPresentingWalkPreparation = true })
                .tabItem { Label("Today", systemImage: "sun.horizon") }
                .tag(Destination.today)

            ActivitiesScreen()
                .tabItem { Label("Activities", systemImage: "list.bullet.rectangle") }
                .tag(Destination.activities)

            ExploreScreen(startWalk: { isPresentingWalkPreparation = true })
                .tabItem { Label("Explore", systemImage: "map") }
                .tag(Destination.explore)

            ProfileScreen()
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
                .tag(Destination.profile)
        }
        // One highlight colour throughout: the cream accent carries every
        // piece of interaction chrome — the selected tab, toolbar actions,
        // native controls — as well as primary CTAs and full-screen surfaces.
        // Gold is reserved for the two places it means something specific
        // rather than "this is tappable": achievement tier badges (an actual
        // gold medal, not a UI accent) and the matching ring metrics on Today
        // and Activities.
        .tint(Theme.Colour.accent)
        .overlay(alignment: .top) {
            if let banner = model.banner {
                BannerView(message: banner) { model.banner = nil }
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .respectingReduceMotion(.companionStandard, value: model.banner)
        .sheet(isPresented: $isPresentingWalkPreparation) {
            WalkPreparationSheet()
                .environment(model)
                .environment(\.formatters, model.formatters)
                .environment(\.companionCalendar, model.calendar)
        }
        // The active walk takes the whole screen: while recording, nothing else
        // in the app is more important, and a half-height sheet over a map is
        // unusable outdoors.
        .fullScreenCoverCompatible(isPresented: .constant(model.recorder.state.hasSession)) {
            ActiveWalkScreen()
                .environment(model)
                .environment(\.formatters, model.formatters)
                .environment(\.companionCalendar, model.calendar)
        }
        .sheet(item: completedActivityBinding) { completed in
            WalkSummaryScreen(activity: completed.activity)
                .environment(model)
                .environment(\.formatters, model.formatters)
                .environment(\.companionCalendar, model.calendar)
        }
    }

    private var completedActivityBinding: Binding<CompletedWalk?> {
        Binding(
            get: {
                guard case .completed(let activity) = model.recorder.state else { return nil }
                return CompletedWalk(activity: activity)
            },
            set: { newValue in
                guard newValue == nil else { return }
                model.recorder.reset()
            }
        )
    }
}

struct CompletedWalk: Identifiable {
    let activity: WalkActivity
    var id: UUID { activity.id }
}

extension View {
    /// `fullScreenCover` where it exists, a sheet where it does not.
    @ViewBuilder
    func fullScreenCoverCompatible<Content: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        #if os(iOS)
        self.fullScreenCover(isPresented: isPresented, content: content)
        #else
        self.sheet(isPresented: isPresented, content: content)
        #endif
    }
}

struct MainTabView_Previews: PreviewProvider {
    static var previews: some View {
        PreviewHost { MainTabView() }
            .previewDisplayName("Populated")

        PreviewHost(store: DemoDataProvider.store(populated: false)) { MainTabView() }
            .previewDisplayName("No walks yet")
    }
}

/// Wires a preview's view up with a fully loaded `AppModel`.
///
/// Previews must not need a backend, real GPS, credentials or the network; this
/// makes the in-memory path the default and one line long.
struct PreviewHost<Content: View>: View {
    let store: InMemoryStore
    let locationStatus: LocationAuthorizationStatus
    let content: Content

    @State private var model: AppModel

    init(
        store: InMemoryStore = DemoDataProvider.store(),
        locationStatus: LocationAuthorizationStatus = .whenInUse,
        @ViewBuilder content: () -> Content
    ) {
        self.store = store
        self.locationStatus = locationStatus
        self.content = content()
        _model = State(
            initialValue: AppModel(
                environment: .preview(store: store, locationStatus: locationStatus)
            )
        )
    }

    var body: some View {
        content
            .environment(model)
            .environment(\.formatters, model.formatters)
            .environment(\.companionCalendar, model.calendar)
            .task { await model.load() }
    }
}
