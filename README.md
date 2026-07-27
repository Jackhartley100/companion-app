# Companion

A premium activity tracker for dog owners. Record your walks, build a routine, and
keep a lifetime of adventures with your dog in one place.

*Companion* is a working name.

---

## ⚠️ Build status — read this first

| What | Status |
|---|---|
| `CompanionCore` (domain, tracking, statistics, persistence) | ✅ Compiles, 131 tests passing |
| `CompanionUI` (design system, every screen, previews) | ✅ Compiles (for macOS), 17 journey tests passing |
| `Companion` (the iOS app target) | ⚠️ **Never compiled** — needs Xcode |
| Running on a simulator or device | ⚠️ **Never run** — needs Xcode |

**Xcode is not installed on the development machine this was built on** — only the
Command Line Tools. That means no `xcodebuild`, no iOS SDK and no simulator.

The architecture is a direct response to that constraint, and it is a good one
regardless: everything except a 50-line app entry point lives in a multi-platform
Swift package that builds and tests for macOS from the command line. So the domain
logic, the SwiftUI views, the MapKit map, the Swift Charts charts and every preview
are all genuinely compiled and type-checked. What has *not* been verified is the
iOS app target, its Info.plist wiring, code signing, and anything that only happens
on a real device — background location, haptics, the photo picker.

