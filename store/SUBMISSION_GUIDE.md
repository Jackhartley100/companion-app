# Companion — App Store Submission Guide

The path from here to "Waiting for Review", in order. Steps marked **[Jack]**
need your Apple ID, payment details or judgement; steps marked **[Claude]** can
be done in a session once the step before them is complete.

## 1. Apple Developer Program — [Jack] — DO THIS FIRST

Enrol at <https://developer.apple.com/programs/enroll> with the Apple ID
already used for device signing (jackhartley100@icloud.com). $99/year.
Approval usually takes 24–48 hours. Nothing below can happen until it clears.

## 2. Host the privacy policy and support pages — [Jack + Claude]

App Store Connect requires a **privacy policy URL** and a **support URL**.
No website needed — one free static host is enough:

- `privacy-policy.md` and `support.md` in this folder are the content, ready
  to publish.
- Easiest: a GitHub repository with GitHub Pages (free), or a public Notion
  page. Claude can convert these to styled HTML and walk through Pages setup —
  say the word once you have a GitHub account signed in.

## 3. Create the app record in App Store Connect — [Jack, ~10 min]

Once enrolled: <https://appstoreconnect.apple.com> → My Apps → "+" → New App.

- **Platform**: iOS
- **Name**: must be unique store-wide. "Companion" alone will be taken.
  Suggested: `Companion: Dog Walk Tracker` (see metadata below). The home
  screen name stays "Companion" regardless.
- **Primary language**: English (UK)
- **Bundle ID**: `com.jackhartley.companion` (register it under
  Certificates → Identifiers if it is not offered in the dropdown)
- **SKU**: `companion-ios-1` (internal only, never shown)

## 4. Fill in the listing — [Jack pastes, Claude drafted]

Ready-to-paste copy is in `metadata/` in this folder:

- `name-and-subtitle.txt` — name + 30-char subtitle
- `description.txt` — the long description
- `keywords.txt` — the 100-char keyword field
- `review-notes.txt` — notes for the App Review team (explains the
  background-location mode; reviewers reject what they can't understand)

Other fields:

- **Category**: Lifestyle (primary), Health & Fitness (secondary)
- **Age rating**: answer "No" to everything → 4+
- **Price**: Free (Agreements → the free app agreement must be Active;
  no banking/tax forms are needed for a free app)

### App Privacy section (the "nutrition label")

Companion sends nothing off-device, so the honest answers are:

- "Do you or your third-party partners collect data from this app?" → **No,
  we do not collect data from this app.**
- That yields the "Data Not Collected" label. (On-device use of location does
  not count as collection under Apple's definitions; Apple Maps lookups are
  Apple acting as the provider.)

## 5. Screenshots — [Claude, after your device-testing feedback lands]

Required: 6.9" iPhone screenshots (1320 × 2868), 3–10 of them. Claude can
capture these from the simulator with demo data once the app's content is
final — no point shooting screens that are about to change.

## 6. Build upload — [Claude prepares, Jack's account signs]

After enrolment, in a session:

1. Update signing to the paid team (`Signing.xcconfig` — DEVELOPMENT_TEAM
   changes to the new Team ID if it differs).
2. `xcodebuild archive` (Release) → export with App Store method →
   upload with `xcrun altool`/Transporter, or via Xcode Organiser.
3. The build appears in App Store Connect → TestFlight within the hour.

**Recommended: a TestFlight round first.** Install the Release build on your
phone via TestFlight, walk Roxy once with it, then promote that exact build
to review. Development builds (what you have now) behave identically but
expire; TestFlight builds are the real artefact.

## 7. Submit — [Jack, one button]

Select the build, answer the export-compliance prompt (already declared in
the app: no non-exempt encryption), submit. First reviews typically take
24–48 hours. Rejections, if any, come with a message — bring it to a session
and it gets fixed.

---

## Already done in the codebase (nothing to re-check)

- Privacy manifest (`PrivacyInfo.xcprivacy`), no required-reason APIs
- All purpose strings accurate, incl. Explore's location use
- `ITSAppUsesNonExemptEncryption` = false
- Background-location mode limited to active walk recording
- 1024 pt app icon; portrait-only, iPhone-only (both permitted)
- Release configuration builds clean; version set to 1.0.0
- In-app data deletion (no account system, so account-deletion rule is N/A)
