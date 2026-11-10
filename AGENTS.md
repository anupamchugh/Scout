# Scout: Repository Guidelines

Scout helps editors find writers and stories for outreach and newsletters from public RSS feeds and Medium sitemaps, with on-device Apple Intelligence for notes, drafts and publication reports. iPhone/iPad app `Scout` and Mac app `ScoutMac`, both bundle `com.anupamchugh.scout`, version 1.0 (1). This repository is **public** (MIT): never commit private paths, account or team IDs, keys, real people's data or anything from a private repo.

## Structure

- `project.yml` (XcodeGen) is the source of truth. `Scout.xcodeproj` is committed: edit `project.yml`, run `xcodegen generate`, and commit both. Never hand-edit `project.pbxproj`.
- `Scout/` is shared app code; `ScoutMac` compiles all of `Scout/` except `App/ScoutApp.swift`, plus `ScoutMac/`. `Packages/ScoutKit` holds feeds, scoring, export, role packs, publication comparison and the story judge, with no UI, so other apps can import it.
- `FoundationModelsUtilities` comes from `https://github.com/apple/foundation-models-utilities`, pinned `exactVersion: 1.0.0-beta5` in `project.yml`.
- `Tools/PulsePrototype` is a Mac-only command-line package over ScoutKit (`CompareAll`, `LastPosts`, `MonthReport`, `Originality`) that writes the reports in `docs/reports/`; it is not shipped. Specs are in `docs/specs/`.
- GitHub rejects files over 100 MB: `screenshots/2026-11-05/scout-walkthrough.mp4` is git-ignored and stays local (commit `4c04c46`). Check a video's size before adding it.

## Build and test

- Schemes (`xcodebuild -list`, 10 Nov 2026): `Scout` (tests `ScoutTests`, `ScoutUITests`), `ScoutMac` (no tests), `ScoutKit`.
- Package tests, no simulator: `cd Packages/ScoutKit && swift test`. Passing: Swift Testing's `Test run with N tests ... passed` line; quote N.
- App tests lease a simulator through Simlock: run `simlock instructions` and follow it, then `xcodebuild test -project Scout.xcodeproj -scheme Scout -destination "platform=iOS Simulator,id=<udid>" -DVTSimulatorSetLocation="$SIMLOCK_IOS_DEVICE_SET" -resultBundlePath build/tests.xcresult` (delete an old bundle first; narrow with `-only-testing:ScoutTests/<Suite>`). Release the lease when done. (unverified)
- Passing means the result bundle's counts, not the exit code: `xcrun xcresulttool get test-results summary --path build/tests.xcresult`. Quote passed, failed and skipped.
- Mac build: `xcodebuild -project Scout.xcodeproj -scheme ScoutMac -destination 'platform=macOS' build`; passing is `** BUILD SUCCEEDED **`. (unverified)
- `Tests/ScoutEvaluations.swift` is an Apple Evaluations suite and `Tests/EvalReplayTests.swift` replays saved runs through a scripted model; on the simulator the on-device model is unavailable ("assets required for the session are unavailable"), so real model scores come only from a device or the Mac.
- `UITests/SiriPublicationEvaluations.swift` is behind `canImport(SiriEvaluations)` and runs only on an iPhone (iOS 27.3, UI Automation on). The Siri AI tool-version intents compile only with an AppIntents SDK of 301.2 or later; past sessions ran those tests with Xcode-beta. Say which SDK you used.
- Debug-only launch arguments for UI tests and screenshots, all inside `#if DEBUG`: `-demoData` (fictional writers, in-memory store), `-tab <name>`, `-stories`, `-compareA`/`-compareB`/`-compareRun`, `-runIntent publications|slop:<key>`, `-siriCardStage`; Mac also `-section`, `-openSettings`, `-demoDecisions`. Keep any new one inside `#if DEBUG`.

## Product rules

- Ranking is computed in code; the model only writes text, and `TextGuard` hides a model line that quotes no feed evidence or adds numbers, links or praise. Outreach drafts are editable and never sent automatically.
- Demo data, screenshots and the demo video use fictional writers. Scout uses public feeds only and needs no Medium account.

## Tasks

- There is no beads ledger in this repository (10 Nov 2026). From a worktree, `bd where` falls through to an unrelated home-folder ledger: do not file Scout work there. Take the task the owner names.

## Commit

- Subject: a plain sentence saying what the person or editor now gets (`Measure title originality with Natural Language embeddings`); the body gives the measured numbers and what was not run. End with a `Co-Authored-By:` trailer.

## Releases

- No release tooling exists on 10 Nov 2026: no fastlane, no `metadata/` folder, no App Store record known. Archive, upload, submit, signing and metadata publishing run only after the owner approves that exact action; run the `hidden-feature-gate` skill on any archive first.
