# Changelog

All notable changes to this skill are documented here.

The format is loosely based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versions are not published as git tags yet; the `v0.x` strings referenced in `README.md` and `reference/troubleshooting.md` correspond to the entries below.

## [Unreleased]

### Added

- **Nickname `fpp`** registered in `SKILL.md` frontmatter `description`. Agent now activates this skill on short invocations like `fpp` / `run fpp` / `/fpp` / `跑一下 fpp` / `用 fpp 验证一下` in addition to the existing English/Chinese trigger phrases. Skill directory / `name` field is unchanged (still `flutter-patrol-pilot`) to preserve client path conventions. README §"昵称: `fpp`" documents the full list of supported invocations.
- **`scripts/install_axe.sh`** — opt-in installer for [AXe CLI](https://github.com/cameroncooke/AXe) (the optional dependency that makes `sim_snapshot.sh --tree` ~10× cheaper than a screenshot). Wraps `brew install cameroncooke/axe/axe`; idempotent (already-installed → `action: "noop"`); supports `--dry-run` and `--force`. **Never invoked automatically by the skill** — `SKILL.md` §"Optional: AXe CLI" requires the agent to ask the user *"want me to install AXe via Homebrew?"* before running it. Falls back to a clean error JSON if `brew` is missing. Stdout is a single-line JSON object (`success` / `action` / `axe_path` / `axe_version` / `elapsed_s` / `error`).
- **`init_project.sh` summary now reports `axe_present: bool`** and, when AXe is missing, appends an `OPTIONAL:` entry to `next_steps[]` pointing at `install_axe.sh` with an explicit "ask the user first" instruction. Stays consistent with the existing "do not auto-install globally" rule.
- **README §"可选: AXe CLI(让 a11y triage 更省 token)"** documents the install path, the agent-side consent contract, and what happens if you skip it (graceful screenshot fallback).
- **`SKILL.md` §"Optional: AXe CLI"** spells out the agent-side contract: when about to call `sim_snapshot.sh --tree` and `axe` is absent, the agent must ask the user once per session before invoking `install_axe.sh`. On refusal, fall back to screenshot and don't ask again.

### Changed

- **Soften hardcoded `patrol_cli 4.3.1` → `patrol_cli 4.3.x` in user-facing docs.** SKILL.md / README.md / `reference/patrol-patterns.md` now state "developed against 4.3.x — currently 4.3.1 — forward-compatible within 4.3.x; bumps to 4.4+ may need re-verification of Issue 15/16 workarounds". This reduces false-failure pressure when users run a slightly newer 4.3.x without anything actually breaking. **Exception:** `reference/troubleshooting.md` L619 keeps the exact `patrol_cli-4.3.1/lib/src/crossplatform/app_options.dart:279` path because it's a forensic citation (must remain reproducible — readers need to find that exact line in their pub-cache). The prose around the citation already says `patrol_cli 4.3.x`.
- **`init_project.sh` Step 7 now uses the `xcodeproj` gem instead of `sed` for both Xcode-26 pbxproj fixes** (`objectVersion 70 → 60`, `ENABLE_USER_SCRIPT_SANDBOXING YES → NO`). The gem is CocoaPods' own pbxproj parser, robust against whitespace / ordering / format drift that breaks regex patches across Xcode versions. The sandboxing fix now flips the setting across **every** target's build_configurations + the project root's, instead of relying on a literal-text sed match. `objectVersion` uses `instance_variable_set(:@object_version, '60')` because xcodeproj 1.27.x exposes it as reader-only (verified: setter raises `NoMethodError`, instance var write is honored on `project.save`). Unexpected gem output is logged as a `WARNING` (non-fatal — these patches are safety nets, not mandatory). README §"手工 setup" updated with the ruby/gem one-liner alongside the legacy sed for emergency debugging.

## [v0.3] — 2026-04

Major release: full project bootstrap + two new bug-class workarounds for Xcode 26 / patrol_cli 4.3.x.

### Added

- **`scripts/init_project.sh`** — one-shot, idempotent Patrol + iOS setup for a fresh Flutter project. Covers Podfile, `RunnerUITests` UI Test Bundle target (built via the `xcodeproj` ruby gem), Xcode scheme `parallelizable="NO"` patch, Xcode 26 project format downgrade (`objectVersion 70 → 60`), `ENABLE_USER_SCRIPT_SANDBOXING NO`, scaffold `patrol_test/smoke_test.dart`, `.gitignore` entries, and `patrol_cli` activation. Supports `--dry-run`, `--skip-pod-install`, `--skip-pub-get`, `--patrol-version`, `--app-name`, `--bundle-id`, `--package-name`. See `README.md` §"Patrol 4.x 项目一次性 setup". (Issues 12, 13, 14)
- **fvm auto-detection in `build.sh` and `run_test.sh`** — walks up to 8 levels looking for `.fvm/flutter_sdk/bin` and prepends to PATH. Means monorepo/example layouts (where fvm config lives at the repo root but builds run from `example/`) work with no extra configuration.
- **`~/.pub-cache/bin` auto-append to PATH** in all relevant scripts. `patrol_cli` is installed there by `dart pub global activate` but pub doesn't add it to PATH automatically; this stops the "command not found: patrol" failure for users who skipped that step.
- **`reference/troubleshooting.md` Issues 12 – 16** documenting the `RunnerUITests` UI Test Bundle setup, CocoaPods + Xcode 26 `objectVersion` mismatch, `ENABLE_USER_SCRIPT_SANDBOXING` sandbox sandbox-deny, the `patrol test` parallel-clone bug, and the Xcode 26 + Flutter `_Testing_*.framework` dyld crash.

### Changed

- **`scripts/run_test.sh` no longer calls `patrol test` by default.** It now drives `xcodebuild test-without-building` directly against the bundle that `patrol build ios --simulator` produced. This bypasses two patrol_cli 4.3.x bugs at once: (a) it does not pass `-parallel-testing-enabled NO`, so xcodebuild clones the target sim into "Clone 1/2/3"; (b) it uses `-destination name=<X>` instead of `id=<UDID>`, so multiple iOS runtimes with the same device name confuse the runner. The new path explicitly passes `-parallel-testing-enabled NO -disable-concurrent-destination-testing -destination id=<UDID>` and injects `TEST_RUNNER_PATROL_TEST_PORT=8081` / `TEST_RUNNER_PATROL_APP_PORT=8082`. The legacy path is still reachable via `--use-patrol`. (Issue 15)
- **`scripts/build.sh` patches `xctestrun` files** to set `ParallelizationEnabled = false` as a redundant safety net (in case `run_test.sh` is bypassed by an alternate runner). (Issue 15)
- **`scripts/build.sh` auto-injects `_Testing_Foundation.framework`, `_Testing_CoreGraphics.framework`, `_Testing_CoreImage.framework`, `_Testing_UIKit.framework`, and `lib_TestingInterop.dylib`** into both `Runner.app/Frameworks/` and `RunnerUITests-Runner.app/Frameworks/` before `xcrun simctl install`, fixing the Xcode 26 + Flutter dyld crash that manifests as `The test runner timed out while preparing to run tests` after a 6-minute hang. No-op on Xcode < 26. (Issue 16)
- **`scripts/build.sh` also installs `RunnerUITests-Runner.app`**, not just `Runner.app`, so the test host bundle is present for the UI test runner.

### Fixed

- LICENSE: typo in MIT boilerplate (`MERCHANT©ABILITY` → `MERCHANTABILITY`).
- SKILL.md first-run checklist: outdated "Patrol 3.x" string → "Patrol 4.x".
- SKILL.md file inventory: `run_test.sh` description now reflects the v0.3 default xcodebuild path, not `patrol test`.

## [v0.2] — 2026-04

Plumbing pass: structured failure parsing, snapshotting, project-level activation snippets.

### Added

- `scripts/parse_failure.py` — extracts failures from `xcresult` bundles (Xcode 16+ `get test-results` API and pre-16 `--legacy` API), strips SDK frames (`package:flutter/`, `package:patrol/`, `dart:`), keeps app-level frames. Detects `xcresulttool` version via `xcrun xcresulttool --version` and dispatches to the right command.
- `scripts/sim_snapshot.sh` — a11y tree (default, via [`axe`](https://github.com/cameroncooke/AXe) CLI) or screenshot (fallback when `axe` is missing). Designed so the agent can ask "what's on screen" without spending a screenshot's worth of tokens every iteration.
- `templates/AGENTS_md_snippet.md` — Cursor / OpenAI Codex / other AGENTS-aware project-level activation.
- `templates/cursor_rule_snippet.mdc` — Cursor-native `.cursor/rules/` rule with `globs:` scoping (`pubspec.yaml` / `patrol_test/**` / `ios/Podfile`); activates only on Flutter/iOS files.
- `reference/patrol-patterns.md` — Patrol 4.x syntax cheatsheet (`$(...)`, `$.native`, `$.tester`, common matchers) to reduce hallucinated API usage when generating tests.

### Changed

- Standardized all script stdout to a single-line JSON object — even on error paths. The contract is enforced by `set -e` guards around external tool calls (so `set -euo pipefail` doesn't kill the script before the JSON is emitted).
- Hardened xcresult path resolution: switched from `ls -t build/*.xcresult | head -1` (which prefixes per-bundle headers when multiple bundles match) to `find build -maxdepth 1 -type d -name "ios_results_*.xcresult"`.

## [v0.1] — 2026-04

Initial public skill scaffolding.

### Added

- `SKILL.md` with YAML frontmatter (`description`, trigger phrases, anti-triggers).
- `reference/iteration-protocol.md` — the loop, stop conditions, state tracking JSON shape.
- `reference/failure-triage.md` — failure signal → category (5-A through 5-E) → permitted/forbidden actions table.
- `reference/troubleshooting.md` — first 11 known-issue entries (build / sim / pod / signing / xcresult).
- `scripts/boot_sim.sh` — idempotent simulator boot. Iterates *all* runtime keys instead of hardcoding an iOS version.
- `scripts/build.sh` (initial version) — `patrol build ios --simulator` + `xcrun simctl install`.
- `scripts/run_test.sh` (initial version) — wraps `patrol test`.
- `templates/patrol_test_template.dart` — starting point for generated tests.
- `templates/CLAUDE_md_snippet.md` — project-level activation for Claude Code / Claude Desktop.
- MIT `LICENSE`, `README.md`, `.github/` (issue + PR templates), `.gitignore`.
