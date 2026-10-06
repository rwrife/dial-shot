# Dial Shot data ownership and release evidence (#7)

## Local data controls

Open **Beans & history → Data & backup** on an iPhone. **Export backup (JSON)** presents the system Files export picker with a complete version-1 document (beans, grinders, baskets, recipe snapshots/active flags, immutable shots with original suggestions, selected workspace bean). **Export shot log (CSV)** presents the system share sheet; the flat header is `date,bean,roast,grinder,setting,dose,yield,ratio,time,taste,adjustment`, CRLF-delimited with quoted embedded commas/quotes/newlines. Missing verdicts/adjustments are `unknown`. Grinder settings are strings scoped to the named grinder, not converted across grinders.

**Restore from backup** uses the Files picker, validates product ID, schema/version consistency, decimals, domain invariants, duplicate IDs and references, then shows entity counts in a destructive confirmation. Cancel does not write. Confirmation uses the same validated in-memory document shown in the preview, not a second read of a file that could have changed between preview and tap. The SQLite replacement is one transaction, and the capture draft/selected bean are refreshed after success. Keep an exported file outside the app sandbox before deleting the app: uninstalling an iPhone app deletes its Documents directory.

## Privacy and accessibility

No app account, analytics, tracking framework, or app-network API is added. `toolchain.json` keeps `network_allowlist: []`; `bash scripts/check_zero_network.sh` checks first-party code. Files and share sheets are user-initiated system surfaces (destination choices are the user's, not an app network call). JSON export and CSV/restore controls have 44-point minimum label frames, VoiceOver labels, and scalable SwiftUI text; reduced-motion behavior is unchanged. Simulator journey exercises actual local writes/preview/cancel/restore with the system picker suppressed in DEBUG; manual system-picker and VoiceOver verification on a device remain distinct checks.

## Release workflow

`.github/workflows/release.yml` triggers on manual dispatch and `v*` tags. It selects the **exact** Xcode 26.0.1 / 17A400 and iOS 26.0 SDK via `toolchain.json`, archives `com.infinityball.dialshot` with registered team automatic signing, verifies the archived bundle identifier and `UIDeviceFamily == [1]`, checks the compiled icon, exports with `destination=upload`, then polls App Store Connect for this run number's processed TestFlight build. It requires the configured GitHub Actions secret **names** `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`, `ASC_TEAM_ID`; the key is written mode-600 under runner temp and deleted in an always step. A manual dispatch **uploads** as well; do not dispatch as a dry-run. To release from a reviewed main snapshot, create a `v*` tag at that commit or manually dispatch on that exact ref. A tag is not created automatically here.

## Evidence boundary

- Linux `swift:6.2-noble`: `swift test` for DialShotKit and DialShotStore (SQLite headers required), source syntax parsing for SwiftUI and UITests, script unit tests, zero-network policy check, and actionlint are executable locally.
- Pinned macOS `ios` PR check: simulator build, actual built `UIDeviceFamily`, and XCUITest are **pending until that exact PR head succeeds**. Linux source checks cannot prove them.
- A real signed archive, uploaded IPA, processed TestFlight build ID, system Files-picker journey, VoiceOver and on-device behavior require their own observed macOS/device runs. Workflow configuration and secret-name availability alone are not evidence they ran; do not declare release acceptance complete without a successful release run and processed build ID.
