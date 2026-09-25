# Dial Shot

Local-first iPhone espresso dial-in log: one-thumb shot timer, taste-verdict-driven grind adjustments, and per-bean recipe memory — no accounts, no cloud.

## Why

Home espresso dial-in is an interrupted loop: weigh, grind, start the machine, watch the scale, stop the shot, taste, then remember what changed. General coffee journals capture notes after the fact but do not make the next adjustment obvious. Dial Shot keeps the active recipe, timer, previous result, and one bounded next-step suggestion together without requiring an account, subscription, or connected hardware.

## Target users

- Home espresso makers dialing in a new bag or adapting as beans age.
- Small shared households that want a local recipe history per grinder and basket.
- Learners who need an explainable record rather than an opaque “perfect shot” score.

## Core workflow

1. Add a bean bag, grinder, and basket profile.
2. Start from a saved recipe: dose, target yield, target time, temperature note, and grinder setting.
3. Run the large one-thumb shot timer; optionally tap first-drop and stop markers.
4. Enter actual yield and choose simple sensory observations such as sour, balanced, bitter, thin, or harsh.
5. Review the prior shot beside the current result. Dial Shot proposes at most one small, explainable next adjustment—finer, coarser, longer/shorter ratio, or no change—using a deterministic user-visible rule table.
6. Save or reject that suggestion. The next shot always starts from an explicit recipe snapshot.
7. Export the complete local history as versioned JSON or a flat CSV shot log.

The suggestion is a memory aid, not an objective quality verdict. Conflicting or incomplete observations render “insufficient evidence” instead of guessing.

## MVP

- Bean, grinder, basket, and machine-note profiles.
- Immutable shot attempts linked to explicit recipe snapshots.
- Large shot timer with start, first-drop, stop, cancel, and undo-safe review.
- Dose, yield, ratio, time, grinder-setting, temperature-note, and sensory observations.
- Deterministic dial-in suggestion with the exact triggering rule and before/after preview.
- Per-bean recipe memory, shot comparison, and explainable trend summaries.
- Versioned JSON backup/restore with preview plus CSV export through the Files picker.
- VoiceOver labels, Dynamic Type, sufficient contrast, reduced-motion behavior, haptic alternatives, and controls sized for wet or busy hands.
- Zero-network default and no account.

## iPhone Duo design target

Dial Shot is a standard native iPhone app today. Native iPad support is disabled. The future iPhone Duo experience uses one display as a persistent, high-contrast timer/control surface while the other keeps the active recipe, prior shot, and adjustment rationale visible. Folding returns to a one-handed timer without losing timer state, active bean, draft measurements, or comparison selection.

`ShotWorkspaceLayout` will isolate layout policy from domain state. When Apple publishes supported dual-screen safe-region and posture APIs, that adapter can map the same timer and comparison panes onto native regions. No unavailable fold API is required now. Tablet layouts remain deferred and require explicit user opt-in.

## Platform contract

- Native Swift with SwiftUI/UIKit only.
- iPhone-only; Android and native iPad support are out of scope.
- iOS 26 SDK or newer; initial pin: Xcode 26.0.1 (17A400), iOS SDK 26.0, Swift 6 language mode.
- `TARGETED_DEVICE_FAMILY = 1` in every app-target build configuration; a real Apple build must prove built `UIDeviceFamily == [1]`.
- Bundle identifier and `PRODUCT_BUNDLE_IDENTIFIER`: `com.infinityball.dialshot`.
- No Flutter, React Native, Expo, Kotlin Multiplatform, .NET MAUI, Unity, or other cross-platform/hybrid framework.

App Store Connect bundle registration: `CREATED com.infinityball.dialshot`.

## Privacy, storage, and permissions

All records live in an app-private local SQLite database. Export happens only after an explicit Files picker action. Import is previewed before a transactional replace; failed validation leaves current data untouched. The MVP has no analytics, ads, trackers, account, cloud sync, Bluetooth, camera, microphone, location, contacts, or notification requirement. The network allowlist is empty.

## Non-goals

- No Bluetooth scale, machine telemetry, pressure profiling, camera/OCR, bean marketplace, café POS, cloud sync, social feed, public recipe database, AI tasting, or subscription.
- No claim that one recipe, ratio, temperature, or time is universally correct.
- No autonomous grinder control or concealed scoring model.
- No Android, no native iPad support, and no Flutter, React Native, Expo, Kotlin Multiplatform, .NET MAUI, Unity, or equivalent cross-platform/hybrid implementation.

## Status

Documentation and backlog scaffold only. No Xcode project, application code, build, test suite, archive, TestFlight binary, iPhone Duo compatibility evidence, or connected-device support exists yet.

## Milestones

1. Native iPhone skeleton, pure-Swift domain package, and exact toolchain gates.
2. Local persistence and fixture database.
3. Timer and shot-capture vertical slice.
4. Explainable adjustment engine and recipe memory.
5. Accessible history/comparison UI and future dual-screen seam.
6. Backup/export, privacy audit, and evidence-gated TestFlight release.

## Development quickstart

The first implementation issue will create the Xcode project and Swift packages. Planned commands on an Apple host are:

```bash
swift test --package-path Packages/DialShotKit
xcodebuild -project DialShot.xcodeproj -scheme DialShot -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

Linux may run pure-Swift package tests and documentation/configuration checks, but it cannot validate an iOS app archive or built `UIDeviceFamily`.

## Release path

CI will use the iOS 26 SDK or newer and verify exact toolchain metadata before native builds. Signed archive/TestFlight work uses repository secret names `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`, and `ASC_TEAM_ID`; values are never committed or printed. A release is incomplete until a real Apple runner records archive/export evidence and App Store Connect reports the uploaded build processed.

## License

MIT. See [LICENSE](LICENSE).
