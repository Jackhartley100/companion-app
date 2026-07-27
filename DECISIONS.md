# Decisions

Lightweight ADRs. Newest last.

---

## ADR-0001 — Deployment target iOS 17.0

**Context.** The app needs `@Observable`, MapKit's SwiftUI `Map` with
`MapContentBuilder`, `MapPolyline`, and Swift Charts. A target too new costs
reach; too old costs the APIs the design depends on.

**Decision.** iOS 17.0.

**Alternatives.**
- *iOS 18/26.* Would allow newer SwiftUI conveniences, none of which this app
  needs, at the cost of excluding devices.
- *iOS 16.* Rules out `@Observable`, forcing `ObservableObject`, and rules out the
  iOS 17 MapKit SwiftUI API — which would mean falling back to `UIViewRepresentable`
  around `MKMapView` for the most important screen in the app.

**Consequences.** Every API used is available at the stated minimum. No beta OS is
required. `@Observable` and modern MapKit are available throughout. Revisit when
iOS 17's share of devices no longer justifies it.

---

## ADR-0002 — The app is a Swift package with a thin iOS target

**Context.** Xcode is not installed on the development machine — only the Command
Line Tools. There is no `xcodebuild`, no iOS SDK and no simulator. A conventional
monolithic Xcode target would mean writing thousands of lines that could not be
compiled, let alone tested.

**Decision.** Put everything in a multi-platform Swift package
(`.iOS(.v17), .macOS(.v14)`) with two library targets, and reduce the iOS app
target to an entry point and an Info.plist. Generate the `.xcodeproj` with
XcodeGen rather than committing it.

**Alternatives.**
- *Monolithic Xcode target.* Nothing verifiable without Xcode. Rejected.
- *Domain-only package, UI in the app target.* Would leave every view, the map and
  the charts unverified — the majority of the code. Rejected.
- *Hand-written `project.pbxproj`.* Possible but unverifiable, and a format the
  author cannot check. XcodeGen produces it from a readable spec instead.

**Consequences.** The domain layer, the design system, every screen, MapKit and
Swift Charts all compile and are type-checked today, and 148 tests run in under a
second. The cost: SwiftData and the `#Preview` macro are unavailable (ADR-0003,
ADR-0004), and the app target itself remains unverified until Xcode is installed.
This is stated prominently in the README rather than glossed over.

It is also a good structure independently of the constraint: it enforces the layer
boundary, keeps build times low, and makes the domain reusable by a future Watch
app or extension.

---

## ADR-0003 — JSON file persistence rather than SwiftData

**Context.** The brief suggests SwiftData "where appropriate". SwiftData's `@Model`
is a macro whose plugin ships with Xcode; it cannot be expanded by the Command Line
Tools toolchain. Choosing SwiftData would mean the entire persistence layer — the
part where data loss actually happens — could not be compiled or tested at all.

**Decision.** Implement persistence as atomic JSON files behind repository
protocols, with activity metadata and route points in separate files.

**Alternatives.**
- *SwiftData.* Better querying and migration story, and the intended long-term
  home. Unverifiable here, so it would have shipped as untested code underneath
  everything else.
- *Core Data.* No macro problem, but substantially more ceremony and no
  compensating benefit at this data scale.
- *SQLite directly.* Overkill for hundreds of records per user.

**Consequences.** Persistence is fully tested, including persistence across
repository instances, cascading deletes and query parity between the file-backed
and in-memory stores. Route storage is deliberately efficient: listing 500 walks
decodes metadata only, never the ~1.8 million route points behind them.

The costs are real: no query language, no migration framework, and the whole
activity index is rewritten on each save. At the scale of one owner's walk history
that is a few hundred kilobytes and is not a concern; if it becomes one, the swap
path is contained. Everything depends on `ActivityRepository`, `DogRepository` and
friends, so introducing `SwiftDataActivityRepository` alongside the file store is a
new file plus one line in `AppEnvironment.live()`.

---

## ADR-0004 — `PreviewProvider` rather than the `#Preview` macro

**Context.** `#Preview` is a macro from the same Xcode-only plugin family as
`@Model`. Under the Command Line Tools it fails to expand, so any preview written
with it is a compile error here — meaning previews could be written but never
checked.

**Decision.** Use `PreviewProvider`.

**Consequences.** Every preview in the codebase is compile-verified, and they
render identically in Xcode's canvas. `PreviewProvider` is more verbose and is the
older idiom. Migrating to `#Preview` is a mechanical change once Xcode is the build
environment, and is not urgent.

---

## ADR-0005 — Swift 6 language mode everywhere

**Context.** The recording pipeline spans a location manager, an async stream, a
main-actor observable model and an actor-backed file store — exactly the shape
where data races hide.

**Decision.** Full Swift 6 language mode with complete concurrency checking on all
four targets.

**Consequences.** Two design changes fell directly out of it:
`ActivityTrackingSource.sessionUpdates()` became `async` (a synchronous requirement
cannot be witnessed by an isolated method), and `WalkRecorder` lost its `deinit`
cancellation (a `deinit` cannot touch main-actor state) in favour of tasks that
hold `self` weakly and exit on their next iteration. There is no
`@unchecked Sendable` in the codebase outside one test helper. The build is clean
with `-warnings-as-errors`.

