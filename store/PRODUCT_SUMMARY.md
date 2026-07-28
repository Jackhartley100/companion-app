# Companion — Product Summary

*For marketing and business planning purposes. Compiled 28 July 2026.*

## One-line pitch

Companion is a private dog-walking tracker for iPhone that turns the walks you
take together into a picture of your dog's life outdoors — with no account, no
ads, and nothing that ever leaves your phone.

## The problem it solves

Dog owners who walk daily have no good way to see the shape of that routine
over time — how far, how often, whether it's actually enough for this
particular dog. Existing fitness trackers are built around the human athlete
and treat the dog as an afterthought (if they mention the dog at all). Social
walking apps (Strava-style) push sharing, leaderboards and competition onto
something that, for most owners, is really about the relationship with their
dog, not performance.

Companion's bet: there's a large, underserved audience who want the *tracking
and motivation* benefits of an app like Strava, applied to dog walks, without
the social pressure, and without their location history living on someone
else's server.

## Who it's for

**Primary:** A dog owner who walks their dog most days and wants to walk them
more, better, and in more places. Not an athlete, not tracking themselves —
tracking a relationship. Wants to feel good about the life they're giving
their dog.

**Secondary (higher intent):** Owners of high-energy breeds — working dogs,
large breeds, young dogs — for whom "did they get enough exercise today" is a
real daily question with real consequences (a bored working dog is a
destructive one).

## What the app actually does

**Recording**
- One-tap walk recording: live route on a map, distance, time, pace
- Keeps recording with the phone locked or in a pocket (background location,
  "when in use" permission only — never asks for "always")
- Pause and resume, for the inevitable sniffing stops
- Record with one dog or several at once

**History**
- Every walk saved with its actual route, climb, duration and pace
- Photos and notes on any walk
- Full searchable, filterable history

**Progress and motivation**
- Per-dog weekly distance goals
- Streaks — deliberately forgiving: a streak isn't broken until a whole day
  has passed with no walk, not the moment midnight ticks over
- Weekly / monthly / three-month statistics
- Thirteen achievements for milestones worth marking
- "Worth knowing" insights generated only from the owner's own real history —
  never invented averages, and never shown at all when there isn't enough data
  for the claim to be meaningful

**Explore**
- Finds real nearby dog-friendly parks, beaches, woodland, cafés and pubs via
  Apple Maps, always based on current location, sorted by distance
- Filterable by category, saveable, with directions

**Multi-dog support**
- Add as many dogs as needed; each walk counts toward each dog's own goals
  and streaks independently

## Brand and tone

**Tagline:** *"Every walk becomes part of their story."*

The dog is the emotional centre of every piece of copy. The app says "Roxy
completed her evening walk," never "activity #14 recorded." Encouragement
without guilt is a hard rule — never "you failed," never "your dog is missing
out," no aggressive streak-loss messaging.

Visual identity is a deep, natural green with a warm sand accent — restrained
enough to sit under text without shouting, distinct from generic "fitness app
blue." Premium feel is meant to come from typography, spacing, hierarchy and
motion, explicitly *not* from gradients, neon, or cartoon paw prints
everywhere.

## The privacy position (this is a genuine differentiator, not boilerplate)

This is probably the single most marketable fact about the product:

- **No user account of any kind.** Open it, add a dog, start walking.
- **No server.** Not "we encrypt your data on our server" — there is no
  server. Everything lives in local storage on the owner's iPhone.
- **No analytics SDKs, no advertising, no third-party tracking of any kind.**
- Location is read only for (a) drawing the route during an active,
  owner-started walk, and (b) a single on-demand lookup when Explore is
  opened — never continuous background tracking outside a walk.
- Full data deletion is always available and always immediate: one walk, all
  history, or everything.
- Apple's own "Data Not Collected" privacy label applies, because nothing is
  collected.

Most competitors in this space (Strava, AllTrails, various pet-specific
trackers) require an account and sync to a cloud backend by default. "It never
leaves your phone" is a claim Companion can make that most of the category
cannot.

## Honesty about what it measures

A quieter but important principle baked into the product: the app tracks
where the **owner's iPhone** went, not the dog's independent movement. It
never implies it knows the dog's own distance, pace, or calorie burn, because
without hardware on the dog it genuinely doesn't know that. This is deliberate
groundwork — see "Future hardware" below — not a limitation to hide.

## Current status (as of 28 July 2026)

- Feature-complete local MVP: all of the above is built and working, verified
  running on both the iOS Simulator and Jack's personal iPhone
- Version 1.0.0, Release build verified
- Not yet submitted to the App Store — next steps are Apple Developer Program
  enrolment (in progress) and App Store Connect listing setup
- Marketing/waitlist site is built (landing page, privacy policy, support
  page), not yet deployed to a public URL
- No monetisation is live yet — see below

## Monetisation direction (not yet built)

Planned model: **freemium**. No paywall exists yet, deliberately — nothing is
gated behind a purchase that can't yet be made, since that's a dead end for
the user experience.

Likely free tier: dog profiles, walk recording, recent history, basic weekly
statistics, one active goal.

Likely premium tier: unlimited history, advanced trend statistics, multiple
concurrent goals, route discovery, personalised insights, family sharing,
data export, and (eventually) hardware tracker features.

The underlying subscription/entitlement architecture already exists in the
codebase so this is a service swap later, not a rebuild.

## Roadmap (five phases; currently in Phase 1)

| Phase | Focus |
|---|---|
| **1 — Local MVP** (current) | Everything described above |
| **2 — Accounts and sync** | Optional cloud accounts, cross-device sync, image storage, data export, live subscription billing |
| **3 — Community** | Profiles, following, a feed, comments, route privacy controls, challenges — introduced carefully, opt-in, not required |
| **4 — Discovery** | Verified (not just Apple Maps-sourced) dog-friendly places, community-submitted routes, business listings |
| **5 — Companion Tracker** | A physical hardware add-on: Bluetooth dog tracker giving independent GPS on the dog itself — live location, safe-zone/escape alerts, battery monitoring, the dog's own activity and sleep metrics |

**Why Phase 5 matters for positioning:** Phase 1's insistence on honest,
owner's-phone-only data isn't a limitation — it's the setup. When the
hardware tracker ships, "your dog walked 4.2 km today" becomes a claim the
product can actually stand behind, landing as a genuine new capability rather
than a quiet correction of something it had been implying all along. This is
a legitimate long-term hardware/subscription business, not just an app.

## Competitive framing

- **vs. Strava / human fitness trackers:** built dog-first from the ground
  up, not a human tracker with a dog field bolted on
- **vs. AllTrails and similar:** not primarily a trail-discovery app; the walk
  and the relationship with the dog are the product, discovery is one feature
- **vs. other dog-specific trackers:** the privacy model (no account, no
  server, no sync) is unusual in the category — most require sign-up
- **vs. wearable dog trackers (Fi, Whistle, etc.):** those sell hardware
  first with an app as the companion; Companion is building the software
  relationship and audience first, with hardware as a deliberate future
  phase once there's a base of engaged, trusting owners

## Assets available for marketing use

- App icon (a paw mark on deep green)
- A marketing/waitlist landing page (built, not yet deployed) with:
  - Hero section, feature walkthroughs with real app screenshots
  - A "your walks are nobody else's business" privacy section
  - A founder's-note quote section
  - Waitlist signup (Netlify Forms — no backend needed)
- Ten photographic image prompts written for a consistent editorial/documentary
  brand look, ready to generate
- Privacy policy and support pages, written and ready to host
