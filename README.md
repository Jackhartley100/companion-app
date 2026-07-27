# Companion

A premium activity tracker for dog owners. Record your walks, build a routine, and
keep a lifetime of adventures with your dog in one place.

*Companion* is a working name.

---

## Build status

| What | Status |
|---|---|
| `CompanionCore` (domain, tracking, statistics, persistence) | ✅ Builds, 165 tests passing |
| `CompanionUI` (design system, every screen, previews) | ✅ Builds |
| `Companion` (the iOS app target) | ✅ Builds clean for iOS, zero warnings |
| Running in the simulator | ✅ Verified — onboarding, live recording, pause/resume, save, history |
| Running on a physical iPhone | ✅ Verified on a real walk — see below |

Built against **Xcode 26.6**, and **recorded on a real walk** on an iPhone 16 Plus
(free personal provisioning).

Confirmed on device:

- Recording survives the screen locking — the route comes back unbroken, which is
  the background-location mode doing its job and the single thing most likely to
  have been silently wrong
- Distance matches a known route
- The two-tap finish is comfortable one-handed with a lead in the other
- Haptics fire on start, finish and the rest
- Locale defaults to kilometres and kilograms in the UK, unlike the US simulator

Not yet exercised on device: **pausing mid-walk**, and **degraded GPS** (no weak
signal encountered). Both are covered by unit and UI tests, so the logic is
tested — but neither has met real hardware.

Everything except a ~50-line app entry point lives in a multi-platform Swift
package that also builds for macOS, so the domain layer and the whole UI can be
compiled and unit-tested from the command line in under a second — without
launching Xcode. That started as a workaround for not having Xcode installed; it
has stayed because the fast loop is worth keeping.

Still unverified: a physical device, and therefore real GPS accuracy, background
recording with the screen locked, and haptics. See
[Known limitations](#known-limitations).

---

## Quick start

### Fast loop — domain and UI, no Xcode needed

```bash
make check
```

Builds every package target with warnings treated as errors and runs all 165
tests. Takes seconds.

### Running the app

```bash
brew install xcodegen && make xcodeproj
```

Then open `Companion.xcodeproj`, choose an iPhone simulator, and run. If
`xcodebuild` complains that it cannot find Xcode:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

Xcode 26 ships without simulator runtimes — if there are no destinations, install
one from **Xcode → Settings → Components**.

### UI tests

```bash
xcodebuild -scheme Companion -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' test
```

Five XCUITest cases cover onboarding, control reachability, pause/resume, the
two-tap finish, and a saved walk reaching history.

### Running on your iPhone

This is the only way to test what actually matters for a walking app: real GPS,
and recording that survives the screen locking.

**1. Find your Team ID.** Xcode → Settings → Accounts → add your Apple ID if it is
not there → select it → the Team ID is the 10-character string beside your name.
A **free Apple ID works** — it appears as "(Personal Team)".

**2. Fill in `Signing.xcconfig`** (created for you by `make xcodeproj`, and
gitignored so your Team ID never gets committed):

```
DEVELOPMENT_TEAM = ABCDE12345
PRODUCT_BUNDLE_IDENTIFIER = com.jackhartley.companion
```

The bundle identifier must be globally unique, even on a free account. Change it
if registration fails.

**3. Connect the iPhone** by USB, unlock it, and tap **Trust** on the prompt.
Check the Mac can see it:

```bash
make devices
```

**4. Build and run.** Open `Companion.xcodeproj`, pick your iPhone from the device
menu, and press Run. From the command line instead:

```bash
make device
```

**5. Trust the developer certificate on the phone.** The first launch will refuse
with "Untrusted Developer". On the iPhone: **Settings → General → VPN & Device
Management → your Apple ID → Trust**. Then launch again.

#### If you are using a free Apple ID

- The app **stops working after 7 days** and must be rebuilt from Xcode. A paid
  Apple Developer Program membership (£79/year) extends this to a year.
- You are limited to 3 apps installed this way, and 10 new device registrations
  per week.
- Background location, MapKit and everything else in the MVP work fine on a free
  account. Nothing here needs a paid entitlement.

#### What to actually test outdoors

The simulator cannot exercise any of these:

- **Distance accuracy.** Walk a route you know the length of and compare.
- **The screen locking mid-walk.** Lock the phone, keep walking, unlock. The route
  must be continuous, with no gap — this is the `location` background mode and
  `allowsBackgroundLocationUpdates` doing their job.
- **Pausing for a genuine stop**, then resuming somewhere else. The polyline
  should break rather than draw a straight line across ground you did not walk.
- **Poor signal.** Under trees or between tall buildings, the status pill should
  drop to "Weak signal" and recording should continue rather than fail.
- **Battery cost** over an hour.
- **Readability in daylight**, one-handed, holding a lead.
- **Haptics** on start, pause, resume and finish.

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

Bugs these tests found and fixed:

1. **Pause gaps were being counted as distance.** The route filter reset correctly
   on resume, but `WalkSession.append` still measured from the last pre-pause
   point — so driving to a different park during a pause added a kilometre to the
   walk.
2. **Completing onboarding could be silently reverted.** Selecting a dog and
   completing onboarding both did a read-modify-write on the profile; whichever
   write finished last won, and the loser's change vanished. Profile writes are
   now ordered.
3. **`UIApplication` touched off the main actor.** Invisible to the macOS build,
   because `UIApplication` does not exist there and the bodies compiled away to
   nothing. Four warnings on the first real iOS compile.
4. **Zero distance rendered in two different units.** Today showed "0.00 mi" for
   the day and "0 ft" for the week — the same nothing, measured twice.
5. **XcodeGen was silently overwriting the Info.plist**, taking every usage
   description and the background-location mode with it.

### UI tests

```bash
xcodebuild -scheme Companion -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' test
```

| Test | Covers |
|---|---|
| `testCanCompleteOnboarding` | Welcome → account → owner → dog → ready |
| `testAddDogFormControlsAreHittable` | Every control on the add-dog form is reachable, not merely visible |
| `testPauseAndResume` | Pause offers Resume and Discard; resuming hides Discard |
| `testFinishRequiresTwoTaps` | One tap must *not* end a walk; two taps saves it |
| `testSavedWalkAppearsInHistory` | Record → finish → save → the walk is in Activities |

### Not covered

Anything that only happens on real hardware: GPS accuracy in the wild, background
recording with the screen locked, and haptics.

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

1. **Pause and degraded GPS are untested on device.** Both work in the simulator
   and are covered by unit and UI tests, but neither has been exercised outdoors.
   Pausing is the higher risk of the two: it is the one path where the app stops
   and restarts the flow of accepted fixes, and a mistake there corrupts the
   distance of an otherwise good walk.
2. **Battery cost over a long walk has not been measured.** A two-hour hike at
   `kCLLocationAccuracyBestForNavigation` is the realistic worst case and has not
   been tried.
3. **Persistence is JSON files, not SwiftData.** The SwiftData macro plugin ships
   with Xcode and cannot run under the Command Line Tools, so a SwiftData model
   layer could not have been compiled or tested here. The file store is a real,
   tested implementation behind `ActivityRepository` and friends — see
   `DECISIONS.md` ADR-0003 for the swap path.
4. **Previews use `PreviewProvider`, not the `#Preview` macro** — so they compile
   under the command-line toolchain too. They render identically in Xcode's
   canvas, and this way every one of them stays compile-verified by `make check`.
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