---

## ADR-0006 — The route filter discards, but never smooths

**Context.** GPS traces are noisy. The usual response is to smooth them, which
produces a tidier line and a nicer-looking map.

**Decision.** Reject fixes that cannot be trusted — poor accuracy, stale
timestamps, impossible speeds, sub-jitter movement — and never interpolate,
average, or otherwise modify the fixes that pass.

**Consequences.** Recorded distance is conservative and defensible. Smoothing would
delete real movement: a dog walk full of genuine doubling-back would be flattened
into a straight line, and the distance would be wrong in the owner's favour, which
is the worst direction for a number the product asks people to trust.

The jitter threshold scales with each fix's reported accuracy (`max(3 m,
accuracy × 0.5)`) rather than being fixed, because a ±30 m fix wanders much
further while stationary than a ±5 m one.

---

## ADR-0007 — Pause creates a route segment break, not just a filter reset

**Context.** The first implementation reset `RouteFilter` on resume so the pause
gap would not be rejected as an impossible jump. A test found that
`WalkSession.append` still measured the new point against the last pre-pause point,
so driving to another park during a pause added the whole drive to the walk.

**Decision.** `WalkSession` records a segment break on resume, so the first fix
after a pause contributes no distance. The map splits the polyline through
`routeSegments(from:)`, which detects the same breaks from the coordinates alone —
one implementation serving both the live route and saved routes loaded from disk.

**Consequences.** Distance is correct across pauses, and the map does not claim a
route that was never walked. Covered by "The gap crossed while paused is not
counted after resuming".

---

## ADR-0008 — Profile writes are serialised

**Context.** The profile is edited from several places that overlap in time: the
settings pickers, the dog selector's `didSet`, and onboarding completion. Each does
a read, a change and a write. A journey test caught the consequence — selecting a
dog and completing onboarding raced, the slower write landed last, and
`onboardingCompleted` was silently reverted, dropping the owner back to the welcome
screen on next launch.

**Decision.** `AppModel.saveProfile` assigns `self.profile` synchronously before
any suspension, and chains each repository write behind the previous one.

**Alternatives.**
- *Re-read the profile inside the task.* Fixes the stale-snapshot half but not the
  write ordering; the race survived this fix in testing.
- *An actor around the profile.* Heavier, and the ordering problem would remain.

**Consequences.** Overlapping edits compose rather than clobber, and the last write
to disk always contains every change. Covered by "Completing onboarding creates a
profile and a dog that persist".

---

## ADR-0009 — Native `TabView`, no custom tab bar

**Context.** The brief floats a centre Start Walk button attached to the tab bar,
which requires a custom tab bar.

**Decision.** Native `TabView`. Start Walk is a full-width primary button at the
top of Today.

**Alternatives.** A custom bar would mean reimplementing selection, accessibility
focus order, safe-area behaviour, Dynamic Type layout and the system's own tab-bar
semantics — a large amount of fragile code for one button.

**Consequences.** The action is visible on launch without a tap, which is at least
as fast as a tab-bar button, and it is reachable from Explore and place detail too.
Accessibility and system behaviour come for free.

---

## ADR-0010 — Local-device authentication that does not pretend

**Context.** No backend exists. The brief asks for an authentication abstraction
with sign-in options.

**Decision.** `LocalAuthenticationService` creates a real, persisted, device-local
account. `signInWithApple` and `signInWithEmail` throw `.notConfigured`, and the
onboarding screen shows them as "Coming soon" text rather than as buttons.

**Consequences.** Nobody is told their data is backed up to an account when it is
only on one device, and nobody discovers a dead button by tapping it. The Settings
screen states plainly that deleting the app removes the walks. Swapping in a real
provider is one file and one registration line.

---

## ADR-0011 — Explore ships labelled sample data

**Context.** Explore needs content to be built at all, and no places provider has
been selected. The candidates — MKLocalSearch, a licensed API, or community data
with moderation — differ in cost and in moderation obligations, so the choice
deserves a deliberate decision rather than whichever integrates fastest.

**Decision.** Ship six hand-written example places, all `source: .sample` and
`isVerified: false`, with an on-screen notice on the list, the map and every detail
page saying they are examples that have not been checked.

**Consequences.** The screen's structure, categories, saving, detail and directions
are all built and testable, and the swap to a real provider changes
`PlaceRepository` and nothing else. The notice is not decoration — someone could
otherwise drive to a beach on the strength of unverified data.

---

## ADR-0012 — Route privacy trims endpoints, and refuses when it cannot

**Context.** A walk almost always starts and ends at the owner's front door.
Sharing a raw polyline publishes a home address.

**Decision.** `RoutePrivacy.trimmingEndpoints` removes everything within a
configurable radius (200 m by default) of the first and last points. When the whole
walk falls inside that radius it returns nothing rather than something.

**Consequences.** A short walk around the block cannot be shared as a map at all,
which is the correct outcome — there is no version of that map that does not give
away where it started. The full route is always kept on device, so the owner's own
history stays accurate; trimming happens only on the way out. `MapCameraPosition.fitting`
also enforces a minimum span, so a very short walk does not zoom to street level.
