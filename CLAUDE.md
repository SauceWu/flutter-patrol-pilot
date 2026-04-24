<!-- GSD:project-start source:PROJECT.md -->
## Project

**flutter-ios-agent-test**

A Claude Code / Claude Desktop skill that lets an agent autonomously validate Flutter functionality on an iOS simulator. The agent accepts test intent (natural language, Patrol `.dart` file, or Markdown spec), compiles the Flutter app, installs it on a simulator, runs Patrol tests, triages failures, fixes code, and iterates until tests pass — stopping cleanly when it hits iteration limits or divergence.

**Core Value:** The agent can take any Flutter test intent, run it on a real iOS simulator, and fix failures without human intervention — stopping cleanly and asking for help only when it genuinely cannot make progress.

### Constraints

- **Platform**: macOS only — scripts use `xcrun simctl` and Xcode toolchain
- **Flutter version**: ≥ 3.22 required (Patrol 3.x compatibility)
- **Patrol CLI**: Must be installed via `dart pub global activate patrol_cli`
- **Token budget**: Full 6-iteration run must stay ≤ 30k tokens
- **Hard rules**: Never change assertions to pass tests; never delete failing tests; never skip triage step
<!-- GSD:project-end -->

<!-- GSD:stack-start source:research/STACK.md -->
## Technology Stack

