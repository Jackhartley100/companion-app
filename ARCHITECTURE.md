# Architecture

## Shape

Three layers, with dependencies pointing one way only.

```
┌──────────────────────────────────────────────┐
│  Companion (iOS app target)                  │  ~50 lines. Needs Xcode.
│  CompanionApp.swift · Info.plist             │
└───────────────────┬──────────────────────────┘
                    │ imports
┌───────────────────▼──────────────────────────┐
│  CompanionUI                                 │  SwiftUI. Builds for iOS + macOS.
│  DesignSystem · App · Features                │
└───────────────────┬──────────────────────────┘
                    │ imports
┌───────────────────▼──────────────────────────┐
│  CompanionCore                               │  No SwiftUI. Pure domain.
│  Models · Tracking · Statistics ·             │
│  Achievements · Repositories · Services       │
└──────────────────────────────────────────────┘
```

`CompanionCore` imports Foundation, CoreLocation and `os` — nothing else. It has no
view code, so every calculation in the app can be tested without a UI, a device or
a simulator.

The app target is deliberately trivial. Everything of substance lives in a package
that compiles for macOS, which is what allows the whole codebase to be built and
tested from the command line without Xcode. See ADR-0002.

## Layer responsibilities

### CompanionCore

| Area | Responsibility |
|---|---|
| `Models/` | Value types. `Codable`, `Sendable`, no behaviour beyond derived properties. |
| `Tracking/` | The tracking-source protocol, GPS filtering, the walk session, the recording state machine. |
| `Statistics/` | Aggregation, streaks, goal evaluation, insight generation. All pure functions taking an explicit `Calendar`. |
| `Achievements/` | The catalogue (data) and the engine (rules). |
| `Repositories/` | Persistence protocols plus two implementations: file-backed and in-memory. |
| `Services/` | Auth, subscriptions, notifications, health, analytics, route privacy, places. All protocol-first. |
| `Formatting/` | Locale-aware presentation of stored base units. |
| `Demo/` | The single source of demonstration data. |

### CompanionUI

| Area | Responsibility |
|---|---|
| `DesignSystem/` | Tokens (colour, spacing, type, radius, motion) and reusable components. No feature logic. |
| `App/` | `AppEnvironment` (dependency container), `AppModel` (loaded state and actions), routing, tab shell. |
| `Features/` | One directory per feature. Views read `AppModel` and call its methods; they do no arithmetic and touch no repository directly. |

## Dependency injection

`AppEnvironment` is the composition root. It holds every repository and service as
an existential (`any ActivityRepository`, `any AuthenticationService`, …) and is
constructed exactly twice:

- `AppEnvironment.live()` — files on disk, the iPhone's GPS
- `AppEnvironment.preview()` — in-memory stores, a mock tracking source, stubbed
  permissions

No singletons. No global mutable state. Every preview and every test constructs its
own environment, which is why previews need no backend, no credentials, no network
and no GPS.

Protocol boundaries exist where an implementation is genuinely expected to be
replaced — persistence, auth, tracking sources, places, subscriptions, health,
notifications, analytics. One-line helpers are not hidden behind protocols.

## State management

`@Observable` (the Observation framework, iOS 17+) with `@MainActor` isolation.

There is **one** app-level model, `AppModel`, rather than one per screen. Dogs,
activities and goals are read by almost every screen; duplicating that loading per
view produces screens that disagree about what the owner just did. `AppModel` stays
a coordinator — it holds loaded data and calls into `CompanionCore` for every
calculation.

Load state is explicit:

```swift
enum LoadState { case loading, loaded, failed(String) }
```

Local view state (`@State`) is used for genuinely local things: which sheet is up,
what is typed in a field, whether a confirmation is armed.

### Concurrency

The whole package builds in **Swift 6 language mode with complete concurrency
checking**, with no `@unchecked Sendable` escape hatches outside a single test
helper.

- `AppModel`, `WalkRecorder` and `PhoneLocationTrackingSource` are `@MainActor`.
  Location callbacks arrive on the main thread anyway, and the per-callback work
  is a few arithmetic operations.
- `FileStore` is an `actor`, so concurrent saves cannot interleave.
- `MockTrackingSource` and `SamplePlaceRepository` are actors.
- Domain value types are `Sendable` by construction.

`ActivityTrackingSource.sessionUpdates()` is `async` rather than synchronous,
because every real implementation stores its stream continuation in isolated state
and a synchronous requirement cannot be witnessed by an isolated method.

## Persistence

JSON files under Application Support, behind repository protocols.

```
Application Support/Companion/
├── profile.json
├── dogs.json
├── goals.json
├── achievements.json
├── session.json              ← in-progress walk, for crash recovery
├── activities/
│   ├── index.json            ← metadata for every walk
│   └── routes/
│       └── <uuid>.json       ← one file per route
└── images/
```

Two design points matter here:

1. **Routes are stored separately from activity metadata.** A one-hour walk is
   ~3,600 route points. Listing 500 walks must not decode 1.8 million of them, so
   `activities/index.json` carries only what a list row needs — including a
   `routePreview` of at most 60 sampled coordinates for the thumbnail — and the
   full route is loaded only when a map is actually drawn.

