---
name: flutter-patrol-pilot
description: Run Flutter Patrol tests on iOS simulator and auto-fix Dart until they pass. Nickname "fpp" — users may invoke this skill with short phrases like "fpp", "run fpp", "use fpp", "/fpp", "跑一下 fpp", "用 fpp 验证一下", "fpp 跑通流程"; treat any of these as an explicit activation request. Also triggers on "test Flutter on simulator", "验证 Flutter 功能", "跑通流程", Patrol failures. Accepts .dart tests, natural-language, or Markdown specs. Not for Android-only, Flutter web, or non-Flutter iOS.
---

# Flutter Patrol Pilot

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
- `scripts/init_project.sh` — **one-shot Patrol+iOS setup** for a fresh Flutter project (Podfile, RunnerUITests target, xcscheme, Xcode 26 fixes, scaffold). Idempotent; run from project root. See README §"Patrol 4.x 项目一次性 setup".
- `scripts/boot_sim.sh` — boot a target simulator (idempotent).
- `scripts/build.sh` — `patrol build ios --simulator` + install.
- `scripts/run_test.sh` — runs the prebuilt test bundle via `xcodebuild test-without-building` with parallel testing disabled (v0.3+ default); falls back to `patrol test` only with `--use-patrol`. Emits structured JSON.
- `scripts/parse_failure.py` — extract failure signal from xcresult/logs into JSON.
- `scripts/sim_snapshot.sh` — screenshot + a11y tree. **Use only when triage is inconclusive.**
- `scripts/install_axe.sh` — install AXe CLI (optional dep for `sim_snapshot.sh --tree`). **Run only after explicit user consent** — see §"Optional: AXe CLI" below.
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

- `flutter --version` (≥ 3.22; Patrol 4.x requires iOS deployment target ≥ 13.0)
- `patrol --version` (install with `dart pub global activate patrol_cli` if missing; this skill is developed against `patrol_cli 4.3.1`)
- Patrol configured in `pubspec.yaml` (`patrol:` dev_dependency) and a `patrol_test/` directory with at least one test exists (Patrol 4.x default; 3.x's `integration_test/` layout is deprecated)
- At least one iOS simulator available (`xcrun simctl list devices available`)

**If the project has never been Patrol-initialized** (no `ios/RunnerUITests/` target, or Podfile missing `use_modular_headers!`), run the one-shot initializer **before** anything else:

```bash
bash <skill>/scripts/init_project.sh
```

It is idempotent — safe to re-run to repair a partially-configured project. Pass `--dry-run` first if you want to see what it will change. See README §"Patrol 4.x 项目一次性 setup" for the full step table.

## Optional: AXe CLI (for token-cheap a11y trees)

`sim_snapshot.sh --tree` uses [`axe`](https://github.com/cameroncooke/AXe) to dump the iOS simulator's accessibility tree as compact text — typically **~10× cheaper in tokens** than a screenshot for triage purposes. AXe is **optional**: if missing, `sim_snapshot.sh` automatically falls back to a screenshot and tags the JSON output with `warning: "axe not installed..."`.

**Agent contract for AXe:**

- Do **not** install AXe silently. The "do not auto-install globally without asking" rule above applies.
- `init_project.sh` reports AXe presence in its summary JSON as `axe_present: bool` and, when missing, appends an `OPTIONAL:` entry to `next_steps[]`.
- When you (the agent) hit a category 5-E (inconclusive) failure and decide to call `sim_snapshot.sh --tree`, **first check** the latest `init_project.sh` summary or run `command -v axe`:
  - If `axe` is present → just call `sim_snapshot.sh --tree`.
  - If `axe` is absent → **ask the user** something like: *"AXe isn't installed. Want me to install it via Homebrew (`brew install cameroncooke/axe/axe`) so a11y trees are ~10× cheaper than screenshots? Yes / No / Just use screenshot."*
    - On **Yes** → `bash <skill>/scripts/install_axe.sh`, then proceed with `--tree`.
    - On **No / Just use screenshot** → call `sim_snapshot.sh --tree` anyway; it'll fall back to screenshot and warn. Do not ask again in the same session.

`install_axe.sh` is idempotent: re-running when AXe is already installed is a no-op (`action: "noop"`). Use `--dry-run` to preview, `--force` to reinstall.

If any prerequisite is missing, stop and tell the user exactly what to install. Do not try to auto-install globally without asking.