Do not take "it compiles" as "it runs on an iPhone". See
[Known limitations](#known-limitations).

---

## Quick start

### Without Xcode (what works today)

```bash
make check
```

That builds every target with warnings treated as errors and runs the full test
suite. Individually:

```bash
swift build
```

```bash
swift test
```

### With Xcode (to actually run the app)

1. Install Xcode 16 or later from the App Store.
2. Point the toolchain at it:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

3. Install the project generator and generate the project:

```bash
brew install xcodegen && make xcodeproj
```

4. Open `Companion.xcodeproj`, choose an iPhone simulator, and run.

Expect to fix a small number of iOS-only compilation errors on that first build —
the app target has never been near a compiler. They will be confined to
`Sources/Companion/` and to the `#if os(iOS)` branches in
`Sources/CompanionUI/DesignSystem/Platform.swift`.

### Recording a walk in the Simulator

The Simulator has no GPS. Two options:

- **Simulator → Features → Location → City Run** feeds synthetic fixes to the real
  `PhoneLocationTrackingSource`.
- Swap the tracking source for `MockTrackingSource`, which replays a scripted
  route. `AppEnvironment.preview()` already does this, and it is what every
  SwiftUI preview and test uses.

---

## Requirements

- **Deployment target: iOS 17.0.** Chosen because `@Observable` (Observation),
  MapKit's SwiftUI `Map` with `MapContentBuilder`, and `MapPolyline` all require
  iOS 17, and because iOS 17 reaches materially more devices than iOS 18 while
  giving up nothing this app needs. Not a beta OS. See `DECISIONS.md` ADR-0001.
- **Swift 6**, in full Swift 6 language mode with complete concurrency checking.
- **Xcode 16+** to build the app target.
- **iPhone, portrait.** iPad and landscape are not MVP targets; nothing in the
  architecture prevents them later.

## Third-party dependencies

**None.** Everything is Apple-native: SwiftUI, MapKit, Core Location, Swift
Charts, Observation, Swift Concurrency, Swift Testing, PhotosUI.

XcodeGen is a development tool, not a dependency — it generates the project file
and ships in nothing.

---

## What is built

### Working end to end

- Welcome, account setup, owner details, add-dog flow, confirmation
- Today dashboard: greeting, dog selector, today's totals, goal ring, insights,
  weekly chart, latest walk
- Walk preparation sheet with dog selection, activity type and GPS readiness
- Active walk recording: live map, route polyline, distance, moving time, current
  and average pace, pause/resume, GPS quality, interruption handling
- Two-tap finish that cannot be triggered by accident
- Walk summary with map, metrics, achievements earned, goal contribution, editable
  title/notes/visibility
- Activity history with search, filter by dog and type, monthly grouping, delete
- Activity detail with full route, metrics, notes, achievements, share, edit, delete
- Statistics: week / month / three months, distance / time / walks, streaks
- Goals: create, track, delete, with suggested starting points
- Achievements: 13 definitions, progress tracking, unlock celebration
- Dog profile: lifetime totals, trends, achievements, recent walks, edit, archive
- Settings: units, week start, appearance, permissions, privacy, integrations
- Explore: categories, list and map, place detail, save, directions — using clearly
  labelled bundled example places
- Crash recovery: an interrupted walk is offered back rather than lost or silently
  resurrected

### Deliberately not built (and honest about it)

These are modelled and stubbed behind protocols, and the UI says so rather than
pretending:

| Feature | State |
|---|---|
| Sign in with Apple / email accounts | `LocalAuthenticationService` throws `.notConfigured`. The UI shows them as "Coming soon" rather than as buttons that fail. |
| Cloud sync / backend | No backend. `SyncStatus` is modelled; everything is `.localOnly`. |
| Subscriptions | `FreeTierSubscriptionService` gives everyone everything. No paywall, because nothing can be bought yet. |
| Notifications | `InactiveNotificationService` schedules nothing. Reminders are designed but not wired. |
| Apple Health | `UnavailableHealthService`. Needs an entitlement and its own privacy review. |
| Companion Tracker | `TrackerDevice` and `TrackingCapabilities` exist so the pipeline does not need reshaping later. No Bluetooth code. |
| Explore places | Six bundled examples, `isVerified: false`, labelled as examples on screen. |

---

## Testing

```bash
swift test
```

148 tests, all passing, running in well under a second.

| Suite | Covers |
|---|---|
| Route filtering | Accuracy gate, stale fixes, impossible-speed rejection, jitter thresholds scaling with accuracy, whole-trace filtering, reset-on-resume |
| Route geometry | Haversine accuracy, distance totals, elevation-gain noise rejection, preview sampling |
| Walk session arithmetic | Incremental vs recomputed distance, pause accounting, paused fixes discarded, trailing-window pace, Codable round-trip |
| Statistics aggregation | Daily buckets with no gaps, half-open period boundaries, averages, week-start preference |
| Streaks | Current vs best, unwalked-today tolerance, missed-day break |
| Goal progress | Per-dog filtering, shared walks counting twice, active-days vs walk-count, clamping |
| Achievements | Every rule, no double unlocks, progress reporting, catalogue integrity |
| Route privacy | Endpoint trimming, short-route refusal |
| File repositories | Persistence across instances, filtering parity with in-memory, route separation, cascading deletes |
| Walk recorder | Every state transition, permission failures, save-failure retry, signal interruption, crash recovery |
| User journeys | Onboarding, add dog, record → pause → resume → finish → history, multi-dog walks, goal advancement, deletion, unit changes, storage failure |

Two real bugs were found and fixed by these tests during development:

1. **Pause gaps were being counted as distance.** The route filter reset correctly
   on resume, but `WalkSession.append` still measured from the last pre-pause
   point — so driving to a different park during a pause added a kilometre to the
   walk.
2. **Completing onboarding could be silently reverted.** Selecting a dog and
   completing onboarding both did a read-modify-write on the profile; whichever
   write finished last won, and the loser's change vanished. Profile writes are
   now ordered.

### Not covered

XCUITest UI automation needs Xcode and a simulator. The `CompanionUITests` suite
drives the same `AppModel` calls the buttons make, in the same order, which covers
the logic — but it does not prove a button is tappable or that a sheet presents.

---

## Project layout

```
Companion/
├── Package.swift              Multi-platform package: Core + UI + tests
├── project.yml                XcodeGen spec for the iOS app target
├── Makefile                   build / test / check / xcodeproj
├── Sources/
│   ├── CompanionCore/         No SwiftUI. Compiles and tests anywhere.
│   │   ├── Models/            Domain types
│   │   ├── Tracking/          Tracking sources, route filter, recorder
│   │   ├── Statistics/        Aggregation, streaks, goals, insights
│   │   ├── Achievements/      Catalogue and rules engine
│   │   ├── Repositories/      Protocols, file-backed, in-memory
│   │   ├── Services/          Auth, subscriptions, notifications, health, privacy
│   │   ├── Formatting/        Locale-aware formatters
│   │   └── Demo/              The single source of demo data
│   ├── CompanionUI/
│   │   ├── DesignSystem/      Tokens and reusable components
│   │   ├── App/               Environment, model, routing, tabs
│   │   └── Features/          One directory per feature
│   └── Companion/             The iOS app target. ~50 lines + Info.plist.
└── Tests/
    ├── CompanionCoreTests/
    └── CompanionUITests/
```

---

## Permissions

Requested contextually, never all at once during onboarding.

| Permission | When | Why |
|---|---|---|
| Location (when in use) | The first time a walk is started | Draws the route and measures distance |
| Photos | When adding a photo to a dog or a walk | Nothing else in the library is read |
| Notifications | Not requested — reminders are not implemented | — |

The app asks for **"when in use" only**, never "always". Recording continues with
the screen locked via the `location` background mode plus
`allowsBackgroundLocationUpdates`, which iOS permits under "when in use" while a
session is active. That is exactly the guarantee the permission screen makes.

Usage strings are in `Sources/Companion/Info.plist`.

---

## Data honesty

The app records **where the owner's iPhone went**. That is not the same as where
the dog went — an off-lead dog covers considerably more ground than the person
holding the lead.

The product therefore never claims otherwise:

- Metrics are labelled "walk distance", not "your dog's distance"
- `RecordingSource` is stored on every activity and shown on activity detail
  ("Recorded with iPhone")
- Activity detail states plainly that the route is the owner's, not the dog's
- No calorie estimates for the dog, no health inferences
- Activity guidance carries a veterinary disclaimer, placed contextually rather
  than on every screen
- Explore's sample places are marked unverified

---

## Privacy

- Everything is stored locally, in Application Support. Nothing is uploaded.
- Walks are private by default.
- `RoutePrivacy` trims a configurable radius (200 m by default) from the start and
  end of a route before sharing, because a walk almost always begins at the
  owner's front door. A walk too short to survive trimming cannot be shared as a
  map at all.
- Analytics events carry only coarse buckets — no coordinates, no dog names, no
  notes, no photos. The default analytics service records nothing at all.
- "Delete all activity history" and per-walk delete are both available in the app.

---

## Known limitations

1. **The iOS app target has never been compiled or run.** No Xcode on the build
   machine. Everything else is verified.
2. **No XCUITest coverage**, for the same reason.
3. **Persistence is JSON files, not SwiftData.** The SwiftData macro plugin ships
   with Xcode and cannot run under the Command Line Tools, so a SwiftData model
   layer could not have been compiled or tested here. The file store is a real,
   tested implementation behind `ActivityRepository` and friends — see
   `DECISIONS.md` ADR-0003 for the swap path.
4. **Previews use `PreviewProvider`, not the `#Preview` macro** — same macro-plugin
   reason. They render identically in Xcode's canvas, and this way every one of
   them is compile-verified.
5. **No app icon or launch image.** `Assets.xcassets` needs to be added in Xcode.
6. **Welcome screen artwork is a native composition**, not photography. Marked
   with a TODO.
7. **Elevation gain** comes from GPS altitude, which is noisy. Changes under 3 m
   are ignored; it is still an estimate and is only shown when above 5 m.
8. **No landscape or iPad layouts.**

---

## Roadmap

| Phase | Contents |
|---|---|
| **1 — Local MVP** | ✅ Substantially complete, pending an Xcode build |
| **2 — Accounts and sync** | Production auth, backend, cross-device sync, image storage, account deletion, data export, subscription entitlements |
| **3 — Community** | Profiles, following, feed, reactions, comments, route privacy controls, challenges, moderation |
| **4 — Discovery** | Real dog-friendly places, community routes, recommendations, verified listings |
| **5 — Companion Tracker** | Device registration, Bluetooth onboarding, independent dog GPS, live location, safe zones, escape alerts, sleep and activity metrics |

See `PRODUCT.md` for scope and non-goals, `ARCHITECTURE.md` for how it fits
together, and `DECISIONS.md` for why things are the way they are.
