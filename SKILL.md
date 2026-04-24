---
name: flutter-ios-agent-test
description: Run Flutter Patrol tests on iOS simulator and auto-fix Dart until they pass. Triggers on "test Flutter on simulator", "验证 Flutter 功能", "跑通流程", Patrol failures. Accepts .dart tests, natural-language, or Markdown specs. Not for Android-only, Flutter web, or non-Flutter iOS.
---

# Flutter iOS Agent Test

Build a Flutter app, install it on an iOS simulator, run tests, and iteratively fix code until tests pass — or stop cleanly when human help is needed.

## When to use

- User has a Flutter project and wants to validate a scenario on iOS simulator.
- User describes a flow in natural language and wants it turned into a runnable test + executed.
- User has Patrol tests that are failing and wants them triaged + fixed.
- User has a Markdown spec of expected behavior and wants it verified.

## When NOT to use

- Android-only testing → use platform-native tooling.
- Flutter web / desktop only.
- Non-Flutter iOS apps → use `ios-simulator-skill`.
- User only wants to *write* tests without running them.

## Core workflow

1. **Classify the input**: Patrol `.dart` file → go to step 3. Natural language / Markdown → step 2 first.
2. **Generate test** from natural language or Markdown using `templates/patrol_test_template.dart`. **Show the generated test to the user before running.**
3. **Run the iteration loop** defined in `reference/iteration-protocol.md`. This is the core contract — follow it literally.
4. **On failure**, classify using `reference/failure-triage.md` before touching any code.
5. **Stop conditions are hard limits.** If hit, report and ask the user. Do not silently continue.

## Hard rules (non-negotiable)

- **Never change an assertion to make a failing test pass.** If `expect(x, 5)` fails because `x == 4`, fix the app code or confirm with the user that the assertion is wrong — do not flip the expected value.
- **Never delete a failing test** to move on. If a test is genuinely broken, mark it `skip: 'reason'` and report it.
- **Never skip the triage step.** Even if the fix seems obvious, classify the failure first. Build failures and assertion failures look similar in output but need opposite responses.
- **Max iterations default = 6.** If the same test fails 3 times with the same root cause category, stop.
- **Roll back on divergence.** If 2 consecutive fixes do not shrink the error surface (same or new failures), revert to the last known-good state (via `git stash` or a throwaway branch) and report.

## Files in this skill

- `reference/iteration-protocol.md` — the loop, stop conditions, state tracking. **Read this before starting.**
- `reference/failure-triage.md` — failure signal → category → action mapping. **Read before applying any fix.**
- `reference/patrol-patterns.md` — Patrol syntax cheatsheet for generating/fixing tests.
- `reference/troubleshooting.md` — common simulator / build / signing issues.
- `scripts/boot_sim.sh` — boot a target simulator (idempotent).
- `scripts/build.sh` — `patrol build ios --simulator` + install.
- `scripts/run_test.sh` — `patrol test` with structured output.
- `scripts/parse_failure.py` — extract failure signal from xcresult/logs into JSON.
- `scripts/sim_snapshot.sh` — screenshot + a11y tree. **Use only when triage is inconclusive.**
- `templates/patrol_test_template.dart` — starting point for generated tests.
- `templates/CLAUDE_md_snippet.md` — project-level activation for Claude Code / Claude Desktop (paste into `CLAUDE.md`).
- `templates/AGENTS_md_snippet.md` — project-level activation for Cursor / OpenAI Codex / other AGENTS-aware agents (paste into `AGENTS.md`).
- `templates/cursor_rule_snippet.mdc` — Cursor-native project rule with `globs:` scoping (save as `.cursor/rules/flutter-ios-testing.mdc`); activates only on Flutter/iOS files.

## Token discipline

Simulator logs, xcresult dumps, and Flutter build output are enormous. Defaults:

- Scripts emit `--json` summaries; full logs stay on disk with paths returned.
- Never dump raw `xcrun simctl spawn ... log` output into context. Grep for the error, then stop.
- Screenshots are expensive. Use a11y tree (`sim_snapshot.sh --tree`) first; only take a screenshot if the a11y tree doesn't explain the failure.
- Between iterations, output one-line status: `iter 3/6 · build ok · 2/3 tests pass · fixing 5-C in login_screen.dart`.

## First-run checklist

On first invocation in a project, verify once and cache the result:

- `flutter --version` (≥ 3.22 recommended for Patrol 3.x)
- `patrol --version` (install with `dart pub global activate patrol_cli` if missing)
- Patrol configured in `pubspec.yaml` (`patrol:` dev_dependency) and `integration_test/` directory exists
- At least one iOS simulator available (`xcrun simctl list devices available`)

If any is missing, stop and tell the user exactly what to install. Do not try to auto-install globally without asking.