## Toolchain Overview
| Tool | Current Version | Install | Purpose |
|------|----------------|---------|---------|
| patrol_cli | 4.3.1 (stable, April 2026) | `dart pub global activate patrol_cli` | Build + run iOS tests |
| patrol (Flutter pkg) | 4.x | `flutter pub add patrol --dev` | Test DSL, native bindings |
| xcrun simctl | bundled with Xcode | pre-installed | Simulator lifecycle |
| xcresulttool | bundled with Xcode 16+ | pre-installed | Structured test result parsing |
| Flutter SDK | >= 3.22 required | pre-installed | Build flutter app |
| CocoaPods | latest | `sudo gem install cocoapods` | iOS dependency management |
## 1. patrol_cli
### Install
# Verify
# Add to PATH if not already
### pubspec.yaml additions
### Key Commands
#### patrol test (builds + runs in one step — recommended for local dev)
# Run all tests in patrol_test/ on booted simulator
# Run specific test file, verbose output
# Run with device UDID (more reliable in scripts)
# Full isolation between tests (experimental — uninstalls app between each)
# Filter by tag
#### patrol build ios (build only — for CI / separate build+run workflows)
# Build for simulator (debug, default)
# Build debug, explicit
# Build for physical device (release, for device farms)
- `.app` bunaries: `build/ios_integ/Build/Products/Debug-iphonesimulator/`
- `.xctestrun` file: `build/ios_integ/Build/Products/Runner_iphonesimulator<OS>-arm64-x86_64.xctestrun`
- Physical device (release): `build/ios_integ/Build/Products/` with `Release-iphoneos/` and `.xctestrun`
#### patrol devices (list available devices — useful in scripts)
# Output example:
# iPhone 16 (simulator)  ABC12345-XXXX-XXXX-XXXX-ABCDEFABCDEF
#### Detect booted device UDID from patrol devices
## 2. xcrun simctl
### List Devices
# Human-readable list
# JSON output — ALWAYS use this in scripts
# Filter to booted simulators (text grep — use only as fallback)
# Get UDID of booted iPhone 16
# List all available iPhone simulators (not just booted)
### Simulator Lifecycle
# Boot a simulator by UDID
# Boot by name (less reliable — use UDID in scripts)
# Wait for simulator to be ready (simctl boot returns before UI is ready)
# Use this pattern in boot_sim.sh:
# Open Simulator.app to make the booted device visible
# Poll until booted
# Shutdown one simulator
# Shutdown all booted simulators
# Erase (factory reset) a simulator
### App Lifecycle
# Install app bundle (use after patrol build ios --simulator)
# Install to specific UDID
# Launch app by bundle ID
# Launch with stdout/stderr captured
# Terminate running app
# Uninstall app
### Diagnostic Commands
# Get app container path on simulator
# Screenshot (use sparingly — token budget concern)
# Syslog capture
## 3. xcresulttool (Xcode 16+ API)
### Old API (deprecated Xcode 16+, do not use)
# DEPRECATED — requires --legacy flag, will be removed
### New API (Xcode 16+)
#### Summary (pass/fail counts, metadata)
#### All Tests (structure view)
#### Failed Test Details (failure message + stack)
# Get details for a specific test by ID
#### Activities (action log — what Patrol tapped/swiped)
#### Insights (AI/heuristic analysis of failures)
### Where .xcresult is stored
# Fallback: search DerivedData
### Parsing failed tests in scripts (parse_failure.sh pattern)
#!/usr/bin/env bash
# Quick pass/fail decision
# Get failed test identifiers and messages
# Navigate structure to find failed tests
# (exact key names vary — inspect schema with --schema flag)
## 4. Flutter Integration Points
### flutter pub get
- First-time setup
- After adding/updating `patrol` dependency version
- After any `pubspec.yaml` change
### flutter build ios
- You want to verify the Flutter app compiles before wiring up Patrol
- You are building a release IPA unrelated to testing
# Config-only (what patrol uses internally)
# Full build (for app verification, not Patrol tests)
### Full project setup sequence (new project)
# 1. Get dependencies
# 2. Install CocoaPods dependencies
# 3. Run patrol doctor (checks iOS setup)
# 4. Verify simulator is booted
# 5. Run tests
## 5. iOS Native Setup (required before any test runs)
### RunnerUITests target (in Xcode)
### RunnerUITests.m content
### ios/Podfile additions
### Deployment target
- iOS Deployment Target: same as `Runner` (minimum **13.0**)
### After Podfile changes
## 6. Breaking Changes Reference: 2.x → 3.x → 4.x
### Patrol 4.0 (December 2025) — CURRENT MAJOR
| Area | Change | Impact on Scripts |
|------|--------|------------------|
| Test directory | Default changed from `integration_test/` to `patrol_test/` | Update `--target` paths in scripts |
| Native API | `$.native` replaced with `$.platform` / `$.platform.ios` | Test code change, not CLI |
| `bindingType` param | Removed from `patrolTest()` | Test code change |
| `nativeAutomation` param | Removed (now always enabled) | Test code change |
| `integration_test` plugin | Removed as dependency | pubspec.yaml cleanup |
| `--full-isolation` flag | New flag for iOS simulator app uninstall between tests | New optional script flag |
| `patrol_finders` | Bumped to v2 with own breaking changes | Test code change |
### Patrol 3.x Notable Changes
| Version | Change |
|---------|--------|
| 3.11.0 | `--build-name` / `--build-number` flags added |
| 3.6.0 | `--ios` flag added to specify iOS version |
| 3.5.0 | Analytics enabled by default; disable via `PATROL_ANALYTICS_ENABLED=false` |
| 3.2.0 | Code coverage (`--coverage`) added |
| 3.0.0 | Uses `java` from `flutter doctor` (not system PATH) |
### Patrol 2.x → 3.x
| Area | Change |
|------|--------|
| `NativeAutomator2` | Introduced as replacement for `NativeAutomator` (both deprecated in 4.0) |
| CLI device flag | `--devices` → `--device` (both work in 3.x) |
## 7. Known Compatibility Issues
### Xcode 16.2 + iOS 18.2 (Issue #2485, January 2025)
### xcresulttool deprecated in Xcode 16
### Simulator "cloning" behavior
### `patrol test` vs `patrol build + xcodebuild test-without-building`
# After initial patrol build ios --simulator:
## 8. Environment Variables
| Variable | Purpose | Default |
|----------|---------|---------|
| `PATROL_ANALYTICS_ENABLED` | Disable telemetry (`false` for CI) | `true` |
| `PATROL_TEST_SERVER_PORT` | Port for patrol test server | `8081` |
| `PATH` | Must include `$HOME/.pub-cache/bin` for `patrol` binary | — |
## Sources
- [patrol_cli pub.dev](https://pub.dev/packages/patrol_cli) — version 4.3.1 confirmed (HIGH confidence)
- [patrol changelog pub.dev](https://pub.dev/packages/patrol/changelog) — 3.x→4.x breaking changes (HIGH confidence)
- [Patrol official docs — getting started](https://patrol.leancode.co/getting-started) — install command (HIGH confidence)
- [Patrol official docs — build command](https://patrol.leancode.co/cli-commands/build) — build flags (HIGH confidence)
- [Patrol official docs — test command](https://patrol.leancode.co/cli-commands/test) — test flags (HIGH confidence)
- [Patrol 4.0 release blog](https://leancode.co/blog/patrol-4-0-release) — breaking changes summary (HIGH confidence)
- [Context7 patrol docs](https://patrol.leancode.co/) — iOS setup, Podfile, RunnerUITests.m (HIGH confidence)
- [xcresulttool man page](https://keith.github.io/xcode-man-pages/xcresulttool.1.html) — subcommand reference (HIGH confidence)
- [Apple Developer Forums — xcresulttool deprecation](https://developer.apple.com/forums/thread/763888) — Xcode 16 deprecation (HIGH confidence)
- [Flutter issue #151502](https://github.com/flutter/flutter/issues/151502) — xcresulttool replacement commands (HIGH confidence)
- [xcrun simctl reference](https://www.iosdev.recipes/simctl/) — command flags (HIGH confidence)
- [Patrol issue #2485](https://github.com/leancodepl/patrol/issues/2485) — Xcode 16.2 compatibility issue (MEDIUM confidence, issue unresolved)
<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->
## Conventions

Conventions not yet established. Will populate as patterns emerge during development.
<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->
## Architecture

Architecture not yet mapped. Follow existing patterns found in the codebase.
<!-- GSD:architecture-end -->

<!-- GSD:skills-start source:skills/ -->
## Project Skills

No project skills found. Add skills to any of: `.claude/skills/`, `.agents/skills/`, `.cursor/skills/`, `.github/skills/`, or `.codex/skills/` with a `SKILL.md` index file.
<!-- GSD:skills-end -->

<!-- GSD:workflow-start source:GSD defaults -->
## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through a GSD command so planning artifacts and execution context stay in sync.

Use these entry points:
- `/gsd-quick` for small fixes, doc updates, and ad-hoc tasks
- `/gsd-debug` for investigation and bug fixing
- `/gsd-execute-phase` for planned phase work

Do not make direct repo edits outside a GSD workflow unless the user explicitly asks to bypass it.
<!-- GSD:workflow-end -->



<!-- GSD:profile-start -->
## Developer Profile

> Profile not yet configured. Run `/gsd-profile-user` to generate your developer profile.
> This section is managed by `generate-claude-profile` -- do not edit manually.
<!-- GSD:profile-end -->