2. **Writes are atomic.** `FileStore` writes to a temporary file and then moves it
   into place, so an interrupted write leaves the previous good file rather than a
   truncated one.

`SyncStatus` (`localOnly` / `pendingUpload` / `synced` / `conflict` / `failed`) is
modelled on every activity but everything is `.localOnly` today. There is no fake
sync that silently discards data.

## Location tracking

### The source protocol

```swift
protocol ActivityTrackingSource: Sendable {
    var capabilities: TrackingCapabilities { get }
    var recordingSource: RecordingSource { get }
    func startSession(configuration: TrackingConfiguration) async throws
    func pauseSession() async throws
    func resumeSession() async throws
    func stopSession() async throws -> TrackingSessionResult
    func sessionUpdates() async -> AsyncStream<TrackingUpdate>
}
```

Two implementations ship: `PhoneLocationTrackingSource` (real) and
`MockTrackingSource` (previews, tests, Simulator). Consumers ask
`capabilities` rather than checking which concrete type they have, so adding a
hardware source later does not mean editing every call site.

### GPS filtering

`RouteFilter` decides which fixes become route. Four checks, cheapest first:

| Check | Rejects | Why |
|---|---|---|
| Accuracy gate | Horizontal accuracy missing, negative, or > 50 m | The error exceeds the distance walked between fixes, so it can only add noise |
| Timestamp sanity | Older than the last accepted point, or > 30 s stale | CoreLocation delivers a cached fix on start-up |
| Plausible speed | Implied speed above a per-activity ceiling (8 m/s walking, 12 m/s running) | A 300 m jump in two seconds is multipath, not a sprint |
| Movement threshold | Closer than `max(3 m, accuracy × 0.5)` to the previous point | GPS jitter otherwise accumulates distance while standing still |

**The filter never smooths or interpolates.** Aggressive smoothing makes a route
look tidy while deleting genuine movement — a walk full of real doubling-back
would be flattened into a straight line and the reported distance would be wrong
in the owner's favour. It only ever discards fixes it cannot trust.

The jitter threshold scales with the fix's own accuracy: a ±30 m fix wanders
further while stationary than a ±5 m one.

### Recording state machine

```
idle ──prepare──▶ preparing ──▶ ready ──start──▶ recording ⇄ paused
                      │                              │        │
                      ▼                              └───┬────┘
                   failed ◀───────────────────────┐    finish
                                                  │      ▼
                                               (save) finishing ──▶ completed
```

One enum, not several booleans. `RecordingFailure` is reachable from anywhere and
every case answers three questions: what happened, whether the owner's data is
safe, and what to do next. Vague failures are not representable.

Pause semantics:

- Fixes arriving while paused are discarded, not stored — a coffee stop must not be
  drawn as a walked segment.
- On resume the filter's reference point is cleared **and** `WalkSession` marks a
  segment break, so the straight line across the pause adds no distance. (Clearing
  only the filter was a real bug; the session still measured from the pre-pause
  point.)
- Paused time is excluded from moving time and included in elapsed time.
- The map draws segments separately, so a pause reads as a break in the line.

### Crash recovery

The session is snapshotted to `session.json` every 30 seconds and on pause. Often
enough that a crash costs at most half a minute of route; rare enough that a
two-hour hike does not spend its battery on disk writes.

At launch, a snapshot with more than one point is offered back to the owner, who
decides whether to save or discard it. It is neither silently resurrected nor
silently deleted.

### Background recording

`UIBackgroundModes: [location]` plus `allowsBackgroundLocationUpdates = true`,
enabled when a session starts and disabled when it stops. The app requests **"when
in use" only** — iOS permits background updates under that authorisation while a
session is running, which is exactly the promise the permission screen makes.

## Achievements

Rules are data (`AchievementRule`), evaluated in one place (`AchievementEngine`),
against one context (`AchievementContext`). No view unlocks an achievement as a
side effect of being displayed. Adding an achievement means adding a definition to
`AchievementCatalog` and nothing else.

Identifiers are permanent — they are written into unlock records on the owner's
device, so renaming one would orphan every unlock.

## Future backend integration

Nothing needs restructuring to add one:

1. Write `RemoteActivityRepository` conforming to the existing `ActivityRepository`.
2. Compose it with the file store as a read-through cache, so offline keeps working.
3. Drive uploads from `SyncStatus`, which is already on every record.
4. Replace `LocalAuthenticationService` with the chosen identity provider.
5. Register both in `AppEnvironment.live()`.

The UI layer changes not at all — it depends on the protocols.

## Future tracker integration

1. Implement `CompanionTrackerSource: ActivityTrackingSource` with
   `capabilities` including `.dogLocation`.
2. Populate `TrackerDevice` and surface pairing in Settings, where the row already
   exists marked unavailable.
3. `RecordingSource.companionTracker` already exists and
   `measuresDogDirectly` already returns `true` for it — which is the switch that
   lets the UI stop hedging and legitimately say "your dog walked 4.2 km".

No speculative Bluetooth code has been written.
