# Dial Shot implementation plan

## Scope

Deliver a local-first native Swift iPhone app for capturing espresso shots, comparing attempts, and carrying a clearly explained next adjustment into the following attempt. Domain truth is a sequence of immutable shot attempts and recipe snapshots; UI summaries are derived and reproducible.

## Platform and policy

- Native Swift 6 with SwiftUI/UIKit and standard Apple tooling.
- iPhone-only with native iPad support disabled.
- iOS 26 SDK or newer, initially pinned to Xcode 26.0.1 (17A400) and iOS SDK 26.0.
- Bundle identifier: `com.infinityball.dialshot` everywhere, including `PRODUCT_BUNDLE_IDENTIFIER`, Info.plist, signing, provisioning, and release configuration.
- Every app-target configuration uses `TARGETED_DEVICE_FAMILY = 1`; the built product must prove `UIDeviceFamily == [1]` on an Apple runner.
- Android is not a target. Native iPad support requires explicit user opt-in.
- No Flutter, React Native, Expo, Kotlin Multiplatform, .NET MAUI, Unity, or equivalent cross-platform/hybrid framework.

## Architecture

### DialShotKit

A pure-Swift package with no UIKit dependency:

- `BeanBag`, `GrinderProfile`, `BasketProfile`, `RecipeSnapshot`, and immutable `ShotAttempt`.
- Decimal/rational-safe dose, yield, and ratio calculations; no binary floating-point display drift.
- Timer event reducer (`idle`, `running`, `stopped`, `reviewing`, `saved`, `cancelled`) with monotonic elapsed-time inputs.
- Sensory observations represented as a bounded vocabulary plus optional free text.
- `AdjustmentRule` table whose predicates, exclusions, confidence state, and human-readable rationale are serializable.
- `DialInEngine` that produces zero or one adjustment; missing or conflicting evidence yields an explicit unknown state.
- Versioned backup codec, import validation, and migration fixtures.

### DialShotStore

GRDB over app-private SQLite:

- Forward-only schema migrations.
- Append-only saved shots; corrections create replacement records rather than rewriting historical truth.
- Repository protocols with in-memory fakes.
- Fixture database regenerated deterministically and checked in for migration tests.

### DialShot app

- SwiftUI scene and feature composition.
- `ShotWorkspaceLayout` selects folded single-pane presentation now and is the sole future native dual-screen adapter seam.
- Timer state lives above presentation layout so fold/unfold transitions cannot reset an active shot or discard draft values.
- Files-based JSON backup/restore and CSV export.
- Network allowlist remains empty.

## Dual-screen value and migration

The design target places a persistent timer, first-drop/stop controls, and high-contrast live ratio on one iPhone Duo display. The other display shows the active recipe, immediately previous shot, and adjustment rationale. A spanned review can compare two recipe snapshots without hiding controls. Folding preserves timer state and returns to the focused one-handed timer.

Current implementation remains a standard iPhone app with iPad support disabled. No fold posture, hinge, or second-screen API is assumed. Once supported APIs exist, only `ShotWorkspaceLayout` and safe-region policy should change; domain, timer, draft, selection, and persistence state remain shared. Native iPad/tablet layouts are deferred and require explicit opt-in.

## Milestones and dependency order

1. **Skeleton and CI** — create Xcode project, Swift packages, launch smoke test, exact Xcode/SDK pin checks, iPhone-only source and built-product checks, zero-network gate.
2. **Domain engine** — implement models, units, ratios, timer reducer, recipe snapshots, and deterministic rule engine with exhaustive fixtures.
3. **Persistence** — add GRDB migrations, repositories, fixture database, query boundaries, and storage tests.
4. **Capture workflow** — build profile/recipe setup and the accessible one-thumb timer through review/save.
5. **Comparison and layout** — ship history, per-bean recipe memory, adjustment rationale, accessible charts/tables, and `ShotWorkspaceLayout` continuity tests.
6. **Ownership and release** — versioned backup/restore preview, CSV export, privacy checks, archive/upload workflow, and App Store metadata.

## Testing strategy

- Swift Testing unit/property tests for ratios, unit conversion, decimal formatting, rule precedence, unknown/conflict handling, timer transitions, and backup migration.
- Golden fixtures for identical inputs producing identical suggestions and rationale.
- SQLite migration and repository contract tests against in-memory and checked-in fixture databases.
- UI tests for first launch, setup, live shot timing, interrupted/relaunched draft behavior, review/save, comparison, backup preview, and large Dynamic Type/VoiceOver identifiers.
- Clock tests inject monotonic and wall-clock providers; no sleep-based timing assertions.
- Privacy gate scans source and artifacts for undeclared network endpoints; expected allowlist is empty.
- Apple CI records actual Xcode version, build version, SDK version, PR-head SHA, simulator destination, built `UIDeviceFamily`, test result, and artifact provenance.
- Linux checks are limited to pure-Swift and structural evidence; they never substitute for native app/archive verification.

## Data ownership and export

- App-private SQLite is canonical.
- JSON backup includes schema version, stable IDs, profiles, recipes, shot events, and rule-set version.
- Restore parses and validates into staging, displays counts/warnings, then transactionally replaces only after confirmation.
- CSV is a flat human-readable shot export; it is not a lossless restore format.
- No account, telemetry, analytics, cloud sync, advertising, tracking, or background network access.

## Accessibility

- Controls remain operable at accessibility text sizes and in portrait.
- Timer status is conveyed through text and accessibility announcements, not color or haptics alone.
- Start/first-drop/stop targets remain at least 44×44 points, with primary controls materially larger.
- Reduced motion removes decorative transition motion without changing state feedback.
- Sensory observation chips expose selected state and unambiguous labels.

## Packaging and distribution

- SPM pins package versions; no unreviewed latest-version resolution in CI.
- CI builds with iOS 26 SDK or newer and enforces `TARGETED_DEVICE_FAMILY = 1` in every app configuration.
- Bundle/signing contract is `com.infinityball.dialshot`; App Store Connect registration is complete.
- TestFlight/App Store workflow references only `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`, and `ASC_TEAM_ID` secret names.
- Release evidence requires a signed archive, export, upload response, processed App Store Connect build, and source commit mapping. No source-only release claim.

## Risks

- **Suggestion overconfidence:** hard cap at one adjustment, show exact evidence/rule, preserve “insufficient evidence,” and let users reject suggestions.
- **Grinder settings are not universal:** store settings as user-authored text/ordinal values scoped to a grinder; never compare across grinders without an explicit user mapping.
- **Timer integrity:** use monotonic elapsed time and persist recoverable state; wall-clock changes cannot alter elapsed duration.
- **Schema drift:** version every backup and test every migration against fixtures.
- **SDK uncertainty:** keep dual-screen support behind one layout boundary and make no compatibility claim before real APIs/hardware evidence.
- **Release environment:** fail closed if exact required Apple toolchain or credentials are unavailable.

## Explicit non-goals

No Bluetooth scale/machine integration, pressure profiling, automatic grinder control, camera/OCR, store/catalog feed, social network, cloud synchronization, AI tasting, universal espresso-quality claims, or subscription. No Android, no native iPad support, and no Flutter, React Native, Expo, Kotlin Multiplatform, .NET MAUI, Unity, or equivalent cross-platform/hybrid framework.
