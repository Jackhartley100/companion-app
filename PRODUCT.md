# Product

## Vision

**Every walk becomes part of your dog's story.**

Companion is a premium activity tracker for dog owners: a motivating daily
companion, and a record of a life spent outdoors with a dog. It is a fitness and
consistency platform, not a clinical veterinary tool — a more emotional,
dog-centred reading of activity tracking.

The dog is the emotional centre. The app says "Roxy completed her evening walk",
not "activity #14 recorded".

## Target user

A dog owner who walks their dog most days and would like to walk them more, better,
and in more places. They are not an athlete and they are not tracking themselves —
they are tracking a relationship. They want to feel good about the life they are
giving their dog.

Secondary: owners of high-energy breeds (working dogs, large breeds, young dogs)
for whom "did they get enough exercise today" is a real daily question.

## Principles

### 1. Dog first
The owner records the walk; the dog is the subject. Copy, imagery and metrics are
framed around the dog and the pair, never around a user ID and an activity count.

### 2. Honest data
The app measures where the **owner's iPhone** went. It never implies it knows the
dog's independent distance, pace or calorie burn, because without hardware on the
dog it does not. Estimates are labelled as estimates. `RecordingSource` is stored
on every activity and shown on activity detail.

This is not pedantry — it is the whole basis on which a future dog tracker becomes
a compelling product rather than a redundant one.

### 3. Fast interaction
Open, confirm the dog, tap Start Walk. Three actions for a returning owner. The
preparation sheet exists to get location ready before they are out of the door, not
to collect information.

### 4. Premium restraint
Polish comes from hierarchy, typography, spacing, motion and detail. Not from
gradients, neon, glass on every surface, or cartoon paw prints.

### 5. Positive motivation
Encouragement without guilt. "A short walk still counts." "You are 1.8 km from
Roxy's weekly goal." Never "you failed", never "your dog is missing out", no
aggressive streak-loss messaging.

A concrete expression of this: a streak is not broken until a **whole day** has
passed without a walk. Telling someone at 8am that they have lost something they
still have all day to keep is exactly the pattern this product refuses.

### 6. Privacy by design
Location is the most sensitive thing the app holds, and a walk almost always starts
at the owner's front door. Walks are private by default, routes stay on the device,
sharing trims the ends of routes, and deletion is always available and always
immediate.

## MVP scope

Delivered:

1. App shell and four-tab navigation
2. Welcome and onboarding
3. Local device account
4. Dog creation, tolerant of unknown breed, birthday and weight
5. Today dashboard
6. Walk preparation
7. Real iPhone location tracking
8. Active walk map with live metrics
9. Pause and resume
10. Protected finish, and save
11. Walk summary with editable details
12. Local activity history with search and filters
13. Activity detail
14. Weekly, monthly and three-month statistics
15. Goals with suggested starting points
16. Thirteen achievements
17. Dog profile with lifetime totals
18. Settings: units, week start, appearance, permissions, privacy
19. Light and dark appearance throughout
20. Core domain tests (148 passing)

Remaining before this milestone can be called done: **build and run it in Xcode.**
See the README's build-status table.

## Non-goals for the MVP

Explicitly not built, and not partially built:

- Proprietary tracker integration, Bluetooth pairing, cellular infrastructure,
  live dog location
- Public social feed, messaging, comments, follow graph, moderation
- Veterinary diagnosis, food tracking, medication management, insurance comparison
- E-commerce
- Full Apple Watch app; Android
- Live production subscription billing
- Full cloud backend
- Machine-learning activity classification
- Exact dog calorie estimation

Extension points exist only where they are justified — `ActivityTrackingSource` for
future hardware, `SyncStatus` for a future backend, `Entitlement` for a future
subscription. Nothing else is scaffolded speculatively.

## Core journeys

### First run
Welcome → set up on this iPhone → name and units → add a dog → "Roxy is ready for
her first walk" → Today.

Location is *not* requested here. It is requested the first time a walk starts,
with a screen that explains what it draws, when it is collected and what stays
private.

### Daily walk
Today → Start Walk → confirm dog and type → record → pause for the school run →
resume → finish (two taps) → summary → done.

### Looking back
Activities → filter by dog → open a walk → route, metrics, notes, achievements.

### Staying motivated
Today shows the goal ring, the streak, and up to three insights generated from the
owner's own stored data — never from invented averages, and never generated at all
when the sample is too small for the claim to be true in a useful sense.

## Monetisation direction

Freemium, once there is something worth charging for. Not implemented; no paywall
ships, because nothing can be bought yet and gating a feature that cannot be
purchased is a dead end for the owner.

Likely free: dog profiles, walk recording, recent history, basic weekly statistics,
one active goal.

Likely premium: unlimited history, advanced trends, multiple goals, route
discovery, personalised insights, family sharing, exports, tracker features.

`SubscriptionService`, `Entitlement` and `PremiumFeatureLock` exist so the
transition is a service swap rather than a refactor.

## Roadmap

| Phase | Contents |
|---|---|
| **1 — Local MVP** | This build |
| **2 — Accounts and sync** | Production auth, backend, cross-device sync, image storage, account deletion, data export, subscription entitlements |
| **3 — Community** | Profiles, following, feed, reactions, comments, route privacy, challenges, moderation |
| **4 — Discovery** | Real dog-friendly places, community routes, saved walks, recommendations, verified listings, business profiles |
| **5 — Companion Tracker** | Device registration, Bluetooth onboarding, firmware updates, independent dog GPS, live location, battery monitoring, safe zones, escape alerts, sleep and activity metrics, connectivity plan |

Phase 5 is the reason Phase 1 is careful about data honesty. When the tracker
arrives, "your dog walked 4.2 km" becomes a claim the product can actually make —
and it will land as a genuine new capability rather than as a correction of
something the app had been implying all along.
