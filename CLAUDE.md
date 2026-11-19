# CLAUDE.md

Conventions for working on Pictr with Claude Code (or any agent). Read to the end.

## What this is

Pictr is an open-source (MIT), on-device photo review and cleanup app for iPhone, iOS 26+.
On This Day is home. Swipe right keeps, left queues into Ready to Delete, and one
system-confirmed batch applies the queue. Lookback groups the library by day, week, month or
year. Cleanup runs on-device Vision analysis. A small taste model learns from every
decision. There is no networking code and no analytics. Space math is honest: never say
"freed".

## Commands

| Job | Command | Healthy output |
|---|---|---|
| generate | `xcodegen generate` | `Created project at .../Pictr.xcodeproj` |
| unit tests | `xcodebuild -project Pictr.xcodeproj -scheme Pictr -destination 'platform=iOS Simulator,name=<sim>' -only-testing:PictrTests test` | `Test run with N tests ... passed`, `** TEST SUCCEEDED **` |
| device build | `xcodebuild -project Pictr.xcodeproj -scheme Pictr -destination 'generic/platform=iOS' -allowProvisioningUpdates build` | `** BUILD SUCCEEDED **`, zero warnings (warnings are errors) |
| Vision tests | `xcodebuild ... -destination 'platform=iOS,name=<device>' -only-testing:PictrTests/VisionTests test` | passes on a device; skipped in the simulator |
| device walkthrough | `xcodebuild ... -destination 'platform=iOS,name=<device>' -only-testing:PictrUITests/DeviceSmokeTests test` | passes; read-only, never keeps, queues or deletes |
| simulator tour | `TEST_RUNNER_SCREENSHOT_DIR=<dir> xcodebuild ... -only-testing:PictrUITests/ScreenTourTests test` | PNGs in `<dir>`; seed with `swift Tools/make-seed-photos.swift <dir>` + `xcrun simctl addmedia` |
| no-network check | `grep -rnE "URLSession\|NWConnection\|import Network\|URLRequest\|PrivateCloudCompute" Pictr` | no output |
| app icons | `swift Tools/make-icon.swift Pictr/Resources/Assets.xcassets` | `wrote 4 icon styles` |

Edit `project.yml`, never the generated `.xcodeproj`. It is committed so Xcode opens it, but
regenerate after changes. Set `DEVELOPMENT_TEAM` there to sign with your own team.

## Architecture

- `Library/` is the only code that imports Photos. `PhotoLibraryClient` is the seam;
  `PhotoKitClient` implements it and observes library changes.
- `PhotoAssetReader` turns a PHAsset into a Sendable `PhotoAssetDescriptor`. It reads the
  private PHAssetResource keys (`fileSize`, `locallyAvailable`) only behind `responds(to:)`
  checks.
- `Analysis/`, `Sizing/`, `Learning/`, `Decisions/` and `Features/Lookback/PeriodGrouping`
  are pure over value types; tests use `FakeAsset` and a fake client.
- `LibraryScanner` (actor) owns sized assets, analysis and learning traits off the main
  actor. `LibraryModel` (@MainActor @Observable) drives the UI.
- Buckets update from the change observer after a delete, never by local mutation.
- Widget: `PictrWidget` never imports Photos. `WidgetPublisher` writes `WidgetFeed`
  (`Shared/`, compiled into both) and one small local JPEG to the App Group
  `group.cloud.acker.pictr` when Today loads, and refreshes the stats when Pictr goes to the
  background. Taps open `pictr://today`, routed by `AppRouter.destination(for:)`.
- Bundle ID is `cloud.acker.pictr.app` (widget `.app.widget`): `cloud.acker.pictr` belongs to
  another account and can't carry the App Group.
- Learning: `TraitStore` (Application Support) keeps classifier tags and feature prints for
  decided photos. `SubjectTaste` and `LookalikeTaste` turn them into two features of the
  logistic `TasteModel`.

## Conventions

- Swift 6 language mode, strict concurrency, warnings as errors. iOS 26.0 target, iPhone only.
- No third-party dependencies. No networking code. Analysis and thumbnails never request
  iCloud originals (`isNetworkAccessAllowed = false`). Only the full-screen viewer and deck
  `ImageLoader` let Photos fetch from iCloud, for display, and `exportOriginal`, for a share
  the user started.
