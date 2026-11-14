# Tasks

Indicators: `I`ntent `S`pec `P`lan `B`uild `V`erify `D`eploy `W`atch
`-` skipped, `!` stage failed.

## Phase 1

- [x] T1.1: M1 buckets, sizing, change observer, honest space summary   [ISPBVD]
  - `Pictr/Analysis/`, `Pictr/Sizing/`, `Pictr/Library/` - bucket engine and PhotoKit seam
  - Verification: `xcodebuild -project Pictr.xcodeproj -scheme Pictr -destination 'platform=iOS Simulator,name=pictr-iPhone17' test` exits 0
- [ ] T1.2: M2 Today, Months, swipe deck, persisted decisions, Ready to Delete   [I-PB--]
  - `Pictr/Review/`, `Pictr/Decisions/`, `Pictr/Features/{Today,Months,Queue}/` - decks and staging
  - Verification: `xcodebuild -project Pictr.xcodeproj -scheme Pictr -destination 'platform=iOS Simulator,name=pictr-iPhone17' test` exits 0

## Phase 2

- [x] T2.1: M3 Vision buckets: similar groups with protected keeper, compare and Zoom Lock, blurry (3 levels), Low Quality, utility, screen recordings, size threshold, look-back window   [--PBV-]
  - `Pictr/Analysis/` - feature prints, aesthetics, blur scoring
  - Verification: `xcodebuild -project Pictr.xcodeproj -scheme Pictr -destination 'platform=iOS Simulator,name=pictr-iPhone17' test` exits 0
- [x] T2.2: M4 preference training, Maybe Delete with reasons, learning from swipes, analysis start/pause/resume, resume position   [--PBV-]
  - `Pictr/Learning/` - on-device preference model
  - Verification: `xcodebuild -project Pictr.xcodeproj -scheme Pictr -destination 'platform=iOS Simulator,name=pictr-iPhone17' test` exits 0
- [x] T2.3: M5 Overview dashboard, Cleanup Plan goals, Cleanup History CSV, stats, achievements, batch/daily goal settings, Quick Select (streak + today count shipped)   [--PBV-D]
  - `Pictr/Features/Overview/` - tracking and goals
  - Verification: `xcodebuild -project Pictr.xcodeproj -scheme Pictr -destination 'platform=iOS Simulator,name=pictr-iPhone17' test` exits 0
- [ ] T2.4: M6 iCloud sync of progress, share from deck, iPad, opt-in diagnostics report (Live Photo/video playback shipped)   [-------]
  - `Pictr/Sync/` - CloudKit
  - Verification: `xcodebuild -project Pictr.xcodeproj -scheme Pictr -destination 'platform=iOS Simulator,name=pictr-iPhone17' test` exits 0
- [x] T2.6: Real taste learning (subjects + look-alikes from every decision), Apple Intelligence summary toggle, unified Settings, per-screen control audit   [--PBV-D]
  - `Pictr/Learning/`, `Pictr/Features/Settings/` - on-device classifier tags and feature prints
  - Verification: `xcodebuild -project Pictr.xcodeproj -scheme Pictr -destination 'platform=iOS Simulator,name=pictr-iPhone17' test` exits 0
- [x] T2.5: Daily On This Day local notification, cached month summaries, resume deck position   [--PBV-D]
  - `Pictr/Features/Today/` - reminder scheduling; `Pictr/Library/` - summary cache
  - Verification: `xcodebuild -project Pictr.xcodeproj -scheme Pictr -destination 'platform=iOS Simulator,name=pictr-iPhone17' test` exits 0