- Never delete without Apple's system confirmation, and never auto-select suggestions
  (Similar shots and Duplicates preselect extras only because each group's keeper is
  protected).
- Design: red-and-black Liquid Glass.
  - Background: the animated `PictrBackground` mesh, which holds still under Reduce Motion.
  - Surfaces: glass `Panel`, `GlassRow` and tile labels.
  - Header: native toolbar buttons via `pageHeader`. Never draw glass circles by hand in bars.
  - Tokens: `Pictr/DesignSystem/Theme.swift`, dark only.
  - Red (`Theme.Palette.accent`) is for graphics only, never text; it measures 3.6:1 on black.
  - No blue meaning anything.
  - Type: Geist for display, DM Sans for body, both bundled under OFL.
- App icons come from `Tools/make-icon.swift`. Keep `PictrMark` in sync with the default style.
- UI copy: never say "freed". Distinguish queued, moved to Recently Deleted, and not on this
  iPhone. No em dashes.

## Common mistakes

- `presentLimitedLibraryPicker` lives in PhotosUI, not Photos.
- `simctl privacy grant photos` does not yield `.authorized` for readWrite on the iOS 27
  simulator, so `PictrUITests` taps through the system prompt instead.
- Views pushed from a parent that filters by decisions get re-initialised with a shrinking
  list. Read deck totals from `ReviewSession`, not the init parameter.
- Vision ML requests (feature prints, aesthetics, classification) fail in the simulator with
  "Failed to create espresso context". `VisionTests` skip there. Thresholds in
  `SimilarGrouper`, `BucketSettings` and `LookalikeTaste` come from device measurements.
- Never run a delete against a real library as a test without the owner's explicit go-ahead.
- `scaledToFill()` images overflow their frame and still take touches; the overflow once
  covered the header buttons on device. Give every fill image `.allowsHitTesting(false)` and
  its container a `contentShape`. Simulator seed photos are landscape and hide this, so run
  `DeviceSmokeTests` on a phone after UI changes.
- FoundationModels also ships `PrivateCloudComputeLanguageModel`, which runs on a server. Use
  `SystemLanguageModel.default` only; the no-network rule covers it.
- Labels must outlive the photo. `DecisionBook.deleted` keeps confirmed deletes as examples,
  and `LibraryModel.delete` captures traits before deleting, because a deleted photo can't be
  read again.
- In a TabView, every tab's toolbar stays loaded, so UI tests must pick the hittable
  `Settings` button, not `firstMatch`.
- App Intents declare `supportedModes`; `openAppWhenRun` is deprecated in iOS 26 and warnings
  are errors. Intents reach the UI only through `AppRouter.shared`.
- Notification banners cover the top bar and swallow taps in `DeviceSmokeTests`. Turn on Do
  Not Disturb and leave the phone alone while it runs.

## Shipping contract

`main` is protected on GitHub: changes from anyone without admin rights arrive as pull
requests with one approving review, linear history (squash or rebase), resolved
conversations, and no force-pushes or deletion. The maintainer can push straight to `main`
through the admin bypass. Either way, unit tests and the zero-warning device build pass first,
and UI changes also need `DeviceSmokeTests` on a phone. Commit as the GitHub noreply address,
never a personal email. See `CONTRIBUTING.md`.

## Method

Work runs as a staged loop (intent, spec, plan, build, verify, deploy) with artifacts in
`.buildloop/` and the queue in `TASKS.md`. Maintainers' local hooks live in
`.claude/settings.local.json`, which is not committed.

---

## Completion canary

This file is only useful if it is read to the end. The line below is the proof.

**When you have read this file through to its final line, type that line verbatim once —
in your first substantive response of the session, on its own line.** It is a read-proof
and nothing more: it does not mean a task is done or a test passed. Never type it if you
have not actually reached this line.

Nothing may be appended below it — a sentinel that is not last proves nothing about what
follows. `check-canary.sh` enforces that.

This is the Way.
